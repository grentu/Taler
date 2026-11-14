import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../privacy/privacy_firewall.dart';
import '../privacy/privacy_settings.dart';
import '../privacy/spoof_profile.dart';
import '../privacy/spoofing_service.dart';
import '../protocol/opcode.dart';
import '../protocol/packet.dart';

enum TalerConnectionState { disconnected, connecting, connected, online }

/// Транспортный уровень MAX.
///
/// Обеспечивает:
/// - основное подключение по прямому бинарному TLS-сокету к `api2.oneme.ru:443`
///   (с резервным хостом `api.oneme.ru:443` и поддержкой сертификатов Минцифры)
///   и автоматическим фоллбэком на `wss://api.oneme.ru/websocket` в WEB-режиме;
/// - потоковую сборку бинарных кадров через [TalerPacketReceiver];
/// - хендшейк `Opcode.sessionInit (6)` с виртуальным профилем устройства;
/// - строгую фильтрацию всех пакетов через [PrivacyFirewall];
/// - поддержание сессии (ping/pong) с учётом флага невидимки [PrivacySettings.ghostModeOnline];
/// - авто-реконнект с экспоненциальной задержкой.
class TalerSession {
  static const List<String> tlsHosts = ['api2.oneme.ru', 'api.oneme.ru'];
  static const int tlsPort = 443;
  static const String wsEndpoint = 'wss://api.oneme.ru/websocket';
  static const String wsOrigin = 'https://web.max.ru';
  static const Duration connectTimeout = Duration(seconds: 12);
  static const Duration requestTimeout = Duration(seconds: 30);
  static const Duration pingInterval = Duration(seconds: 10);

  final PrivacyFirewall firewall;
  final PrivacySettings privacySettings;
  final SpoofingService spoofingService;

  SecureSocket? _tlsSocket;
  WebSocket? _wsSocket;
  StreamSubscription<dynamic>? _socketSub;
  final TalerPacketReceiver _receiver = TalerPacketReceiver();

  Timer? _pingTimer;
  Timer? _reconnectTimer;

  final Map<int, Completer<TalerPacket>> _pending = {};
  final _stateController = StreamController<TalerConnectionState>.broadcast();
  final _pushController = StreamController<TalerPacket>.broadcast();

  TalerConnectionState _state = TalerConnectionState.disconnected;
  int _seq = 0;
  int _sessionEpoch = 0;
  int _reconnectAttempt = 0;
  bool _autoReconnect = false;
  bool _isAttemptingConnect = false;
  bool _disposed = false;
  int? _callsSeed;
  String? _activeDeviceId;
  Future<void> Function()? onReconnected;

  TalerSession({
    required this.firewall,
    required this.privacySettings,
    required this.spoofingService,
  });

  TalerConnectionState get state => _state;
  Stream<TalerConnectionState> get stateStream => _stateController.stream;
  Stream<TalerPacket> get pushStream => _pushController.stream;
  int? get callsSeed => _callsSeed;
  String? get activeDeviceId => _activeDeviceId;
  int get sessionEpoch => _sessionEpoch;
  bool get isOnline => _state == TalerConnectionState.online;
  bool get _hasSocket => _tlsSocket != null || _wsSocket != null;

  /// Устанавливает соединение с сервером MAX и выполняет хендшейк `SESSION_INIT`.
  Future<Map<String, dynamic>> connect({
    bool enableReconnect = true,
    bool forceReconnect = false,
  }) async {
    if (_disposed) {
      throw StateError('TalerSession уже уничтожена');
    }
    if (!forceReconnect && _state == TalerConnectionState.online && _hasSocket) {
      return const {};
    }
    if (forceReconnect && _hasSocket) {
      _failPending(const TalerPacketException('Переподключение сессии'));
      await _cleanupSocketOnly();
      _setState(TalerConnectionState.disconnected);
    }

    _autoReconnect = enableReconnect;
    _isAttemptingConnect = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _setState(TalerConnectionState.connecting);

    final active = spoofingService.activeProfile;
    _activeDeviceId = active.deviceId;

    // Даже при выключенном ручном спуфинге Taler использует обезличенный
    // профиль, чтобы никогда не передавать данные реального железа.
    final SpoofProfile effectiveProfile = privacySettings.spoofingEnabled
        ? active
        : SpoofingService.buildFromPreset(
            SpoofingService.presets.first,
            deviceId: active.deviceId,
            instanceId: active.instanceId,
            clientSessionId: active.clientSessionId,
          );

    Object? lastError;

    try {
      // 1. Основной транспорт: прямой бинарный TLS-сокет (выдаёт callsSeed).
      for (final host in tlsHosts) {
        try {
          return await _connectViaTls(host, effectiveProfile);
        } catch (e) {
          lastError = e;
          await _cleanupSocketOnly();
        }
      }

      // 2. Резервный транспорт: WebSocket в принудительном режиме deviceType=WEB
      // (wss://api.oneme.ru/websocket принимает только WEB и отклоняет ANDROID).
      try {
        return await _connectViaWebSocket(effectiveProfile);
      } catch (e) {
        lastError = e;
        await _cleanupSocketOnly();
      }
    } finally {
      _isAttemptingConnect = false;
    }

    _setState(TalerConnectionState.disconnected);
    throw lastError;
  }

  Future<Map<String, dynamic>> _connectViaTls(
    String host,
    SpoofProfile profile,
  ) async {
    final socket = await SecureSocket.connect(
      host,
      tlsPort,
      timeout: connectTimeout,
      // Допускаем корневой и промежуточный сертификаты Минцифры для *.oneme.ru.
      onBadCertificate: (X509Certificate cert) =>
          host == 'api2.oneme.ru' || host == 'api.oneme.ru',
    );

    _tlsSocket = socket;
    _receiver.reset();
    _setState(TalerConnectionState.connected);

    _socketSub = socket.listen(
      _onTlsChunk,
      onError: (Object error) => _handleDrop('Ошибка TLS-сокета: $error'),
      onDone: () => _handleDrop('Соединение закрыто сервером'),
      cancelOnError: true,
    );

    final handshakePacket = await request(
      Opcode.sessionInit,
      profile.toSessionInitPayload(forceWeb: false),
    );
    return _finalizeHandshake(handshakePacket);
  }

  Future<Map<String, dynamic>> _connectViaWebSocket(SpoofProfile profile) async {
    final socket = await WebSocket.connect(
      wsEndpoint,
      headers: <String, Object>{
        'Origin': wsOrigin,
        'User-Agent': profile.userAgent,
      },
    ).timeout(connectTimeout);

    _wsSocket = socket;
    _receiver.reset();
    _setState(TalerConnectionState.connected);

    _socketSub = socket.listen(
      _onWsFrame,
      onError: (Object error) => _handleDrop('Ошибка WebSocket: $error'),
      onDone: () => _handleDrop('Соединение закрыто сервером'),
      cancelOnError: true,
    );

    final handshakePacket = await request(
      Opcode.sessionInit,
      profile.toSessionInitPayload(forceWeb: true),
    );
    return _finalizeHandshake(handshakePacket);
  }

  Map<String, dynamic> _finalizeHandshake(TalerPacket handshakePacket) {
    final payload = handshakePacket.payloadAsMap ?? const <String, dynamic>{};
    final rawSeed = payload['callsSeed'] ?? payload['seed'];
    if (rawSeed is num) {
      _callsSeed = rawSeed.toInt();
    } else {
      _callsSeed = null;
    }

    _sessionEpoch++;
    _reconnectAttempt = 0;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _setState(TalerConnectionState.online);
    _startPingLoop();
    return payload;
  }

  /// Отправляет запрос с проверкой через [PrivacyFirewall].
  Future<TalerPacket> request(
    int opcode,
    Object? payload, {
    bool throwOnError = true,
    Duration? timeout,
  }) {
    final nextSeq = (_seq % 32000) + 1;
    final decision = firewall.inspectOutgoing(opcode, payload, seq: nextSeq);
    if (!decision.allowed) {
      return Future<TalerPacket>.value(
        TalerPacket(
          cmd: CmdType.ok,
          seq: nextSeq,
          opcode: opcode,
          payload: const {'blockedByTaler': true},
        ),
      );
    }

    if (!_hasSocket) {
      return Future<TalerPacket>.error(
        const TalerPacketException('Нет подключения к серверу MAX'),
      );
    }

    _seq = nextSeq;
    final seq = _seq;
    final completer = Completer<TalerPacket>();
    _pending[seq] = completer;

    final encoded = TalerFraming.encode(
      cmd: CmdType.request,
      seq: seq,
      opcode: opcode,
      payload: payload,
    );
    _writeRaw(encoded);

    return completer.future.timeout(
      timeout ?? requestTimeout,
      onTimeout: () {
        _pending.remove(seq);
        throw TalerPacketException(
          'Таймаут запроса ${Opcode.name(opcode)}',
          opcode: opcode,
        );
      },
    ).then((packet) {
      if (throwOnError && packet.isError) {
        throw TalerPacketException.fromFrame(packet);
      }
      return packet;
    });
  }

  /// Отправляет ping с учётом флага невидимки (`interactive: false`).
  Future<void> sendPing() async {
    if (!isOnline) return;
    try {
      await request(
        Opcode.ping,
        {'interactive': !privacySettings.ghostModeOnline},
        throwOnError: false,
        timeout: const Duration(seconds: 8),
      );
    } catch (_) {}
  }

  void _writeRaw(Uint8List bytes) {
    final tls = _tlsSocket;
    if (tls != null) {
      tls.add(bytes);
      return;
    }
    _wsSocket?.add(bytes);
  }

  void _onTlsChunk(Uint8List chunk) {
    final List<Uint8List> rawFrames;
    try {
      rawFrames = _receiver.feedFrames(chunk);
    } catch (_) {
      return;
    }
    for (final raw in rawFrames) {
      try {
        final packet = TalerFraming.decode(raw);
        _dispatchPacket(packet);
      } catch (_) {
        // Игнорируем единичный битый кадр, не прерывая остальные в чанке.
      }
    }
  }

  void _onWsFrame(dynamic raw) {
    if (raw is! List<int>) return;
    try {
      final frame = TalerFraming.decode(Uint8List.fromList(raw));
      _dispatchPacket(frame);
    } catch (_) {}
  }

  void _dispatchPacket(TalerPacket frame) {
    final allowed = firewall.inspectIncoming(
      frame.opcode,
      frame.payload,
      seq: frame.seq,
    );
    if (!allowed) return;

    if (frame.cmd == CmdType.request) {
      if (frame.opcode == Opcode.ping) {
        _writeRaw(
          TalerFraming.encode(
            cmd: CmdType.ok,
            seq: frame.seq,
            opcode: Opcode.ping,
          ),
        );
        return;
      }
      if (!_pushController.isClosed) {
        _pushController.add(frame);
      }
      return;
    }

    final completer = _pending.remove(frame.seq);
    if (completer != null && !completer.isCompleted) {
      completer.complete(frame);
    }
  }

  void _startPingLoop() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(pingInterval, (_) => sendPing());
  }

  void _handleDrop(String reason) {
    _cleanupSocketOnly();
    _failPending(TalerPacketException(reason));
    if (_isAttemptingConnect) return;
    if (_state != TalerConnectionState.disconnected) {
      _setState(TalerConnectionState.disconnected);
    }
    if (_autoReconnect && !_disposed) {
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    final delaySec = (2 * (1 << _reconnectAttempt.clamp(0, 3))).clamp(2, 15);
    _reconnectAttempt++;
    _reconnectTimer = Timer(Duration(seconds: delaySec), () async {
      if (_disposed || !_autoReconnect) return;
      try {
        await connect(enableReconnect: true);
        if (onReconnected != null) {
          await onReconnected!();
        }
      } catch (_) {
        if (_autoReconnect && !_disposed) {
          _scheduleReconnect();
        }
      }
    });
  }

  void _failPending(TalerPacketException error) {
    for (final completer in _pending.values) {
      if (!completer.isCompleted) {
        completer.completeError(error);
      }
    }
    _pending.clear();
  }

  Future<void> _cleanupSocketOnly() async {
    _pingTimer?.cancel();
    _pingTimer = null;
    await _socketSub?.cancel();
    _socketSub = null;
    _receiver.reset();
    try {
      await _tlsSocket?.close();
    } catch (_) {}
    _tlsSocket?.destroy();
    _tlsSocket = null;
    try {
      await _wsSocket?.close();
    } catch (_) {}
    _wsSocket = null;
  }

  Future<void> disconnect() async {
    _autoReconnect = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _failPending(const TalerPacketException('Сессия закрыта'));
    await _cleanupSocketOnly();
    _setState(TalerConnectionState.disconnected);
  }

  void _setState(TalerConnectionState next) {
    if (_state == next) return;
    _state = next;
    if (!_stateController.isClosed) {
      _stateController.add(next);
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    await disconnect();
    await _stateController.close();
    await _pushController.close();
  }
}

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

/// Канал, через который установлена текущая сессия.
enum TalerTransport { none, tls, webSocket }

/// Транспортный уровень MAX.
///
/// Обеспечивает:
/// - основное подключение по прямому бинарному TLS-сокету к api2.oneme.ru:443
///   (с резервным хостом api.oneme.ru:443 и поддержкой сертификатов Минцифры)
///   и фоллбэк на wss://api.oneme.ru/websocket в WEB-режиме;
/// - одно общее подключение на всех вызывающих (повторный connect() ждёт уже
///   идущий, а не начинает второй параллельно);
/// - короткие таймауты на каждый шаг, чтобы недоступный хост не держал
///   экран входа десятки секунд;
/// - хендшейк Opcode.sessionInit (6) с виртуальным или постоянным профилем;
/// - строгую фильтрацию всех пакетов через [PrivacyFirewall];
/// - ping/pong с учётом флага невидимки и авто-реконнект с задержкой.
class TalerSession {
  static const List<String> tlsHosts = ['api2.oneme.ru', 'api.oneme.ru'];
  static const int tlsPort = 443;
  static const String wsEndpoint = 'wss://api.oneme.ru/websocket';
  static const String wsOrigin = 'https://web.max.ru';

  /// TCP + TLS рукопожатие с одним хостом.
  static const Duration connectTimeout = Duration(seconds: 6);

  /// Ответ на SESSION_INIT. Живой сервер отвечает за доли секунды.
  static const Duration handshakeTimeout = Duration(seconds: 8);

  /// Обычные запросы после подключения.
  static const Duration requestTimeout = Duration(seconds: 20);

  /// Закрытие сокета не должно блокировать переподключение.
  static const Duration closeTimeout = Duration(seconds: 2);
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
  TalerTransport _transport = TalerTransport.none;
  int _seq = 0;
  int _sessionEpoch = 0;
  int _reconnectAttempt = 0;
  bool _autoReconnect = false;
  bool _isAttemptingConnect = false;
  bool _disposed = false;
  int? _callsSeed;
  String? _activeDeviceId;
  String? _lastConnectError;
  Future<Map<String, dynamic>>? _connectInFlight;
  Future<void> Function()? onReconnected;

  /// Подключаться сразу через веб-шлюз (deviceType WEB), минуя TLS.
  bool preferWebGateway = false;

  /// В тестах мгновенно отклоняет попытку подключения без сетевых вызовов.
  bool rejectConnectForTest = false;

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
  TalerTransport get transport => _transport;
  String? get lastConnectError => _lastConnectError;
  bool get _hasSocket => _tlsSocket != null || _wsSocket != null;

  /// Профиль, который уйдёт в SESSION_INIT: виртуальный при включённой
  /// маскировке или постоянный профиль этого устройства при выключенной.
  SpoofProfile get effectiveProfile => privacySettings.spoofingEnabled
      ? spoofingService.activeProfile
      : spoofingService.nativeProfile;

  /// Устанавливает соединение с сервером MAX и выполняет хендшейк SESSION_INIT.
  ///
  /// Если подключение уже идёт, возвращает его же Future.
  Future<Map<String, dynamic>> connect({
    bool enableReconnect = true,
    bool forceReconnect = false,
  }) {
    if (rejectConnectForTest) {
      return Future<Map<String, dynamic>>.error(
        const TalerPacketException('Нет подключения к серверу MAX'),
      );
    }
    if (_disposed) {
      return Future<Map<String, dynamic>>.error(
        StateError('TalerSession уже уничтожена'),
      );
    }
    if (!forceReconnect && _state == TalerConnectionState.online && _hasSocket) {
      return Future<Map<String, dynamic>>.value(const <String, dynamic>{});
    }
    final inFlight = _connectInFlight;
    if (inFlight != null) {
      if (!forceReconnect) return inFlight;
      // Дожидаемся текущей попытки и только потом переподключаемся.
      return inFlight.then<void>((_) {}, onError: (Object _) {}).then(
            (_) => connect(
              enableReconnect: enableReconnect,
              forceReconnect: true,
            ),
          );
    }
    final attempt = _connectImpl(
      enableReconnect: enableReconnect,
      forceReconnect: forceReconnect,
    );
    _connectInFlight = attempt;
    attempt.then<void>((_) {}, onError: (Object _) {}).whenComplete(() {
      if (identical(_connectInFlight, attempt)) _connectInFlight = null;
    });
    return attempt;
  }

  Future<Map<String, dynamic>> _connectImpl({
    required bool enableReconnect,
    required bool forceReconnect,
  }) async {
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

    final profile = effectiveProfile;
    _activeDeviceId = profile.deviceId;

    Object? lastError;
    try {
      if (!preferWebGateway) {
        // 1. Основной транспорт: прямой бинарный TLS-сокет (выдаёт callsSeed).
        for (final host in tlsHosts) {
          try {
            return await _connectViaTls(host, profile);
          } catch (e) {
            lastError = e;
            await _cleanupSocketOnly();
          }
        }
      }

      // 2. Веб-шлюз: WebSocket в режиме deviceType=WEB.
      try {
        return await _connectViaWebSocket(profile);
      } catch (e) {
        lastError = e;
        await _cleanupSocketOnly();
      }
    } finally {
      _isAttemptingConnect = false;
    }

    _lastConnectError = lastError.toString();
    _transport = TalerTransport.none;
    _setState(TalerConnectionState.disconnected);
    if (_autoReconnect && !_disposed) {
      _scheduleReconnect();
    }
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
    socket.setOption(SocketOption.tcpNoDelay, true);

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
      timeout: handshakeTimeout,
    );
    return _finalizeHandshake(handshakePacket, TalerTransport.tls);
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
      timeout: handshakeTimeout,
    );
    return _finalizeHandshake(handshakePacket, TalerTransport.webSocket);
  }

  Map<String, dynamic> _finalizeHandshake(
    TalerPacket handshakePacket,
    TalerTransport transport,
  ) {
    final payload = handshakePacket.payloadAsMap ?? const <String, dynamic>{};
    final rawSeed = payload['callsSeed'] ?? payload['seed'];
    if (rawSeed is num) {
      _callsSeed = rawSeed.toInt();
    } else {
      _callsSeed = null;
    }

    _transport = transport;
    _lastConnectError = null;
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
    try {
      _writeRaw(encoded);
    } catch (e) {
      _pending.remove(seq);
      return Future<TalerPacket>.error(
        TalerPacketException('Не удалось отправить запрос: $e', opcode: opcode),
      );
    }

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

  /// Отправляет ping с учётом флага невидимки (interactive: false).
  /// При сбое/таймауте сбрасывает полуоткрытый сокет и запускает реконнект.
  Future<void> sendPing({Duration timeout = const Duration(seconds: 6)}) async {
    if (!isOnline || _disposed) return;
    final epoch = _sessionEpoch;
    try {
      await request(
        Opcode.ping,
        {'interactive': !privacySettings.ghostModeOnline},
        throwOnError: false,
        timeout: timeout,
      );
    } catch (_) {
      if (_disposed || !isOnline || _sessionEpoch != epoch) return;
      _handleDrop('Keepalive ping не ответил');
    }
  }

  /// Вызывается при возвращении приложения на экран: проверяет живой ли сокет
  /// или немедленно запускает переподключение.
  void wakeUp() {
    if (_disposed || !_autoReconnect) return;
    switch (_state) {
      case TalerConnectionState.disconnected:
        _reconnectAttempt = 0;
        _reconnectTimer?.cancel();
        _reconnectTimer = null;
        unawaited(
          connect(enableReconnect: true).then<void>((_) async {
            if (onReconnected != null) {
              await onReconnected!();
            }
          }, onError: (Object _) {}),
        );
      case TalerConnectionState.connecting:
      case TalerConnectionState.connected:
        _reconnectAttempt = 0;
      case TalerConnectionState.online:
        unawaited(sendPing(timeout: const Duration(seconds: 3)));
    }
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
      _decodeAndDispatch(raw);
    }
  }

  void _onWsFrame(dynamic raw) {
    if (raw is! List<int>) return;
    _decodeAndDispatch(raw is Uint8List ? raw : Uint8List.fromList(raw));
  }

  void _decodeAndDispatch(Uint8List raw) {
    final TalerPacket packet;
    try {
      packet = TalerFraming.decode(raw);
    } catch (e) {
      _failUndecodable(raw, e);
      return;
    }
    _dispatchPacket(packet);
  }

  /// Если не удалось разобрать ответ на наш запрос, сразу сообщаем об ошибке
  /// вместо ожидания полного таймаута.
  void _failUndecodable(Uint8List raw, Object error) {
    if (raw.length < TalerFraming.headerSize) return;
    final cmd = raw[1];
    if (cmd == CmdType.request) return;
    final seq = ByteData.sublistView(raw).getUint16(2, Endian.big);
    final completer = _pending.remove(seq);
    if (completer != null && !completer.isCompleted) {
      completer.completeError(
        TalerPacketException('Не удалось разобрать ответ сервера: $error'),
      );
    }
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
    _transport = TalerTransport.none;
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
      } on TalerPacketException catch (e) {
        if (e.isSessionExpired) {
          _autoReconnect = false;
          await disconnect();
          return;
        }
        await _cleanupSocketOnly();
        _transport = TalerTransport.none;
        _setState(TalerConnectionState.disconnected);
        if (_autoReconnect && !_disposed) {
          _scheduleReconnect();
        }
      } catch (_) {
        await _cleanupSocketOnly();
        _transport = TalerTransport.none;
        _setState(TalerConnectionState.disconnected);
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
    final sub = _socketSub;
    final tls = _tlsSocket;
    final ws = _wsSocket;
    _socketSub = null;
    _tlsSocket = null;
    _wsSocket = null;
    _receiver.reset();
    try {
      await sub?.cancel().timeout(closeTimeout);
    } catch (_) {}
    if (tls != null) {
      try {
        await tls.close().timeout(closeTimeout);
      } catch (_) {}
      tls.destroy();
    }
    if (ws != null) {
      try {
        await ws.close().timeout(closeTimeout);
      } catch (_) {}
    }
  }

  Future<void> disconnect() async {
    _autoReconnect = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _failPending(const TalerPacketException('Сессия закрыта'));
    await _cleanupSocketOnly();
    _transport = TalerTransport.none;
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

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../privacy/privacy_firewall.dart';
import '../privacy/privacy_settings.dart';
import '../privacy/spoofing_service.dart';
import '../protocol/opcode.dart';
import '../protocol/packet.dart';

enum TalerConnectionState { disconnected, connecting, connected, online }

/// Транспортный уровень MAX поверх WebSocket.
///
/// Обеспечивает:
/// - подключение к `wss://api.oneme.ru/websocket` с подменой `User-Agent`;
/// - бинарный хендшейк `Opcode.sessionInit (6)` с виртуальным профилем устройства;
/// - строгую фильтрацию всех пакетов через [PrivacyFirewall];
/// - поддержание сессии (ping/pong) с учётом флага невидимки [PrivacySettings.ghostModeOnline];
/// - авто-реконнект с экспоненциальной задержкой.
class TalerSession {
  static const String endpoint = 'wss://api.oneme.ru/websocket';
  static const String origin = 'https://web.max.ru';
  static const Duration requestTimeout = Duration(seconds: 30);
  static const Duration pingInterval = Duration(seconds: 25);

  final PrivacyFirewall firewall;
  final PrivacySettings privacySettings;
  final SpoofingService spoofingService;

  WebSocket? _socket;
  StreamSubscription<dynamic>? _socketSub;
  Timer? _pingTimer;
  Timer? _reconnectTimer;

  final Map<int, Completer<TalerPacket>> _pending = {};
  final _stateController = StreamController<TalerConnectionState>.broadcast();
  final _pushController = StreamController<TalerPacket>.broadcast();

  TalerConnectionState _state = TalerConnectionState.disconnected;
  int _seq = 0;
  int _reconnectAttempt = 0;
  bool _autoReconnect = false;
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
  bool get isOnline => _state == TalerConnectionState.online;

  /// Устанавливает соединение с сервером MAX и выполняет хендшейк `SESSION_INIT`.
  Future<Map<String, dynamic>> connect({bool enableReconnect = true}) async {
    if (_disposed) {
      throw StateError('TalerSession уже уничтожена');
    }
    if (_state == TalerConnectionState.online && _socket != null) {
      return const {};
    }

    _autoReconnect = enableReconnect;
    _reconnectTimer?.cancel();
    _setState(TalerConnectionState.connecting);

    final profile = spoofingService.activeProfile;
    _activeDeviceId = profile.deviceId;

    // Даже при отключённом выборе кастомного профиля Taler использует
    // обезличенный профиль, чтобы никогда не передавать данные реального железа.
    final userAgentHeader = profile.userAgent;
    final handshakeUserAgent = privacySettings.spoofingEnabled
        ? profile.toHandshakeUserAgent()
        : SpoofingService.buildFromPreset(
            SpoofingService.presets.last,
            deviceId: profile.deviceId,
            instanceId: profile.instanceId,
          ).toHandshakeUserAgent();

    try {
      final socket = await WebSocket.connect(
        endpoint,
        headers: <String, Object>{
          'Origin': origin,
          'User-Agent': userAgentHeader,
        },
      ).timeout(const Duration(seconds: 20));

      _socket = socket;
      _setState(TalerConnectionState.connected);

      _socketSub = socket.listen(
        _onFrame,
        onError: (Object error) => _handleDrop('Ошибка сокета: $error'),
        onDone: () => _handleDrop('Соединение закрыто сервером'),
        cancelOnError: true,
      );

      final handshakePacket = await request(
        Opcode.sessionInit,
        <String, Object?>{
          'userAgent': handshakeUserAgent,
          'deviceId': profile.deviceId,
        },
      );

      final payload = handshakePacket.payloadAsMap ?? const <String, dynamic>{};
      final rawSeed = payload['callsSeed'] ?? payload['seed'];
      if (rawSeed is num) {
        _callsSeed = rawSeed.toInt();
      }

      _reconnectAttempt = 0;
      _setState(TalerConnectionState.online);
      _startPingLoop();
      return payload;
    } catch (e) {
      await _cleanupSocketOnly();
      _setState(TalerConnectionState.disconnected);
      rethrow;
    }
  }

  /// Отправляет запрос с проверкой через [PrivacyFirewall].
  Future<TalerPacket> request(
    int opcode,
    Object? payload, {
    bool throwOnError = true,
  }) {
    final nextSeq = _seq + 1;
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

    final socket = _socket;
    if (socket == null) {
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
    socket.add(encoded);

    return completer.future.timeout(
      requestTimeout,
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
      );
    } catch (_) {}
  }

  void _onFrame(dynamic raw) {
    if (raw is! List<int>) return;
    final TalerPacket frame;
    try {
      frame = TalerFraming.decode(Uint8List.fromList(raw));
    } catch (_) {
      return;
    }

    final allowed = firewall.inspectIncoming(
      frame.opcode,
      frame.payload,
      seq: frame.seq,
    );
    if (!allowed) return;

    if (frame.cmd == CmdType.request) {
      if (frame.opcode == Opcode.ping) {
        _socket?.add(
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
    try {
      await _socket?.close();
    } catch (_) {}
    _socket = null;
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

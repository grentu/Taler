import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../privacy/privacy_firewall.dart';

/// Результат завершённой записи голосового сообщения.
class TalerRecordedVoice {
  final String path;
  final int durationMs;

  const TalerRecordedVoice({required this.path, required this.durationMs});
}

/// Состояние нативного аудиоплеера.
class TalerAudioState {
  final bool ready;
  final bool playing;
  final int positionMs;
  final int durationMs;
  final bool completed;
  final String? error;

  const TalerAudioState({
    this.ready = false,
    this.playing = false,
    this.positionMs = 0,
    this.durationMs = 0,
    this.completed = false,
    this.error,
  });
}

/// Мост к нативным возможностям Android/Windows без сторонних SDK и телеметрии:
/// уведомления, открытие URL и файлов, воспроизведение и запись голосовых.
class TalerNativeBridge {
  TalerNativeBridge._() {
    if (_isAndroid) {
      _channel.setMethodCallHandler(_handleIncomingCall);
    }
  }

  static final TalerNativeBridge instance = TalerNativeBridge._();
  static const MethodChannel _channel = MethodChannel('io.grentu.taler/native');

  final StreamController<int> _notificationTapCtrl =
      StreamController<int>.broadcast();

  Stream<int> get onNotificationTap => _notificationTapCtrl.stream;

  bool get _isTest => Platform.environment['FLUTTER_TEST'] == 'true';
  bool get _isAndroid => !_isTest && !kIsWeb && Platform.isAndroid;
  bool get _isWindows => !_isTest && !kIsWeb && Platform.isWindows;

  bool get supportsInlineVideo => _isAndroid;
  bool get supportsVoiceRecording => _isAndroid;

  /// Хук для перехвата открытий URL и уведомлений в юнит/виджет-тестах.
  @visibleForTesting
  Future<bool> Function(String url)? testOpenUrlHandler;

  @visibleForTesting
  Future<bool> Function(String path)? testOpenFileHandler;

  @visibleForTesting
  void Function(int chatId, String title, String body)?
      testNotificationHandler;

  Future<dynamic> _handleIncomingCall(MethodCall call) async {
    if (call.method == 'onNotificationTap') {
      final raw = call.arguments;
      final chatId = raw is num ? raw.toInt() : int.tryParse('$raw');
      if (chatId != null && chatId != 0 && !_notificationTapCtrl.isClosed) {
        _notificationTapCtrl.add(chatId);
      }
    }
    return null;
  }

  Future<bool> requestNotificationPermission() async {
    if (!_isAndroid) return true;
    try {
      return await _channel.invokeMethod<bool>(
            'requestNotificationPermission',
          ) ??
          false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> hasNotificationPermission() async {
    if (!_isAndroid) return true;
    try {
      return await _channel.invokeMethod<bool>('hasNotificationPermission') ??
          false;
    } catch (_) {
      return false;
    }
  }

  Future<void> showMessageNotification({
    required int chatId,
    required String title,
    required String body,
    String? sender,
  }) async {
    final handler = testNotificationHandler;
    if (handler != null) {
      handler(chatId, title, body);
      return;
    }
    if (!_isAndroid) return;
    try {
      await _channel.invokeMethod<void>('showMessageNotification', {
        'chatId': chatId,
        'title': title,
        'body': body,
        if (sender != null && sender.isNotEmpty) 'sender': sender,
      });
    } catch (_) {}
  }

  Future<bool> openNotificationSettings() async {
    if (!_isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('openNotificationSettings') ??
          false;
    } catch (_) {
      return false;
    }
  }

  Future<void> cancelChatNotification(int chatId) async {
    if (!_isAndroid) return;
    try {
      await _channel.invokeMethod<void>('cancelChatNotification', {
        'chatId': chatId,
      });
    } catch (_) {}
  }

  Future<int?> consumeInitialNotificationChatId() async {
    if (!_isAndroid) return null;
    try {
      final raw = await _channel.invokeMethod<dynamic>(
        'getInitialNotificationChatId',
      );
      if (raw is num) return raw.toInt();
      return int.tryParse('$raw');
    } catch (_) {
      return null;
    }
  }

  /// Открывает внешнюю ссылку в системном браузере.
  Future<bool> openUrl(String rawUrl) async {
    var trimmed = rawUrl.trim();
    if (trimmed.isEmpty) return false;
    if (!trimmed.contains('://')) {
      trimmed = 'https://$trimmed';
    }
    final uri = Uri.tryParse(trimmed);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      return false;
    }

    final testHandler = testOpenUrlHandler;
    if (testHandler != null) {
      return testHandler(uri.toString());
    }
    if (_isAndroid) {
      try {
        return await _channel.invokeMethod<bool>('openUrl', {
              'url': uri.toString(),
            }) ??
            false;
      } catch (_) {
        return false;
      }
    }
    if (_isWindows) {
      try {
        await Process.start(
          'cmd',
          ['/c', 'start', '', uri.toString()],
          runInShell: false,
        );
        return true;
      } catch (_) {
        return false;
      }
    }
    return false;
  }

  /// Открывает локальный файл в системном приложении.
  Future<bool> openFile(String path, {String? mimeType}) async {
    if (path.trim().isEmpty) return false;
    final testHandler = testOpenFileHandler;
    if (testHandler != null) {
      return testHandler(path);
    }
    if (_isAndroid) {
      try {
        return await _channel.invokeMethod<bool>('openFile', {
              'path': path,
              'mimeType': mimeType,
            }) ??
            false;
      } catch (_) {
        return false;
      }
    }
    if (_isWindows) {
      try {
        await Process.start(
          'cmd',
          ['/c', 'start', '', path],
          runInShell: false,
        );
        return true;
      } catch (_) {
        return false;
      }
    }
    return false;
  }

  Future<bool> audioPlay(
    String source, {
    String? userAgent,
    double speed = 1.0,
  }) async {
    if (_isAndroid) {
      try {
        return await _channel.invokeMethod<bool>('audioPlay', {
              'source': source,
              'userAgent': userAgent ?? PrivacyFirewall.defaultHttpUserAgent,
              'speed': speed,
            }) ??
            false;
      } catch (_) {
        return false;
      }
    }
    if (_isWindows) {
      return openFile(source);
    }
    return false;
  }

  Future<void> audioSetSpeed(double speed) async {
    if (!_isAndroid) return;
    try {
      await _channel.invokeMethod<void>('audioSetSpeed', {
        'speed': speed,
      });
    } catch (_) {}
  }

  Future<void> audioPause() async {
    if (!_isAndroid) return;
    try {
      await _channel.invokeMethod<void>('audioPause');
    } catch (_) {}
  }

  Future<void> audioResume() async {
    if (!_isAndroid) return;
    try {
      await _channel.invokeMethod<void>('audioResume');
    } catch (_) {}
  }

  Future<void> audioSeek(int positionMs) async {
    if (!_isAndroid) return;
    try {
      await _channel.invokeMethod<void>('audioSeek', {
        'positionMs': positionMs,
      });
    } catch (_) {}
  }

  Future<void> audioStop() async {
    if (!_isAndroid) return;
    try {
      await _channel.invokeMethod<void>('audioStop');
    } catch (_) {}
  }

  Future<TalerAudioState> audioState() async {
    if (!_isAndroid) return const TalerAudioState();
    try {
      final map = await _channel.invokeMapMethod<String, dynamic>('audioState');
      if (map == null) return const TalerAudioState();
      return TalerAudioState(
        ready: map['ready'] as bool? ?? false,
        playing: map['playing'] as bool? ?? false,
        positionMs: (map['positionMs'] as num?)?.toInt() ?? 0,
        durationMs: (map['durationMs'] as num?)?.toInt() ?? 0,
        completed: map['completed'] as bool? ?? false,
        error: map['error'] as String?,
      );
    } catch (_) {
      return const TalerAudioState();
    }
  }

  Future<bool> requestAudioRecordPermission() async {
    if (!_isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>(
            'requestAudioRecordPermission',
          ) ??
          false;
    } catch (_) {
      return false;
    }
  }

  Future<String?> startAudioRecord() async {
    if (!_isAndroid) return null;
    final granted = await requestAudioRecordPermission();
    if (!granted) return null;
    try {
      final dir = await getTemporaryDirectory();
      final outPath =
          '${dir.path}${Platform.pathSeparator}taler_voice_${DateTime.now().millisecondsSinceEpoch}.ogg';
      final ok = await _channel.invokeMethod<bool>('startAudioRecord', {
            'outputPath': outPath,
          }) ??
          false;
      return ok ? outPath : null;
    } catch (_) {
      return null;
    }
  }

  Future<TalerRecordedVoice?> stopAudioRecord() async {
    if (!_isAndroid) return null;
    try {
      final map = await _channel.invokeMapMethod<String, dynamic>(
        'stopAudioRecord',
      );
      if (map == null) return null;
      final path = map['path'] as String?;
      final dur = (map['durationMs'] as num?)?.toInt() ?? 0;
      if (path == null || path.isEmpty) return null;
      return TalerRecordedVoice(path: path, durationMs: dur);
    } catch (_) {
      return null;
    }
  }

  Future<void> cancelAudioRecord() async {
    if (!_isAndroid) return;
    try {
      await _channel.invokeMethod<void>('cancelAudioRecord');
    } catch (_) {}
  }

  Future<double> getAudioAmplitude() async {
    if (!_isAndroid) return 0.0;
    try {
      return (await _channel.invokeMethod<double>('getAudioAmplitude') ?? 0.0)
          .clamp(0.0, 1.0);
    } catch (_) {
      return 0.0;
    }
  }
}

/// Единый реактивный контроллер воспроизведения голосовых и аудио в чатах.
class TalerAudioController extends ChangeNotifier {
  TalerAudioController._();

  static final TalerAudioController instance = TalerAudioController._();

  static const List<double> _speeds = [1.0, 1.5, 2.0];

  String? _activeKey;
  bool _isLoading = false;
  bool _isPlaying = false;
  int _positionMs = 0;
  int _durationMs = 0;
  double _speed = 1.0;
  String? _lastError;
  Timer? _pollTimer;

  String? get activeKey => _activeKey;
  bool get isLoading => _isLoading;
  bool get isPlaying => _isPlaying;
  int get positionMs => _positionMs;
  int get durationMs => _durationMs;
  double get speed => _speed;
  String? get lastError => _lastError;

  String get speedLabel =>
      _speed == 1.0 ? '1×' : (_speed == 1.5 ? '1.5×' : '2×');

  double progressFor(String key) {
    if (_activeKey != key || _durationMs <= 0) return 0.0;
    return (_positionMs / _durationMs).clamp(0.0, 1.0);
  }

  bool isPlayingKey(String key) => _activeKey == key && _isPlaying;
  bool isLoadingKey(String key) => _activeKey == key && _isLoading;

  Future<void> cycleSpeed() async {
    final idx = _speeds.indexOf(_speed);
    _speed = _speeds[(idx + 1) % _speeds.length];
    notifyListeners();
    if (_activeKey != null) {
      await TalerNativeBridge.instance.audioSetSpeed(_speed);
    }
  }

  Future<bool> toggle({
    required String key,
    required Future<String?> Function() resolveSource,
    int fallbackDurationMs = 0,
  }) async {
    _lastError = null;
    if (_activeKey == key && !_isLoading) {
      if (_isPlaying) {
        await TalerNativeBridge.instance.audioPause();
        _isPlaying = false;
        _stopPolling();
        notifyListeners();
        return true;
      } else {
        await TalerNativeBridge.instance.audioResume();
        _isPlaying = true;
        _startPolling();
        notifyListeners();
        return true;
      }
    }

    await stop();
    _activeKey = key;
    _isLoading = true;
    _isPlaying = false;
    _positionMs = 0;
    _durationMs = fallbackDurationMs;
    notifyListeners();

    final source = await resolveSource();
    if (_activeKey != key) return false;
    if (source == null || source.isEmpty) {
      _activeKey = null;
      _isLoading = false;
      _lastError = 'Не удалось загрузить голосовое сообщение';
      notifyListeners();
      return false;
    }

    final started = await TalerNativeBridge.instance.audioPlay(
      source,
      speed: _speed,
    );
    if (_activeKey != key) return false;
    if (!started) {
      _activeKey = null;
      _isLoading = false;
      _lastError = 'Не удалось воспроизвести голосовое сообщение';
      notifyListeners();
      return false;
    }

    _isLoading = false;
    _isPlaying = TalerNativeBridge.instance.supportsInlineVideo;
    if (_isPlaying) {
      _startPolling();
    } else {
      // На Windows системный плеер открывается отдельно.
      _activeKey = null;
    }
    notifyListeners();
    return true;
  }

  Future<void> seek(String key, double fraction) async {
    if (_activeKey != key || _durationMs <= 0) return;
    final targetMs = (_durationMs * fraction.clamp(0.0, 1.0)).round();
    _positionMs = targetMs;
    notifyListeners();
    await TalerNativeBridge.instance.audioSeek(targetMs);
  }

  Future<void> stop() async {
    _stopPolling();
    if (_activeKey != null || _isPlaying) {
      await TalerNativeBridge.instance.audioStop();
    }
    _activeKey = null;
    _isLoading = false;
    _isPlaying = false;
    _positionMs = 0;
    _durationMs = 0;
    notifyListeners();
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(milliseconds: 100), (_) async {
      final state = await TalerNativeBridge.instance.audioState();
      if (_activeKey == null) {
        _stopPolling();
        return;
      }
      if (state.error != null && state.error!.isNotEmpty) {
        _lastError = state.error;
        _isPlaying = false;
        _positionMs = 0;
        _activeKey = null;
        _stopPolling();
        notifyListeners();
        return;
      }
      if (state.durationMs > 0) {
        _durationMs = state.durationMs;
      }
      if (state.ready) {
        _positionMs = state.positionMs.clamp(
          0,
          _durationMs > 0 ? _durationMs : state.positionMs,
        );
      }
      if (state.completed) {
        _isPlaying = false;
        _positionMs = 0;
        _stopPolling();
      } else {
        _isPlaying = state.playing || !state.ready;
      }
      notifyListeners();
    });
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }
}

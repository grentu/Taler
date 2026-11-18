import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../version.dart';

/// Состояния проверки и установки OTA-обновлений клиента Taler.
enum UpdateStatus {
  idle,
  checking,
  upToDate,
  available,
  downloading,
  needsPermission,
  readyToInstall,
  error,
}

/// Файл сборки в релизе GitHub.
class TalerReleaseAsset {
  final String name;
  final String downloadUrl;
  final int sizeBytes;

  const TalerReleaseAsset({
    required this.name,
    required this.downloadUrl,
    required this.sizeBytes,
  });

  factory TalerReleaseAsset.fromJson(Map<String, dynamic> json) {
    return TalerReleaseAsset(
      name: json['name'] as String? ?? '',
      downloadUrl: json['browser_download_url'] as String? ?? '',
      sizeBytes: (json['size'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Описание последнего релиза на GitHub Releases.
class TalerReleaseInfo {
  final String tag;
  final String version;
  final String notes;
  final String htmlUrl;
  final DateTime? publishedAt;
  final TalerReleaseAsset? matchedAsset;

  const TalerReleaseInfo({
    required this.tag,
    required this.version,
    required this.notes,
    required this.htmlUrl,
    this.publishedAt,
    this.matchedAsset,
  });
}

/// Сервис обновлений по воздуху (OTA) через GitHub Releases (`grentu/Taler`).
class AppUpdater extends ChangeNotifier {
  static const MethodChannel _channel = MethodChannel('io.grentu.taler/updater');

  final http.Client? _injectedClient;
  final Future<Directory> Function()? _tempDirProvider;
  final Future<void> Function(String exePath)? _windowsLauncher;
  final Future<String> Function(String apkPath)? _androidInstaller;
  final Future<String> Function()? _androidAbiProvider;
  final bool _isAndroid;
  final bool _isWindows;
  final String _currentVersion;

  UpdateStatus _status = UpdateStatus.idle;
  TalerReleaseInfo? _release;
  double _progress = 0.0;
  int _downloadedBytes = 0;
  int _totalBytes = 0;
  String? _downloadedFilePath;
  String? _errorMessage;
  bool _downloadCancelled = false;
  StreamSubscription<List<int>>? _downloadSub;
  Completer<void>? _downloadCompleter;

  AppUpdater({
    http.Client? httpClient,
    Future<Directory> Function()? tempDirProvider,
    Future<void> Function(String exePath)? windowsLauncher,
    Future<String> Function(String apkPath)? androidInstaller,
    Future<String> Function()? androidAbiProvider,
    bool? isAndroidOverride,
    bool? isWindowsOverride,
    String currentVersion = kTalerVersion,
  })  : _injectedClient = httpClient,
        _tempDirProvider = tempDirProvider,
        _windowsLauncher = windowsLauncher,
        _androidInstaller = androidInstaller,
        _androidAbiProvider = androidAbiProvider,
        _isAndroid = isAndroidOverride ?? Platform.isAndroid,
        _isWindows = isWindowsOverride ?? Platform.isWindows,
        _currentVersion = currentVersion;

  UpdateStatus get status => _status;
  TalerReleaseInfo? get release => _release;
  double get progress => _progress;
  int get downloadedBytes => _downloadedBytes;
  int get totalBytes => _totalBytes;
  String? get downloadedFilePath => _downloadedFilePath;
  String? get errorMessage => _errorMessage;
  String get currentVersion => _currentVersion;

  bool get hasUpdate =>
      _release != null &&
      (_status == UpdateStatus.available ||
          _status == UpdateStatus.downloading ||
          _status == UpdateStatus.needsPermission ||
          _status == UpdateStatus.readyToInstall);

  /// Разбирает строку версии вида `v1.2.12`, `1.2.12+18`, `1.3` в `[major, minor, patch]`.
  static List<int> parseSemVer(String raw) {
    final cleaned = raw.trim().replaceFirst(RegExp(r'^[vV]'), '').split('+').first.split('-').first;
    final parts = cleaned.split('.');
    return List<int>.generate(3, (i) {
      if (i >= parts.length) return 0;
      return int.tryParse(parts[i].replaceAll(RegExp(r'\D'), '')) ?? 0;
    });
  }

  /// Возвращает `true`, если [candidate] строго новее [current].
  static bool isVersionNewer(String candidate, String current) {
    final c = parseSemVer(candidate);
    final cur = parseSemVer(current);
    for (var i = 0; i < 3; i++) {
      if (c[i] > cur[i]) return true;
      if (c[i] < cur[i]) return false;
    }
    return false;
  }

  /// Имя APK-ассета в GitHub Releases для данного ABI.
  static String expectedAndroidAssetName(String abi) {
    final lower = abi.toLowerCase();
    if (lower.contains('armeabi-v7a') || lower.contains('armeabi')) {
      return 'Taler-Android-armeabi-v7a.apk';
    }
    if (lower.contains('x86_64')) {
      return 'Taler-Android-x86_64.apk';
    }
    return 'Taler-Android-arm64-v8a.apk';
  }

  /// Выбирает подходящий файл релиза из массива `assets` ответа GitHub API.
  static TalerReleaseAsset? pickAssetFromList(
    List<dynamic> rawAssets, {
    required bool isAndroid,
    required bool isWindows,
    String abi = 'arm64-v8a',
  }) {
    final assets = rawAssets
        .whereType<Map>()
        .map((e) => TalerReleaseAsset.fromJson(Map<String, dynamic>.from(e)))
        .where((a) => a.name.isNotEmpty && a.downloadUrl.isNotEmpty)
        .toList();

    if (assets.isEmpty) return null;

    if (isAndroid) {
      final preferred = expectedAndroidAssetName(abi);
      return assets.firstWhere(
        (a) => a.name == preferred,
        orElse: () => assets.firstWhere(
          (a) => a.name == 'Taler-Android-arm64-v8a.apk',
          orElse: () => assets.firstWhere(
            (a) => a.name.toLowerCase().endsWith('.apk'),
            orElse: () => const TalerReleaseAsset(name: '', downloadUrl: '', sizeBytes: 0),
          ),
        ),
      ).letOrNull();
    }

    if (isWindows) {
      return assets.firstWhere(
        (a) => a.name == 'Taler-Windows-x64.exe',
        orElse: () => assets.firstWhere(
          (a) => a.name.toLowerCase().endsWith('.exe'),
          orElse: () => const TalerReleaseAsset(name: '', downloadUrl: '', sizeBytes: 0),
        ),
      ).letOrNull();
    }

    return null;
  }

  Future<String> _resolveAndroidAbi() async {
    if (_androidAbiProvider != null) {
      return _androidAbiProvider();
    }
    if (!Platform.isAndroid) return 'arm64-v8a';
    try {
      final res = await _channel.invokeMethod<String>('getAbi');
      if (res != null && res.isNotEmpty) return res;
    } catch (_) {}
    return 'arm64-v8a';
  }

  /// Проверяет последний релиз на GitHub (`grentu/Taler`).
  Future<void> checkForUpdates({bool silent = false}) async {
    if (_status == UpdateStatus.checking || _status == UpdateStatus.downloading) {
      return;
    }
    if (_injectedClient == null && Platform.environment['FLUTTER_TEST'] == 'true') {
      return;
    }

    if (!silent) {
      _status = UpdateStatus.checking;
      _errorMessage = null;
      notifyListeners();
    }

    final ownsClient = _injectedClient == null;
    final client = _injectedClient ?? http.Client();

    try {
      final uri = Uri.https(
        'api.github.com',
        '/repos/$kTalerRepoOwner/$kTalerRepoName/releases/latest',
      );
      final resp = await client.get(
        uri,
        headers: {
          'Accept': 'application/vnd.github+json',
          'User-Agent': 'Taler/$_currentVersion',
        },
      ).timeout(const Duration(seconds: 12));

      if (resp.statusCode != 200) {
        if (!silent) {
          _status = UpdateStatus.error;
          _errorMessage = 'Не удалось проверить обновления (HTTP ${resp.statusCode})';
          notifyListeners();
        }
        return;
      }

      final json = jsonDecode(resp.body) as Map<String, dynamic>;
      final tag = (json['tag_name'] as String? ?? '').trim();
      final version = tag.replaceFirst(RegExp(r'^[vV]'), '');
      final notes = (json['body'] as String? ?? '').trim();
      final htmlUrl = json['html_url'] as String? ??
          'https://github.com/$kTalerRepoOwner/$kTalerRepoName/releases/latest';
      final publishedAt = DateTime.tryParse(json['published_at'] as String? ?? '');
      final rawAssets = json['assets'] as List? ?? const [];

      final abi = _isAndroid ? await _resolveAndroidAbi() : 'arm64-v8a';

      final asset = pickAssetFromList(
        rawAssets,
        isAndroid: _isAndroid,
        isWindows: _isWindows,
        abi: abi,
      );

      final newer = tag.isNotEmpty && isVersionNewer(tag, _currentVersion);
      if (newer) {
        _release = TalerReleaseInfo(
          tag: tag,
          version: version.isEmpty ? tag : version,
          notes: notes,
          htmlUrl: htmlUrl,
          publishedAt: publishedAt,
          matchedAsset: asset,
        );
        // Если новая версия с другим тегом — сбрасываем прошлый скачанный файл.
        if (_downloadedFilePath != null &&
            !_downloadedFilePath!.contains(tag)) {
          _downloadedFilePath = null;
        }
        _status = UpdateStatus.available;
        _errorMessage = null;
        notifyListeners();
      } else if (!silent || _status != UpdateStatus.idle) {
        _release = null;
        _status = UpdateStatus.upToDate;
        _errorMessage = null;
        notifyListeners();
      }
    } catch (e) {
      if (!silent) {
        _status = UpdateStatus.error;
        _errorMessage = 'Ошибка сети при проверке обновлений';
        notifyListeners();
      }
    } finally {
      if (ownsClient) client.close();
    }
  }

  /// Скачивает пакет обновления и запускает установщик.
  Future<void> downloadAndInstall() async {
    final info = _release;
    final asset = info?.matchedAsset;
    if (info == null || asset == null) {
      _status = UpdateStatus.error;
      _errorMessage = 'Сборка для вашей платформы пока загружается в релиз';
      notifyListeners();
      return;
    }

    // Если этот релиз уже скачан (например, после выдачи разрешения на Android) — сразу ставим.
    final cachedPath = _downloadedFilePath;
    if (cachedPath != null &&
        cachedPath.contains(info.tag) &&
        await File(cachedPath).exists()) {
      await _launchInstaller(cachedPath);
      return;
    }

    if (_status == UpdateStatus.downloading) return;

    _downloadCancelled = false;
    _status = UpdateStatus.downloading;
    _progress = 0.0;
    _downloadedBytes = 0;
    _totalBytes = asset.sizeBytes;
    _errorMessage = null;
    notifyListeners();

    final ownsClient = _injectedClient == null;
    final client = _injectedClient ?? http.Client();
    IOSink? sink;
    File? partFile;

    try {
      final dir = await (_tempDirProvider != null
          ? _tempDirProvider()
          : _resolveUpdateDir());
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      final safeTag = info.tag.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
      final finalPath = '${dir.path}${Platform.pathSeparator}taler_${safeTag}_${asset.name}';
      partFile = File('$finalPath.part');
      if (await partFile.exists()) {
        await partFile.delete();
      }

      final request = http.Request('GET', Uri.parse(asset.downloadUrl))
        ..headers['User-Agent'] = 'Taler/$_currentVersion';
      final response = await client.send(request).timeout(const Duration(seconds: 25));

      if (response.statusCode != 200) {
        throw HttpException('HTTP ${response.statusCode}');
      }

      final contentLength = response.contentLength ?? asset.sizeBytes;
      if (contentLength > 0) _totalBytes = contentLength;

      sink = partFile.openWrite();
      var lastNotify = DateTime.now();

      final completer = Completer<void>();
      _downloadCompleter = completer;
      _downloadSub = response.stream.listen(
        (chunk) {
          if (_downloadCancelled) {
            _downloadSub?.cancel();
            if (!completer.isCompleted) completer.complete();
            return;
          }
          sink!.add(chunk);
          _downloadedBytes += chunk.length;
          if (_totalBytes > 0) {
            _progress = (_downloadedBytes / _totalBytes).clamp(0.0, 1.0);
          }
          final now = DateTime.now();
          if (now.difference(lastNotify).inMilliseconds >= 80) {
            lastNotify = now;
            notifyListeners();
          }
        },
        onError: (Object err) {
          if (!completer.isCompleted) completer.completeError(err);
        },
        onDone: () {
          if (!completer.isCompleted) completer.complete();
        },
        cancelOnError: true,
      );

      await completer.future;
      await sink.flush();
      await sink.close();
      sink = null;
      _downloadSub = null;
      _downloadCompleter = null;

      if (_downloadCancelled) {
        if (await partFile.exists()) await partFile.delete();
        _status = UpdateStatus.available;
        _progress = 0.0;
        _downloadedBytes = 0;
        notifyListeners();
        return;
      }

      final targetFile = File(finalPath);
      if (await targetFile.exists()) {
        await targetFile.delete();
      }
      await partFile.rename(finalPath);
      partFile = null;

      if (await targetFile.length() == 0) {
        throw const FileSystemException('Скачанный файл пуст');
      }

      _downloadedFilePath = finalPath;
      _progress = 1.0;
      notifyListeners();

      await _launchInstaller(finalPath);
    } catch (e) {
      await sink?.close();
      if (partFile != null && await partFile.exists()) {
        try {
          await partFile.delete();
        } catch (_) {}
      }
      if (!_downloadCancelled) {
        _status = UpdateStatus.error;
        _errorMessage = 'Не удалось загрузить обновление';
        notifyListeners();
      }
    } finally {
      _downloadSub = null;
      _downloadCompleter = null;
      if (ownsClient) client.close();
    }
  }

  /// Отменяет текущую загрузку.
  void cancelDownload() {
    if (_status != UpdateStatus.downloading) return;
    _downloadCancelled = true;
    unawaited(_downloadSub?.cancel());
    final completer = _downloadCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }
  }

  Future<Directory> _resolveUpdateDir() async {
    if (Platform.isWindows) {
      final localAppData = Platform.environment['LOCALAPPDATA'];
      if (localAppData != null && localAppData.isNotEmpty) {
        return Directory('$localAppData\\Taler\\updates');
      }
    }
    final temp = await getTemporaryDirectory();
    return Directory('${temp.path}${Platform.pathSeparator}taler_updates');
  }

  Future<void> _launchInstaller(String filePath) async {
    if (_isAndroid || _androidInstaller != null) {
      try {
        final result = _androidInstaller != null
            ? await _androidInstaller(filePath)
            : await _channel.invokeMethod<String>('installApk', {'path': filePath});
        if (result == 'needs_permission') {
          _status = UpdateStatus.needsPermission;
          _errorMessage = null;
          notifyListeners();
          return;
        }
        _status = UpdateStatus.readyToInstall;
        _errorMessage = null;
        notifyListeners();
      } catch (e) {
        _status = UpdateStatus.error;
        _errorMessage = 'Не удалось запустить установщик Android';
        notifyListeners();
      }
      return;
    }

    if (_isWindows || _windowsLauncher != null) {
      try {
        if (_windowsLauncher != null) {
          await _windowsLauncher(filePath);
        } else {
          await Process.start(filePath, const [], mode: ProcessStartMode.detached);
          _status = UpdateStatus.readyToInstall;
          notifyListeners();
          await Future<void>.delayed(const Duration(milliseconds: 250));
          exit(0);
        }
        _status = UpdateStatus.readyToInstall;
        _errorMessage = null;
        notifyListeners();
      } catch (e) {
        _status = UpdateStatus.error;
        _errorMessage = 'Не удалось запустить установщик Windows';
        notifyListeners();
      }
      return;
    }

    _status = UpdateStatus.readyToInstall;
    notifyListeners();
  }

  @override
  void dispose() {
    _downloadSub?.cancel();
    super.dispose();
  }
}

extension on TalerReleaseAsset {
  TalerReleaseAsset? letOrNull() => name.isEmpty || downloadUrl.isEmpty ? null : this;
}

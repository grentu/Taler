import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';

/// Быстрый двухуровневый кэш медиа и аватарок (RAM + диск) с общим keep-alive
/// HttpClient и дедупликацией параллельных запросов.
class TalerMediaCache {
  TalerMediaCache._();

  static final TalerMediaCache instance = TalerMediaCache._();

  static const int _maxConcurrentFetches = 6;

  final Map<String, File> _memoryFiles = <String, File>{};
  final Map<String, Future<File?>> _inFlight = <String, Future<File?>>{};
  final List<({String url, Completer<File?> completer})> _pendingQueue = [];
  int _activeFetches = 0;

  Directory? _cacheDir;
  Future<Directory>? _dirFuture;
  HttpClient? _http;

  static String cacheKey(String url) =>
      sha1.convert(utf8.encode(url)).toString();

  HttpClient _client() {
    return _http ??= HttpClient()
      ..connectionTimeout = const Duration(seconds: 8)
      ..idleTimeout = const Duration(seconds: 30)
      ..maxConnectionsPerHost = 12
      ..autoUncompress = true;
  }

  Future<Directory> _ensureDir() {
    if (_cacheDir != null) return Future.value(_cacheDir!);
    return _dirFuture ??= () async {
      Directory base;
      if (Platform.environment['FLUTTER_TEST'] == 'true') {
        base = Directory.systemTemp;
      } else {
        try {
          base = await getTemporaryDirectory();
        } catch (_) {
          base = Directory.systemTemp;
        }
      }
      final dir = Directory('${base.path}${Platform.pathSeparator}taler_media_cache');
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      _cacheDir = dir;
      return dir;
    }();
  }

  /// Инициализирует каталог кэша в фоне при запуске приложения.
  Future<void> warmUp() async {
    try {
      await _ensureDir();
    } catch (_) {}
  }

  /// Синхронная проверка готового локального файла без лишних Future.
  File? getCachedFileSync(String url) {
    final mem = _memoryFiles[url];
    if (mem != null && mem.existsSync()) return mem;
    final dir = _cacheDir;
    if (dir == null) return null;
    final file = File('${dir.path}${Platform.pathSeparator}${cacheKey(url)}.img');
    if (file.existsSync() && file.lengthSync() > 0) {
      _memoryFiles[url] = file;
      return file;
    }
    return null;
  }

  /// Загружает изображение с дедупликацией и сохранением на диск.
  Future<File?> fetch(String url) {
    final sync = getCachedFileSync(url);
    if (sync != null) return Future.value(sync);

    if (Platform.environment['FLUTTER_TEST'] == 'true') {
      return Future.value(null);
    }

    final existing = _inFlight[url];
    if (existing != null) return existing;

    final completer = Completer<File?>();
    _inFlight[url] = completer.future;

    if (_activeFetches < _maxConcurrentFetches) {
      _startFetch(url, completer);
    } else {
      _pendingQueue.add((url: url, completer: completer));
    }
    return completer.future;
  }

  void _startFetch(String url, Completer<File?> completer) {
    _activeFetches++;
    unawaited(_downloadToFile(url).then((file) {
      if (!completer.isCompleted) completer.complete(file);
    }).catchError((Object _) {
      if (!completer.isCompleted) completer.complete(null);
    }).whenComplete(() {
      _inFlight.remove(url);
      _activeFetches--;
      if (_pendingQueue.isNotEmpty) {
        final next = _pendingQueue.removeAt(0);
        _startFetch(next.url, next.completer);
      }
    }));
  }

  Future<File?> _downloadToFile(String url) async {
    final dir = await _ensureDir();
    final target = File('${dir.path}${Platform.pathSeparator}${cacheKey(url)}.img');
    if (await target.exists() && await target.length() > 0) {
      _memoryFiles[url] = target;
      return target;
    }

    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) return null;

    final part = File('${target.path}.part_${DateTime.now().microsecondsSinceEpoch}');
    IOSink? sink;
    try {
      final req = await _client().getUrl(uri);
      req.headers.set(HttpHeaders.userAgentHeader, 'Taler/1.2');
      final res = await req.close().timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) {
        await res.drain<void>();
        return null;
      }
      sink = part.openWrite();
      await for (final chunk in res) {
        sink.add(chunk);
      }
      await sink.flush();
      await sink.close();
      sink = null;

      if (!await part.exists() || await part.length() == 0) {
        return null;
      }
      if (await target.exists()) {
        try {
          await target.delete();
        } catch (_) {}
      }
      final saved = await part.rename(target.path);
      _memoryFiles[url] = saved;
      return saved;
    } catch (_) {
      await sink?.close();
      if (await part.exists()) {
        try {
          await part.delete();
        } catch (_) {}
      }
      return null;
    }
  }

  /// Фоновый прогрев первых видимых аватарок и миниатюр.
  void prefetchUrls(Iterable<String?> urls) {
    if (Platform.environment['FLUTTER_TEST'] == 'true') return;
    for (final url in urls) {
      if (url == null || url.isEmpty) continue;
      if (!url.startsWith('http://') && !url.startsWith('https://')) continue;
      if (getCachedFileSync(url) != null || _inFlight.containsKey(url)) continue;
      unawaited(fetch(url));
    }
  }

  /// Суммарный размер дискового медиа-кэша в байтах.
  Future<int> estimateDiskBytes() async {
    try {
      final dir = await _ensureDir();
      var total = 0;
      await for (final entity in dir.list()) {
        if (entity is File) {
          total += await entity.length();
        }
      }
      return total;
    } catch (_) {
      return 0;
    }
  }

  /// Очищает локальный кэш изображений на диске и в памяти.
  Future<void> clear() async {
    _memoryFiles.clear();
    try {
      final dir = await _ensureDir();
      if (await dir.exists()) {
        await for (final entity in dir.list()) {
          if (entity is File) {
            try {
              await entity.delete();
            } catch (_) {}
          }
        }
      }
    } catch (_) {}
  }

  @visibleForTesting
  void resetForTest({Directory? cacheDir}) {
    _memoryFiles.clear();
    _inFlight.clear();
    _pendingQueue.clear();
    _cacheDir = cacheDir;
    _dirFuture = cacheDir != null ? Future.value(cacheDir) : null;
  }
}

/// Быстрое кэширующее изображение для фото, аватарок и миниатюр.
class TalerCachedImage extends StatefulWidget {
  final String url;
  final double? width;
  final double? height;
  final int? cacheWidth;
  final BoxFit fit;
  final FilterQuality filterQuality;
  final Widget placeholder;
  final Widget? decodingPlaceholder;
  final Widget? errorWidget;

  const TalerCachedImage({
    super.key,
    required this.url,
    required this.placeholder,
    this.decodingPlaceholder,
    this.width,
    this.height,
    this.cacheWidth,
    this.fit = BoxFit.cover,
    this.filterQuality = FilterQuality.medium,
    this.errorWidget,
  });

  @override
  State<TalerCachedImage> createState() => _TalerCachedImageState();
}

class _TalerCachedImageState extends State<TalerCachedImage> {
  File? _file;
  bool _failed = false;

  bool get _isRemote =>
      widget.url.startsWith('http://') || widget.url.startsWith('https://');

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant TalerCachedImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _file = null;
      _failed = false;
      _resolve();
    }
  }

  void _resolve() {
    if (!_isRemote) {
      _file = File(widget.url);
      return;
    }
    final cached = TalerMediaCache.instance.getCachedFileSync(widget.url);
    if (cached != null) {
      _file = cached;
      return;
    }
    unawaited(
      TalerMediaCache.instance.fetch(widget.url).then((file) {
        if (!mounted) return;
        setState(() {
          _file = file;
          _failed = file == null;
        });
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final file = _file;
    if (file != null) {
      return Image.file(
        file,
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        cacheWidth: widget.cacheWidth,
        filterQuality: widget.filterQuality,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => widget.errorWidget ?? widget.placeholder,
        frameBuilder: (ctx, child, frame, sync) {
          if (sync || frame != null) return child;
          return widget.decodingPlaceholder ?? widget.placeholder;
        },
      );
    }

    if (_failed) {
      return widget.errorWidget ?? widget.placeholder;
    }

    // При отсутствии файла в кэше (например, в среде теста или при первом запросе):
    if (_isRemote && Platform.environment['FLUTTER_TEST'] != 'true') {
      return widget.placeholder;
    }
    return widget.placeholder;
  }
}

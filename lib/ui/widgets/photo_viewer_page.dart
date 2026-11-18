import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/media/taler_media_cache.dart';
import '../../core/storage/taler_models.dart';
import '../icons/taler_icon.dart';
import '../theme/taler_theme.dart';

/// Элемент для полноэкранного просмотрщика фотографий.
class TalerPhotoViewerItem {
  final TalerAttachment attachment;
  final String? senderName;
  final int? timestamp;
  final String? caption;

  const TalerPhotoViewerItem({
    required this.attachment,
    this.senderName,
    this.timestamp,
    this.caption,
  });
}

/// Открывает чёрный полноэкранный просмотрщик фотографий с зумом и свайпом-закрытием.
Future<void> showTalerPhotoViewer(
  BuildContext context, {
  required List<TalerPhotoViewerItem> items,
  int initialIndex = 0,
}) {
  if (items.isEmpty) return Future<void>.value();
  final safeIndex = initialIndex.clamp(0, items.length - 1);
  return Navigator.of(context, rootNavigator: true).push<void>(
    PageRouteBuilder<void>(
      opaque: false,
      barrierColor: Colors.black,
      transitionDuration: const Duration(milliseconds: 220),
      reverseTransitionDuration: const Duration(milliseconds: 190),
      pageBuilder: (_, _, _) => _PhotoViewerPage(
        items: items,
        initialIndex: safeIndex,
      ),
      transitionsBuilder: (_, animation, _, child) => FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
        child: child,
      ),
    ),
  );
}

class _PhotoViewerPage extends StatefulWidget {
  final List<TalerPhotoViewerItem> items;
  final int initialIndex;

  const _PhotoViewerPage({
    required this.items,
    required this.initialIndex,
  });

  @override
  State<_PhotoViewerPage> createState() => _PhotoViewerPageState();
}

class _PhotoViewerPageState extends State<_PhotoViewerPage> {
  late final PageController _pageCtrl;
  late int _index;
  bool _chromeVisible = true;
  double _dragOffsetY = 0.0;
  bool _zoomed = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _pageCtrl = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  TalerPhotoViewerItem get _current => widget.items[_index];

  Future<void> _saveCurrent() async {
    if (_saving) return;
    final url = _current.attachment.url;
    if (url == null || url.isEmpty) return;

    setState(() => _saving = true);
    try {
      File? file;
      if (url.startsWith('http://') || url.startsWith('https://')) {
        file = await TalerMediaCache.instance.fetch(url);
      } else {
        final f = File(url);
        if (await f.exists()) file = f;
      }
      if (file == null || !await file.exists()) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось подготовить файл для сохранения')),
        );
        return;
      }
      final bytes = await file.readAsBytes();
      final ts = _current.timestamp ?? DateTime.now().millisecondsSinceEpoch;
      final suggestedName = _current.attachment.fileName ?? 'taler_$ts.jpg';
      final savedPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Сохранить изображение',
        fileName: suggestedName,
        type: FileType.image,
        bytes: bytes,
      );
      if (!mounted) return;
      if (savedPath != null && savedPath.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Изображение сохранено')),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ошибка сохранения изображения')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _onVerticalDragUpdate(DragUpdateDetails d) {
    if (_zoomed) return;
    setState(() => _dragOffsetY += d.delta.dy);
  }

  void _onVerticalDragEnd(DragEndDetails d) {
    if (_zoomed) return;
    final velocity = d.primaryVelocity ?? 0.0;
    if (_dragOffsetY.abs() > 110 || velocity.abs() > 650) {
      Navigator.of(context).pop();
    } else {
      setState(() => _dragOffsetY = 0.0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dragRatio = (_dragOffsetY.abs() / 280.0).clamp(0.0, 0.72);
    final bgAlpha = 1.0 - dragRatio;
    final item = _current;
    final dateStr = item.timestamp != null && item.timestamp! > 0
        ? DateFormat('dd.MM.yyyy • HH:mm')
            .format(DateTime.fromMillisecondsSinceEpoch(item.timestamp!))
        : null;
    final caption = item.caption?.trim() ?? '';

    return Scaffold(
      backgroundColor: Colors.black.withValues(alpha: bgAlpha),
      body: GestureDetector(
        onTap: () => setState(() => _chromeVisible = !_chromeVisible),
        onVerticalDragUpdate: _zoomed ? null : _onVerticalDragUpdate,
        onVerticalDragEnd: _zoomed ? null : _onVerticalDragEnd,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Transform.translate(
              offset: Offset(0, _dragOffsetY),
              child: Transform.scale(
                scale: (1.0 - dragRatio * 0.14).clamp(0.84, 1.0),
                child: PageView.builder(
                  controller: _pageCtrl,
                  physics: _zoomed
                      ? const NeverScrollableScrollPhysics()
                      : const BouncingScrollPhysics(),
                  itemCount: widget.items.length,
                  onPageChanged: (i) => setState(() {
                    _index = i;
                    _zoomed = false;
                  }),
                  itemBuilder: (context, i) => _ZoomablePhoto(
                    url: widget.items[i].attachment.url ?? '',
                    onZoomChanged: (z) {
                      if (i == _index && _zoomed != z) {
                        setState(() => _zoomed = z);
                      }
                    },
                  ),
                ),
              ),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: IgnorePointer(
                ignoring: !_chromeVisible,
                child: AnimatedOpacity(
                  opacity: _chromeVisible && _dragOffsetY == 0 ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 180),
                  child: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0xD9000000), Color(0x00000000)],
                      ),
                    ),
                    child: SafeArea(
                      bottom: false,
                      child: SizedBox(
                        height: 58,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: Row(
                            children: [
                              TalerIconButton(
                                icon: TalerIcons.arrowLeft,
                                tooltip: 'Назад',
                                size: 44,
                                iconSize: 22,
                                color: Colors.white,
                                onPressed: () => Navigator.of(context).pop(),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item.senderName?.isNotEmpty == true
                                          ? item.senderName!
                                          : 'Фото',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.white,
                                      ),
                                    ),
                                    if (dateStr != null || widget.items.length > 1)
                                      Text(
                                        [
                                          ?dateStr,
                                          if (widget.items.length > 1)
                                            '${_index + 1} из ${widget.items.length}',
                                        ].join(' • '),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Color(0xB3FFFFFF),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              if (_saving)
                                const Padding(
                                  padding: EdgeInsets.all(12),
                                  child: SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  ),
                                )
                              else
                                TalerIconButton(
                                  icon: TalerIcons.arrowDownLeft,
                                  tooltip: 'Сохранить',
                                  size: 44,
                                  iconSize: 21,
                                  color: Colors.white,
                                  onPressed: () => unawaited(_saveCurrent()),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (caption.isNotEmpty)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: IgnorePointer(
                  ignoring: !_chromeVisible,
                  child: AnimatedOpacity(
                    opacity: _chromeVisible && _dragOffsetY == 0 ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 180),
                    child: Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [Color(0xE0000000), Color(0x00000000)],
                        ),
                      ),
                      padding: const EdgeInsets.fromLTRB(16, 28, 16, 18),
                      child: SafeArea(
                        top: false,
                        child: Text(
                          caption,
                          style: const TextStyle(
                            fontSize: 14.5,
                            height: 1.4,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ZoomablePhoto extends StatefulWidget {
  final String url;
  final ValueChanged<bool> onZoomChanged;

  const _ZoomablePhoto({
    required this.url,
    required this.onZoomChanged,
  });

  @override
  State<_ZoomablePhoto> createState() => _ZoomablePhotoState();
}

class _ZoomablePhotoState extends State<_ZoomablePhoto> {
  final TransformationController _transform = TransformationController();
  Offset? _doubleTapPos;

  @override
  void initState() {
    super.initState();
    _transform.addListener(_onScaleChanged);
  }

  void _onScaleChanged() {
    final scale = _transform.value.getMaxScaleOnAxis();
    widget.onZoomChanged(scale > 1.05);
  }

  @override
  void dispose() {
    _transform
      ..removeListener(_onScaleChanged)
      ..dispose();
    super.dispose();
  }

  void _handleDoubleTap() {
    final currentScale = _transform.value.getMaxScaleOnAxis();
    if (currentScale > 1.05) {
      _transform.value = Matrix4.identity();
    } else {
      final pos = _doubleTapPos ?? Offset.zero;
      const scale = 2.4;
      _transform.value = Matrix4.identity()
        ..translateByDouble(-pos.dx * (scale - 1), -pos.dy * (scale - 1), 0, 1)
        ..scaleByDouble(scale, scale, 1, 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    final loading = Center(
      child: CircularProgressIndicator(
        strokeWidth: 2.2,
        color: TalerTheme.paletteOf(context).accent,
      ),
    );
    final failed = const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TalerIcon(TalerIcons.image, size: 42, color: Color(0x88FFFFFF)),
          SizedBox(height: 10),
          Text(
            'Не удалось загрузить изображение',
            style: TextStyle(fontSize: 14, color: Color(0xB3FFFFFF)),
          ),
        ],
      ),
    );

    return GestureDetector(
      onDoubleTapDown: (d) => _doubleTapPos = d.localPosition,
      onDoubleTap: _handleDoubleTap,
      child: InteractiveViewer(
        transformationController: _transform,
        minScale: 1.0,
        maxScale: 4.5,
        clipBehavior: Clip.none,
        child: Center(
          child: widget.url.isEmpty
              ? failed
              : TalerCachedImage(
                  url: widget.url,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                  placeholder: loading,
                  decodingPlaceholder: const SizedBox.shrink(),
                  errorWidget: failed,
                ),
        ),
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/platform/taler_native_bridge.dart';
import '../../core/privacy/privacy_firewall.dart';
import '../icons/taler_icon.dart';
import '../theme/taler_theme.dart';

/// Открывает встроенный полноэкранный видеоплеер Taler (нативный TextureView/MediaPlayer
/// на Android и системный запуск на ПК).
Future<void> showTalerVideoPlayer(
  BuildContext context, {
  required String source,
  String? title,
  String? senderName,
  String? userAgent,
}) {
  return Navigator.of(context, rootNavigator: true).push<void>(
    PageRouteBuilder<void>(
      opaque: true,
      transitionDuration: const Duration(milliseconds: 220),
      reverseTransitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (_, _, _) => _TalerVideoPlayerPage(
        source: source,
        title: title,
        senderName: senderName,
        userAgent: userAgent,
      ),
      transitionsBuilder: (_, anim, _, child) => FadeTransition(
        opacity: CurvedAnimation(parent: anim, curve: Curves.easeOutCubic),
        child: child,
      ),
    ),
  );
}

class _TalerVideoPlayerPage extends StatefulWidget {
  final String source;
  final String? title;
  final String? senderName;
  final String? userAgent;

  const _TalerVideoPlayerPage({
    required this.source,
    this.title,
    this.senderName,
    this.userAgent,
  });

  @override
  State<_TalerVideoPlayerPage> createState() => _TalerVideoPlayerPageState();
}

class _TalerVideoPlayerPageState extends State<_TalerVideoPlayerPage> {
  MethodChannel? _videoChannel;
  Timer? _pollTimer;
  bool _ready = false;
  bool _playing = false;
  bool _muted = false;
  bool _showChrome = true;
  bool _scrubbing = false;
  int _positionMs = 0;
  int _durationMs = 0;
  double _scrubFraction = 0.0;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(TalerAudioController.instance.stop());
    if (!TalerNativeBridge.instance.supportsInlineVideo) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_openExternally());
      });
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  void _onPlatformViewCreated(int viewId) {
    _videoChannel = MethodChannel('io.grentu.taler/video_$viewId');
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(
      const Duration(milliseconds: 250),
      (_) => unawaited(_pollState()),
    );
  }

  Future<void> _pollState() async {
    final ch = _videoChannel;
    if (ch == null || !mounted) return;
    try {
      final map = await ch.invokeMapMethod<String, dynamic>('getState');
      if (map == null || !mounted) return;
      setState(() {
        _ready = map['ready'] as bool? ?? false;
        _playing = map['playing'] as bool? ?? false;
        if (!_scrubbing) {
          _positionMs = (map['positionMs'] as num?)?.toInt() ?? 0;
        }
        _durationMs = (map['durationMs'] as num?)?.toInt() ?? 0;
        _error = map['error'] as String?;
      });
    } catch (_) {}
  }

  Future<void> _togglePlay() async {
    final ch = _videoChannel;
    if (ch == null) return;
    if (_playing) {
      await ch.invokeMethod<void>('pause');
      if (mounted) setState(() => _playing = false);
    } else {
      await ch.invokeMethod<void>('play');
      if (mounted) setState(() => _playing = true);
    }
  }

  Future<void> _toggleMute() async {
    final ch = _videoChannel;
    final next = !_muted;
    setState(() => _muted = next);
    if (ch != null) {
      await ch.invokeMethod<void>('setVolume', {'volume': next ? 0.0 : 1.0});
    }
  }

  Future<void> _seekToFraction(double fraction) async {
    final ch = _videoChannel;
    if (ch == null || _durationMs <= 0) return;
    final target = (_durationMs * fraction.clamp(0.0, 1.0)).round();
    setState(() => _positionMs = target);
    await ch.invokeMethod<void>('seekTo', {'positionMs': target});
  }

  Future<void> _openExternally() async {
    final src = widget.source;
    if (src.startsWith('http://') || src.startsWith('https://')) {
      await TalerNativeBridge.instance.openUrl(src);
    } else {
      await TalerNativeBridge.instance.openFile(src, mimeType: 'video/*');
    }
  }

  static String _fmtMs(int ms) {
    final totalSec = (ms / 1000).floor().clamp(0, 359999);
    final mins = totalSec ~/ 60;
    final secs = totalSec % 60;
    return '$mins:${secs.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final p = TalerTheme.paletteOf(context);
    final padTop = MediaQuery.paddingOf(context).top;
    final padBottom = MediaQuery.paddingOf(context).bottom;
    final inline = TalerNativeBridge.instance.supportsInlineVideo;
    final progress = _scrubbing
        ? _scrubFraction
        : (_durationMs > 0 ? (_positionMs / _durationMs).clamp(0.0, 1.0) : 0.0);

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _showChrome = !_showChrome),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (inline)
              AndroidView(
                viewType: 'taler_video_view',
                creationParams: <String, Object?>{
                  'source': widget.source,
                  'userAgent':
                      widget.userAgent ?? PrivacyFirewall.defaultHttpUserAgent,
                  'autoPlay': true,
                },
                creationParamsCodec: const StandardMessageCodec(),
                onPlatformViewCreated: _onPlatformViewCreated,
              )
            else
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 68,
                      height: 68,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const TalerIcon(
                        TalerIcons.play,
                        size: 30,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      widget.title?.isNotEmpty == true
                          ? widget.title!
                          : 'Видео',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 14),
                    FilledButton(
                      onPressed: () => unawaited(_openExternally()),
                      style: FilledButton.styleFrom(
                        backgroundColor: p.accent,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Открыть в системном плеере'),
                    ),
                  ],
                ),
              ),
            if (inline && !_ready && _error == null)
              const Center(
                child: SizedBox(
                  width: 34,
                  height: 34,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Colors.white,
                  ),
                ),
              ),
            if (_error != null)
              Center(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 28),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xE614151A),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 14, color: Colors.white),
                      ),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: () => unawaited(_openExternally()),
                        style: FilledButton.styleFrom(
                          backgroundColor: p.accent,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('Открыть внешним плеером'),
                      ),
                    ],
                  ),
                ),
              ),
            if (inline && _ready && _showChrome)
              Center(
                child: GestureDetector(
                  onTap: () => unawaited(_togglePlay()),
                  child: Container(
                    width: 64,
                    height: 64,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.56),
                      shape: BoxShape.circle,
                    ),
                    child: _playing
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 5,
                                height: 22,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                width: 5,
                                height: 22,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            ],
                          )
                        : const Padding(
                            padding: EdgeInsets.only(left: 3),
                            child: TalerIcon(
                              TalerIcons.play,
                              size: 28,
                              color: Colors.white,
                            ),
                          ),
                  ),
                ),
              ),
            AnimatedOpacity(
              opacity: _showChrome ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 180),
              child: IgnorePointer(
                ignoring: !_showChrome,
                child: Stack(
                  children: [
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        padding: EdgeInsets.fromLTRB(8, padTop + 6, 8, 14),
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Color(0xB8000000), Color(0x00000000)],
                          ),
                        ),
                        child: Row(
                          children: [
                            TalerIconButton(
                              icon: TalerIcons.arrowLeft,
                              tooltip: 'Назад',
                              iconSize: 22,
                              color: Colors.white,
                              onPressed: () => Navigator.of(context).pop(),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    widget.title?.isNotEmpty == true
                                        ? widget.title!
                                        : (widget.senderName ?? 'Видео'),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white,
                                    ),
                                  ),
                                  if (widget.senderName != null &&
                                      widget.title?.isNotEmpty == true)
                                    Text(
                                      widget.senderName!,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 12.5,
                                        color: Color(0xB8FFFFFF),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            TalerIconButton(
                              icon: TalerIcons.arrowUpRight,
                              tooltip: 'Открыть внешним плеером',
                              iconSize: 20,
                              color: Colors.white,
                              onPressed: () => unawaited(_openExternally()),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (inline && _ready)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: Container(
                          padding: EdgeInsets.fromLTRB(
                            16,
                            18,
                            16,
                            padBottom + 14,
                          ),
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                              colors: [Color(0xC7000000), Color(0x00000000)],
                            ),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SliderTheme(
                                data: SliderTheme.of(context).copyWith(
                                  trackHeight: 3,
                                  activeTrackColor: p.accent,
                                  inactiveTrackColor:
                                      Colors.white.withValues(alpha: 0.24),
                                  thumbColor: Colors.white,
                                  thumbShape: const RoundSliderThumbShape(
                                    enabledThumbRadius: 6,
                                  ),
                                  overlayShape: SliderComponentShape.noOverlay,
                                ),
                                child: Slider(
                                  value: progress.clamp(0.0, 1.0),
                                  onChangeStart: (v) => setState(() {
                                    _scrubbing = true;
                                    _scrubFraction = v;
                                  }),
                                  onChanged: (v) =>
                                      setState(() => _scrubFraction = v),
                                  onChangeEnd: (v) {
                                    setState(() => _scrubbing = false);
                                    unawaited(_seekToFraction(v));
                                  },
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Text(
                                    '${_fmtMs(_positionMs)} / ${_fmtMs(_durationMs)}',
                                    style: TalerTheme.tabularStyle(
                                      size: 12.5,
                                      weight: FontWeight.w500,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const Spacer(),
                                  TalerIconButton(
                                    icon: _muted
                                        ? TalerIcons.volumeOff
                                        : TalerIcons.bell,
                                    tooltip: _muted
                                        ? 'Включить звук'
                                        : 'Без звука',
                                    size: 36,
                                    iconSize: 18,
                                    color: Colors.white,
                                    onPressed: () => unawaited(_toggleMute()),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

import 'dart:async';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/media/taler_media_cache.dart';
import '../../core/platform/taler_native_bridge.dart';
import '../../core/storage/taler_models.dart';
import '../icons/taler_icon.dart';
import '../theme/chat_tokens.dart';
import '../theme/taler_theme.dart';

/// Серый чип по центру ленты: разделитель дат или служебное сообщение.
class ChatDayChip extends StatelessWidget {
  final String label;

  const ChatDayChip({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    final p = TalerTheme.paletteOf(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: p.surface.withValues(alpha: p.isDark ? 0.88 : 0.92),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            label,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: p.fg2),
          ),
        ),
      ),
    );
  }
}

/// Строка сообщения: аватар отправителя в группах, пузырь, свайп-ответ,
/// двойной тап быстрой реакции, мультивыделение и реакции.
class MessageRow extends StatelessWidget {
  final TalerMessage message;
  final bool isMine;
  final bool firstInRun;
  final bool lastInRun;

  /// Группа: показывать имя и аватар отправителя у входящих.
  final bool showSender;
  final String senderName;
  final String? senderAvatarUrl;
  final double maxBubbleWidth;
  final int? peerReadMark;
  final double messageFontSize;
  final double bubbleRadius;
  final VoidCallback? onActions;
  final ValueChanged<Rect?>? onBubbleActions;
  final VoidCallback? onShowHistory;
  final VoidCallback? onRetry;
  final VoidCallback? onSwipeReply;
  final VoidCallback? onDoubleTapQuickReaction;
  final bool selectionMode;
  final bool isSelected;
  final VoidCallback? onToggleSelect;
  final void Function(TalerAttachment photo)? onOpenPhoto;
  final void Function(TalerAttachment video)? onOpenVideo;
  final void Function(TalerAttachment file)? onOpenFile;
  final double? Function(TalerAttachment file)? fileProgressOf;
  final Future<String?> Function(TalerAttachment audio)? onResolveAudio;
  final void Function(String url)? onOpenLink;
  final ValueChanged<String> onToggleReaction;

  const MessageRow({
    super.key,
    required this.message,
    required this.isMine,
    required this.firstInRun,
    required this.lastInRun,
    required this.showSender,
    required this.senderName,
    required this.maxBubbleWidth,
    required this.onToggleReaction,
    this.onActions,
    this.onBubbleActions,
    this.peerReadMark,
    this.messageFontSize = 15.0,
    this.bubbleRadius = 20.0,
    this.senderAvatarUrl,
    this.onShowHistory,
    this.onRetry,
    this.onSwipeReply,
    this.onDoubleTapQuickReaction,
    this.selectionMode = false,
    this.isSelected = false,
    this.onToggleSelect,
    this.onOpenPhoto,
    this.onOpenVideo,
    this.onOpenFile,
    this.fileProgressOf,
    this.onResolveAudio,
    this.onOpenLink,
  });

  void _triggerActions(BuildContext bubbleCtx) {
    if (selectionMode) {
      onToggleSelect?.call();
      return;
    }
    if (onBubbleActions != null) {
      final box = bubbleCtx.findRenderObject() as RenderBox?;
      Rect? rect;
      if (box != null && box.hasSize) {
        rect = box.localToGlobal(Offset.zero) & box.size;
      }
      onBubbleActions!(rect);
    }
    onActions?.call();
  }

  @override
  Widget build(BuildContext context) {
    final p = TalerTheme.paletteOf(context);
    if (message.isControl) {
      return ChatDayChip(label: message.text.isNotEmpty ? message.text : 'Служебное сообщение');
    }
    final bubble = Builder(
      builder: (bubbleCtx) {
        final gesture = GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: selectionMode
              ? onToggleSelect
              : (message.status == 'error' ? () => _triggerActions(bubbleCtx) : null),
          onLongPress: () => _triggerActions(bubbleCtx),
          onSecondaryTap: () => _triggerActions(bubbleCtx),
          child: IgnorePointer(
            ignoring: selectionMode,
            child: MessageBubble(
              message: message,
              isMine: isMine,
              firstInRun: firstInRun,
              showName: showSender && firstInRun,
              senderName: senderName,
              maxWidth: selectionMode
                  ? (maxBubbleWidth - 34).clamp(140.0, maxBubbleWidth)
                  : maxBubbleWidth,
              peerReadMark: peerReadMark,
              fontSize: messageFontSize,
              cornerRadius: bubbleRadius,
              onShowHistory: onShowHistory,
              onRetry: onRetry,
              onOpenPhoto: onOpenPhoto,
              onOpenVideo: onOpenVideo,
              onOpenFile: onOpenFile,
              fileProgressOf: fileProgressOf,
              onResolveAudio: onResolveAudio,
              onOpenLink: onOpenLink,
            ),
          ),
        );
        if (selectionMode || onDoubleTapQuickReaction == null) {
          return gesture;
        }
        return _QuickDoubleTapDetector(
          onDoubleTap: onDoubleTapQuickReaction!,
          child: gesture,
        );
      },
    );

    Widget rowContent = Padding(
      padding: EdgeInsets.only(top: firstInRun ? 8 : 2),
      child: Row(
        mainAxisAlignment: isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (selectionMode) ...[
            Padding(
              padding: const EdgeInsets.only(right: 10, bottom: 8),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isSelected ? p.accent : Colors.transparent,
                  shape: BoxShape.circle,
                  border: isSelected
                      ? null
                      : Border.all(
                          color: p.fg3.withValues(alpha: 0.55),
                          width: 1.6,
                        ),
                ),
                child: isSelected
                    ? const TalerIcon(
                        TalerIcons.check,
                        size: 14,
                        color: Colors.white,
                        morph: false,
                      )
                    : null,
              ),
            ),
          ],
          if (showSender && !isMine) ...[
            SizedBox(
              width: 36,
              child: lastInRun
                  ? TalerAvatar(
                      seedId: message.senderId,
                      initials: _initials(senderName),
                      imageUrl: senderAvatarUrl,
                      size: 36,
                    )
                  : null,
            ),
            const SizedBox(width: 8),
          ],
          if (selectionMode && isMine) const Spacer(),
          Flexible(
            child: Column(
              crossAxisAlignment: isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                bubble,
                if (message.reactions.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: [
                        for (final r in message.reactions)
                          _ReactionChip(
                            reaction: r,
                            palette: p,
                            onTap: selectionMode
                                ? (onToggleSelect ?? () {})
                                : () => onToggleReaction(r.emoji),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );

    if (selectionMode) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onToggleSelect,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          decoration: BoxDecoration(
            color: isSelected
                ? p.accent.withValues(alpha: p.isDark ? 0.16 : 0.10)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          child: rowContent,
        ),
      );
    }

    if (onSwipeReply != null) {
      return _SwipeToReplyWrapper(
        onReply: onSwipeReply!,
        child: rowContent,
      );
    }
    return rowContent;
  }

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    String firstRune(String s) => String.fromCharCode(s.runes.first).toUpperCase();
    if (parts.length == 1) return firstRune(parts.first);
    return '${firstRune(parts[0])}${firstRune(parts[1])}';
  }
}

class _QuickDoubleTapDetector extends StatefulWidget {
  final VoidCallback onDoubleTap;
  final Widget child;

  const _QuickDoubleTapDetector({
    required this.onDoubleTap,
    required this.child,
  });

  @override
  State<_QuickDoubleTapDetector> createState() => _QuickDoubleTapDetectorState();
}

class _QuickDoubleTapDetectorState extends State<_QuickDoubleTapDetector> {
  Offset? _downPos;
  DateTime? _downAt;
  Offset? _lastTapPos;
  DateTime? _lastTapAt;

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (e) {
        _downPos = e.position;
        _downAt = DateTime.now();
      },
      onPointerUp: (e) {
        final downPos = _downPos;
        final downAt = _downAt;
        _downPos = null;
        _downAt = null;
        if (downPos == null || downAt == null) return;
        final now = DateTime.now();
        if ((e.position - downPos).distance > 18.0 ||
            now.difference(downAt) > const Duration(milliseconds: 260)) {
          return;
        }
        final prevAt = _lastTapAt;
        final prevPos = _lastTapPos;
        if (prevAt != null &&
            prevPos != null &&
            now.difference(prevAt) <= const Duration(milliseconds: 340) &&
            (e.position - prevPos).distance <= 36.0) {
          _lastTapAt = null;
          _lastTapPos = null;
          widget.onDoubleTap();
        } else {
          _lastTapAt = now;
          _lastTapPos = e.position;
        }
      },
      child: widget.child,
    );
  }
}

class _SwipeToReplyWrapper extends StatefulWidget {
  final Widget child;
  final VoidCallback onReply;

  const _SwipeToReplyWrapper({
    required this.child,
    required this.onReply,
  });

  @override
  State<_SwipeToReplyWrapper> createState() => _SwipeToReplyWrapperState();
}

class _SwipeToReplyWrapperState extends State<_SwipeToReplyWrapper>
    with SingleTickerProviderStateMixin {
  static const double _triggerThreshold = 48.0;
  static const double _maxDrag = 74.0;

  late final AnimationController _snapCtrl;
  double _dragDx = 0.0;
  double _snapFrom = 0.0;
  bool _triggered = false;

  @override
  void initState() {
    super.initState();
    _snapCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 210),
    )..addListener(() {
        final t = Curves.easeOutCubic.transform(_snapCtrl.value);
        setState(() => _dragDx = _snapFrom * (1.0 - t));
      });
  }

  @override
  void dispose() {
    _snapCtrl.dispose();
    super.dispose();
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (_snapCtrl.isAnimating) _snapCtrl.stop();
    final delta = details.delta.dx;
    if (_dragDx == 0 && delta > 0) return;
    final resistance = _dragDx.abs() > _triggerThreshold ? 0.35 : 0.85;
    final next = (_dragDx + delta * resistance).clamp(-_maxDrag, 0.0);
    if ((next - _dragDx).abs() < 0.1) return;
    final crossed = !_triggered && next.abs() >= _triggerThreshold;
    if (crossed) {
      _triggered = true;
      unawaited(HapticFeedback.lightImpact());
    } else if (_triggered && next.abs() < _triggerThreshold * 0.85) {
      _triggered = false;
    }
    setState(() => _dragDx = next);
  }

  void _onDragEnd() {
    final shouldReply = _triggered;
    _triggered = false;
    if (_dragDx.abs() > 0.5) {
      _snapFrom = _dragDx;
      _snapCtrl.forward(from: 0.0);
    }
    if (shouldReply) {
      widget.onReply();
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = TalerTheme.paletteOf(context);
    final progress = (_dragDx.abs() / _triggerThreshold).clamp(0.0, 1.0);
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragUpdate: _onDragUpdate,
      onHorizontalDragEnd: (_) => _onDragEnd(),
      onHorizontalDragCancel: _onDragEnd,
      child: Stack(
        alignment: Alignment.centerRight,
        clipBehavior: Clip.none,
        children: [
          if (progress > 0.02)
            Positioned(
              right: 6,
              child: Opacity(
                opacity: progress,
                child: Transform.scale(
                  scale: 0.58 + 0.42 * progress,
                  child: Container(
                    width: 34,
                    height: 34,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: progress >= 1.0 ? p.accent : p.surface2,
                      shape: BoxShape.circle,
                    ),
                    child: TalerIcon(
                      TalerIcons.reply,
                      size: 17,
                      color: progress >= 1.0 ? Colors.white : p.fg2,
                      morph: false,
                    ),
                  ),
                ),
              ),
            ),
          Transform.translate(
            offset: Offset(_dragDx, 0),
            child: widget.child,
          ),
        ],
      ),
    );
  }
}

class _ReactionChip extends StatelessWidget {
  final TalerReactionCounter reaction;
  final TalerPalette palette;
  final VoidCallback onTap;

  const _ReactionChip({required this.reaction, required this.palette, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final mine = reaction.isMine;
    final bg = mine
        ? p.accent
        : (p.isDark
            ? const Color(0xFF1F2128)
            : Colors.black.withValues(alpha: 0.065));
    final countColor = mine ? Colors.white : p.fg2;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        splashFactory: NoSplash.splashFactory,
        highlightColor: p.fg.withValues(alpha: 0.08),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          height: 26,
          padding: const EdgeInsets.symmetric(horizontal: 9),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(reaction.emoji, style: const TextStyle(fontSize: 14.5)),
              const SizedBox(width: 4.5),
              Text(
                '${reaction.count}',
                style: TalerTheme.tabularStyle(
                  size: 12,
                  weight: FontWeight.w600,
                  color: countColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Пузырь сообщения. Подряд идущие сообщения одного автора склеиваются:
/// угол со стороны отправителя остаётся острым.
class MessageBubble extends StatelessWidget {
  final TalerMessage message;
  final bool isMine;
  final bool firstInRun;
  final bool showName;
  final String senderName;
  final double maxWidth;
  final int? peerReadMark;
  final double fontSize;
  final double cornerRadius;
  final VoidCallback? onShowHistory;
  final VoidCallback? onRetry;
  final void Function(TalerAttachment photo)? onOpenPhoto;
  final void Function(TalerAttachment video)? onOpenVideo;
  final void Function(TalerAttachment file)? onOpenFile;
  final double? Function(TalerAttachment file)? fileProgressOf;
  final Future<String?> Function(TalerAttachment audio)? onResolveAudio;
  final void Function(String url)? onOpenLink;

  const MessageBubble({
    super.key,
    required this.message,
    required this.isMine,
    required this.firstInRun,
    required this.showName,
    required this.senderName,
    required this.maxWidth,
    this.peerReadMark,
    this.fontSize = 15.0,
    this.cornerRadius = 20.0,
    this.onShowHistory,
    this.onRetry,
    this.onOpenPhoto,
    this.onOpenVideo,
    this.onOpenFile,
    this.fileProgressOf,
    this.onResolveAudio,
    this.onOpenLink,
  });

  static const double _small = 6;

  String? _resolvedStatus(TalerMessage m) {
    if (!isMine) return null;
    if (m.status == 'error' || m.status == 'sending' || m.status == 'pending') {
      return m.status;
    }
    if (m.status == 'read' ||
        (!m.deletedByPeer && peerReadMark != null && peerReadMark! >= m.time)) {
      return 'read';
    }
    return m.status;
  }

  @override
  Widget build(BuildContext context) {
    final p = TalerTheme.paletteOf(context);
    final m = message;
    final big = cornerRadius;
    final radius = isMine
        ? BorderRadius.only(
            topLeft: Radius.circular(big),
            topRight: Radius.circular(firstInRun ? big : _small),
            bottomRight: const Radius.circular(_small),
            bottomLeft: Radius.circular(big),
          )
        : BorderRadius.only(
            topLeft: Radius.circular(firstInRun ? big : _small),
            topRight: Radius.circular(big),
            bottomRight: Radius.circular(big),
            bottomLeft: const Radius.circular(_small),
          );
    final deleted = m.deletedByPeer;
    final out = isMine && !deleted;
    final failed = isMine && m.status == 'error';
    final bg = out ? p.bubbleOut : p.bubbleIn;
    final fg = out ? p.bubbleOutText : p.bubbleInText;
    final metaColor = out
        ? p.bubbleOutText.withValues(alpha: 0.78)
        : (p.isDark ? p.fg2.withValues(alpha: 0.85) : p.fg3);

    final photos = <TalerAttachment>[];
    final videos = <TalerAttachment>[];
    final stickers = <TalerAttachment>[];
    final audios = <TalerAttachment>[];
    final shares = <TalerAttachment>[];
    final files = <TalerAttachment>[];

    for (final a in m.attachments) {
      switch (a.type) {
        case 'CONTROL':
        case 'INLINE_KEYBOARD':
        case 'REPLY_KEYBOARD':
        case 'WIDGET':
          break;
        case 'PHOTO':
          if (a.url != null) photos.add(a);
          break;
        case 'VIDEO':
        case 'VIDEO_MSG':
        case 'VIDEO_NOTE':
          videos.add(a);
          break;
        case 'STICKER':
          if ((a.thumbnailUrl ?? a.url) != null) stickers.add(a);
          break;
        case 'AUDIO':
        case 'VOICE':
          audios.add(a);
          break;
        case 'SHARE':
        case 'LINK':
        case 'MEDIA_SHARE':
          shares.add(a);
          break;
        case 'FILE':
          files.add(a);
          break;
        default:
          if (a.fileName != null || a.fileSize != null || a.fileId != null) {
            files.add(a);
          } else if (a.url != null || a.previewText != null || a.description != null) {
            shares.add(a);
          }
          break;
      }
    }

    final hasText = m.text.trim().isNotEmpty;
    final hasAnyAttachment = photos.isNotEmpty ||
        videos.isNotEmpty ||
        stickers.isNotEmpty ||
        audios.isNotEmpty ||
        shares.isNotEmpty ||
        files.isNotEmpty;

    final meta = MessageMeta(
      time: m.time,
      color: metaColor,
      edited: m.isEdited,
      deleted: deleted,
      status: _resolvedStatus(m),
      onTapEdited: onShowHistory,
      onTapRetry: failed ? onRetry : null,
    );

    final metaInShare = shares.isNotEmpty;
    final metaInText = hasText && !metaInShare;
    final metaInFile = !hasText && !metaInShare && files.isNotEmpty;
    final metaInAudio = !hasText && !metaInShare && files.isEmpty && audios.isNotEmpty;
    final metaInVideo =
        !hasText && !metaInShare && files.isEmpty && audios.isEmpty && videos.isNotEmpty;
    final metaInSticker = !hasText &&
        !metaInShare &&
        files.isEmpty &&
        audios.isEmpty &&
        videos.isEmpty &&
        stickers.isNotEmpty;
    final metaInPhoto = !hasText &&
        !metaInShare &&
        files.isEmpty &&
        audios.isEmpty &&
        videos.isEmpty &&
        stickers.isEmpty &&
        photos.isNotEmpty;

    final children = <Widget>[];
    if (showName) {
      children.add(Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: Text(
          senderName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: ChatTokens.peerColor(m.senderId)),
        ),
      ));
    }
    final forwarded = m.forwardedFromName;
    if (forwarded != null && forwarded.isNotEmpty) {
      children.add(Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: Text(
          'Переслано от $forwarded',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: out ? fg : p.accent),
        ),
      ));
    }
    for (final photo in photos) {
      children.add(
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onOpenPhoto != null ? () => onOpenPhoto!(photo) : null,
          child: _PhotoView(
            attachment: photo,
            width: maxWidth,
            overlayMeta: metaInPhoto && photo == photos.last ? meta : null,
          ),
        ),
      );
    }
    for (final video in videos) {
      children.add(
        _VideoView(
          attachment: video,
          width: maxWidth,
          overlayMeta: metaInVideo && video == videos.last ? meta : null,
          onTap: onOpenVideo != null ? () => onOpenVideo!(video) : null,
        ),
      );
    }
    for (final sticker in stickers) {
      children.add(
        _StickerView(
          attachment: sticker,
          overlayMeta: metaInSticker && sticker == stickers.last ? meta : null,
        ),
      );
    }
    final reply = m.replyTo;
    if (reply != null) {
      children.add(Container(
        margin: const EdgeInsets.fromLTRB(8, 8, 8, 0),
        padding: const EdgeInsets.fromLTRB(10, 4, 12, 4),
        decoration: BoxDecoration(
          color: out ? Colors.white.withValues(alpha: 0.16) : ChatTokens.accentSoft(p),
          borderRadius: BorderRadius.circular(8),
          border: Border(left: BorderSide(color: out ? Colors.white.withValues(alpha: 0.8) : p.accent, width: 3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              reply.senderName ?? 'Ответ',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: out ? Colors.white : p.accent),
            ),
            Text(
              (reply.text ?? '').isEmpty ? 'Вложение' : reply.text!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, color: fg.withValues(alpha: 0.85)),
            ),
          ],
        ),
      ));
    }
    for (final audio in audios) {
      final isLast = audio == audios.last;
      children.add(_AudioView(
        audioKey: '${m.id}:${audio.audioId ?? audio.fileId ?? audio.url ?? audio.fileName ?? 'audio'}',
        attachment: audio,
        out: out,
        palette: p,
        metaColor: metaColor,
        maxWidth: maxWidth,
        inlineMeta: metaInAudio && isLast ? meta : null,
        bottomPadding: metaInAudio && isLast ? 8 : 0,
        onResolveSource: onResolveAudio != null ? () => onResolveAudio!(audio) : null,
      ));
    }
    for (final file in files) {
      final isLast = file == files.last;
      children.add(_FileView(
        attachment: file,
        out: out,
        palette: p,
        metaColor: metaColor,
        inlineMeta: metaInFile && isLast ? meta : null,
        bottomPadding: metaInFile && isLast ? 8 : 0,
        downloadProgress: fileProgressOf?.call(file),
        onTap: onOpenFile != null ? () => onOpenFile!(file) : null,
      ));
    }
    if (hasText) {
      final topPad = (showName ||
              reply != null ||
              files.isNotEmpty ||
              audios.isNotEmpty ||
              photos.isNotEmpty ||
              videos.isNotEmpty ||
              stickers.isNotEmpty ||
              forwarded != null)
          ? 4.0
          : 7.0;
      final linkColor = out ? Colors.white : p.accent;
      if (metaInText) {
        children.add(Stack(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(12, topPad, 12, 7),
              child: _LinkifiedText(
                text: m.text,
                style: TextStyle(fontSize: fontSize, height: 1.4, color: fg),
                linkColor: linkColor,
                trailingSpacerWidth: meta.estimatedWidth + 6,
                onOpenLink: onOpenLink,
              ),
            ),
            Positioned(right: 10, bottom: 5, child: meta),
          ],
        ));
      } else {
        children.add(Padding(
          padding: EdgeInsets.fromLTRB(12, topPad, 12, 6),
          child: _LinkifiedText(
            text: m.text,
            style: TextStyle(fontSize: fontSize, height: 1.4, color: fg),
            linkColor: linkColor,
            onOpenLink: onOpenLink,
          ),
        ));
      }
    }
    for (final share in shares) {
      final isLast = share == shares.last;
      children.add(_SharePreviewView(
        attachment: share,
        out: out,
        palette: p,
        fg: fg,
        width: maxWidth,
        topMargin: hasText || children.isNotEmpty ? 2 : 8,
        trailingMeta: metaInShare && isLast ? meta : null,
        onOpenLink: onOpenLink,
      ));
    }
    if (!hasText && !hasAnyAttachment) {
      children.add(Padding(
        padding: const EdgeInsets.fromLTRB(12, 7, 12, 7),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Вложение', style: TextStyle(fontSize: 15, color: fg.withValues(alpha: 0.7))),
            const SizedBox(width: 10),
            meta,
          ],
        ),
      ));
    }

    final bubble = ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: radius,
          border: failed ? Border.all(color: p.danger, width: 1.5) : null,
        ),
        child: IntrinsicWidth(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: children,
          ),
        ),
      ),
    );
    // Сохранённое после удаления собеседником: тот же пузырь, но приглушённый.
    return deleted ? Opacity(opacity: 0.5, child: bubble) : bubble;
  }
}

/// Время, значки «изменено» / «удалено» и статус прочтения.
class MessageMeta extends StatelessWidget {
  final int time;
  final Color color;
  final bool edited;
  final bool deleted;
  final String? status;
  final VoidCallback? onTapEdited;
  final VoidCallback? onTapRetry;

  const MessageMeta({
    super.key,
    required this.time,
    required this.color,
    this.edited = false,
    this.deleted = false,
    this.status,
    this.onTapEdited,
    this.onTapRetry,
  });

  /// Примерная ширина, чтобы зарезервировать место в последней строке текста.
  double get estimatedWidth =>
      32 + (edited ? 14 : 0) + (deleted ? 16 : 0) + (status != null ? 18 : 0);

  @override
  Widget build(BuildContext context) {
    final p = TalerTheme.paletteOf(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (deleted) ...[
          Tooltip(
            message: 'Удалено собеседником, сохранено Taler',
            child: TalerIcon(TalerIcons.trash, size: 13, color: color, semanticLabel: 'Удалено собеседником'),
          ),
          const SizedBox(width: 4),
        ],
        if (edited) ...[
          GestureDetector(
            onTap: onTapEdited,
            child: Tooltip(
              message: 'Изменено',
              child: TalerIcon(TalerIcons.pencil, size: 12, color: color, semanticLabel: 'Изменено'),
            ),
          ),
          const SizedBox(width: 4),
        ],
        Text(ChatTokens.time(time), style: TalerTheme.tabularStyle(size: 11, color: color)),
        if (status != null) ...[
          const SizedBox(width: 4),
          if (status == 'error')
            GestureDetector(
              onTap: onTapRetry,
              child: Tooltip(
                message: 'Не отправлено · нажмите для повтора',
                child: Container(
                  width: 16,
                  height: 16,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: p.danger, shape: BoxShape.circle),
                  child: const TalerIcon(
                    TalerIcons.alertCircle,
                    size: 11,
                    color: Colors.white,
                    semanticLabel: 'Не отправлено',
                  ),
                ),
              ),
            )
          else if (status == 'sending' || status == 'pending')
            Tooltip(
              message: 'Отправка…',
              child: TalerIcon(
                TalerIcons.history,
                size: 12,
                color: color,
                semanticLabel: 'Отправка',
              ),
            )
          else
            TalerIcon(
              status == 'read' ? TalerIcons.checkCheck : TalerIcons.check,
              size: 15,
              color: color,
              strokeWidth: 2,
            ),
        ],
      ],
    );
  }
}

class _PhotoView extends StatelessWidget {
  final TalerAttachment attachment;
  final double width;
  final MessageMeta? overlayMeta;

  const _PhotoView({required this.attachment, required this.width, this.overlayMeta});

  @override
  Widget build(BuildContext context) {
    final p = TalerTheme.paletteOf(context);
    final url = attachment.url!;
    final w = attachment.width;
    final h = attachment.height;
    final ratio = (w != null && h != null && w > 0 && h > 0) ? (w / h).clamp(0.6, 2.0) : 4 / 3;
    final targetWidth = width.clamp(160.0, 360.0);
    final isHttp = url.startsWith('http://') || url.startsWith('https://');
    final cachePx = (targetWidth * MediaQuery.devicePixelRatioOf(context)).round();
    final placeholder = Container(
      color: p.bg3,
      child: Center(
        child: TalerIcon(TalerIcons.image, size: 28, color: p.fg4),
      ),
    );
    final image = isHttp
        ? TalerCachedImage(
            url: url,
            fit: BoxFit.cover,
            cacheWidth: cachePx,
            placeholder: placeholder,
            errorWidget: placeholder,
          )
        : Image.file(
            File(url),
            fit: BoxFit.cover,
            cacheWidth: cachePx,
            errorBuilder: (_, _, _) => placeholder,
          );
    final meta = overlayMeta;
    return SizedBox(
      width: targetWidth,
      child: AspectRatio(
        aspectRatio: ratio,
        child: Stack(
          fit: StackFit.expand,
          children: [
            image,
            if (meta != null)
              Positioned(
                right: 8,
                bottom: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: MessageMeta(
                    time: meta.time,
                    color: Colors.white,
                    edited: meta.edited,
                    deleted: meta.deleted,
                    status: meta.status,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _LinkifiedText extends StatefulWidget {
  final String text;
  final TextStyle style;
  final Color linkColor;
  final double? trailingSpacerWidth;
  final void Function(String url)? onOpenLink;

  const _LinkifiedText({
    required this.text,
    required this.style,
    required this.linkColor,
    this.trailingSpacerWidth,
    this.onOpenLink,
  });

  @override
  State<_LinkifiedText> createState() => _LinkifiedTextState();
}

class _LinkifiedTextState extends State<_LinkifiedText> {
  static final RegExp _urlRegex = RegExp(
    r'((?:https?:\/\/|www\.)[^\s<>"\)\]]+|\b(?:t\.me|max\.ru|vk\.com|vkvideo\.ru|youtu\.be|youtube\.com|rutube\.ru|github\.com)\/[^\s<>"\)\]]+)',
    caseSensitive: false,
  );

  final List<TapGestureRecognizer> _recognizers = [];

  @override
  void dispose() {
    _clearRecognizers();
    super.dispose();
  }

  void _clearRecognizers() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  void _open(String rawUrl) {
    final normalized = rawUrl.contains('://') ? rawUrl : 'https://$rawUrl';
    final cb = widget.onOpenLink;
    if (cb != null) {
      cb(normalized);
    } else {
      unawaited(TalerNativeBridge.instance.openUrl(normalized));
    }
  }

  @override
  Widget build(BuildContext context) {
    _clearRecognizers();
    final spans = <InlineSpan>[];
    final text = widget.text;
    var cursor = 0;

    for (final match in _urlRegex.allMatches(text)) {
      if (match.start > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, match.start)));
      }
      var raw = match.group(0)!;
      var suffix = '';
      while (raw.isNotEmpty && '.,!?;:'.contains(raw[raw.length - 1])) {
        suffix = raw[raw.length - 1] + suffix;
        raw = raw.substring(0, raw.length - 1);
      }
      if (raw.isNotEmpty) {
        final target = raw;
        final rec = TapGestureRecognizer()..onTap = () => _open(target);
        _recognizers.add(rec);
        spans.add(
          TextSpan(
            text: raw,
            recognizer: rec,
            style: widget.style.copyWith(
              color: widget.linkColor,
              decoration: TextDecoration.underline,
              decorationColor: widget.linkColor.withValues(alpha: 0.65),
            ),
          ),
        );
      }
      if (suffix.isNotEmpty) {
        spans.add(TextSpan(text: suffix));
      }
      cursor = match.end;
    }

    if (cursor < text.length) {
      spans.add(TextSpan(text: text.substring(cursor)));
    }
    if (widget.trailingSpacerWidth != null) {
      spans.add(
        WidgetSpan(
          child: SizedBox(width: widget.trailingSpacerWidth, height: 12),
        ),
      );
    }

    return Text.rich(
      TextSpan(children: spans),
      style: widget.style,
    );
  }
}

class _FileView extends StatelessWidget {
  final TalerAttachment attachment;
  final bool out;
  final TalerPalette palette;
  final Color metaColor;
  final MessageMeta? inlineMeta;
  final double bottomPadding;
  final double? downloadProgress;
  final VoidCallback? onTap;

  const _FileView({
    required this.attachment,
    required this.out,
    required this.palette,
    required this.metaColor,
    required this.inlineMeta,
    required this.bottomPadding,
    this.downloadProgress,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final name = attachment.fileName ?? attachment.previewText ?? 'Файл';
    final size = ChatTokens.fileSize(attachment.fileSize);
    final fg = out ? p.bubbleOutText : p.bubbleInText;
    final meta = inlineMeta;
    final prog = downloadProgress;
    final statusText = prog != null
        ? 'Загрузка ${(prog * 100).round()}%'
        : (size.isNotEmpty ? size : 'Нажмите, чтобы скачать');

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.fromLTRB(12, 10, 12, bottomPadding > 0 ? bottomPadding : 8),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: out ? Colors.white.withValues(alpha: 0.18) : p.accent,
                borderRadius: BorderRadius.circular(12),
              ),
              child: prog != null
                  ? SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        value: prog > 0.06 ? prog : null,
                        strokeWidth: 2.2,
                        color: Colors.white,
                      ),
                    )
                  : const TalerIcon(TalerIcons.file, size: 20, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: fg),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          statusText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TalerTheme.tabularStyle(size: 12, color: metaColor),
                        ),
                      ),
                      if (meta != null) ...[
                        const SizedBox(width: 14),
                        meta,
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Форматирует длительность аудио/голосового строго из миллисекунд.
/// При `roundUpForTotal = true` короткие записи (< 1 сек, > 0 мс) показываются как `0:01`.
String formatAudioDurationMs(int? ms, {bool roundUpForTotal = false}) {
  if (ms == null || ms <= 0) return '0:00';
  final secs = roundUpForTotal
      ? ((ms / 1000).round()).clamp(1, 359999)
      : (ms ~/ 1000).clamp(0, 359999);
  final hours = secs ~/ 3600;
  final mins = (secs % 3600) ~/ 60;
  final rem = secs % 60;
  final ss = rem.toString().padLeft(2, '0');
  if (hours > 0) {
    final mm = mins.toString().padLeft(2, '0');
    return '$hours:$mm:$ss';
  }
  return '$mins:$ss';
}

String _formatAttachmentDuration(int? raw) {
  if (raw == null || raw <= 0) return '';
  final secs = raw >= 10000 ? (raw / 1000).round() : raw;
  final hours = secs ~/ 3600;
  final mins = (secs % 3600) ~/ 60;
  final rem = secs % 60;
  final ss = rem.toString().padLeft(2, '0');
  if (hours > 0) {
    final mm = mins.toString().padLeft(2, '0');
    return '$hours:$mm:$ss';
  }
  return '$mins:$ss';
}

bool _looksLikeVideoHost(String? host) {
  if (host == null || host.isEmpty) return false;
  final h = host.toLowerCase();
  return h.contains('youtube.com') ||
      h.contains('youtu.be') ||
      h.contains('rutube.ru') ||
      h.contains('vkvideo.ru') ||
      h.contains('vimeo.com') ||
      h.contains('tiktok.com') ||
      h.contains('twitch.tv');
}

String? _extractDisplayHost(String? rawUrl) {
  if (rawUrl == null || rawUrl.trim().isEmpty) return null;
  final uri = Uri.tryParse(rawUrl.trim());
  final host = uri?.host ?? '';
  if (host.isEmpty) return null;
  return host.startsWith('www.') ? host.substring(4) : host;
}

class _VideoView extends StatelessWidget {
  final TalerAttachment attachment;
  final double width;
  final MessageMeta? overlayMeta;
  final VoidCallback? onTap;

  const _VideoView({
    required this.attachment,
    required this.width,
    this.overlayMeta,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isNote = attachment.type == 'VIDEO_MSG' || attachment.type == 'VIDEO_NOTE';
    final w = attachment.width;
    final h = attachment.height;
    final ratio = isNote
        ? 1.0
        : (w != null && h != null && w > 0 && h > 0)
            ? (w / h).clamp(0.65, 1.9)
            : 16 / 9;
    final targetWidth = isNote
        ? width.clamp(160.0, 224.0)
        : width.clamp(200.0, 340.0);
    final thumb = attachment.thumbnailUrl;
    final dur = _formatAttachmentDuration(attachment.durationMs);
    final badgeLabel = dur.isNotEmpty
        ? dur
        : (isNote ? 'Видеосообщение' : 'Видео');
    final title = (attachment.previewText ?? attachment.fileName)?.trim() ?? '';
    final cachePx = (targetWidth * MediaQuery.devicePixelRatioOf(context)).round();

    Widget fallbackBg() => DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF1D202A), Color(0xFF101218)],
            ),
          ),
        );

    Widget bgLayer = fallbackBg();
    if (thumb != null && thumb.isNotEmpty) {
      final isHttp = thumb.startsWith('http://') || thumb.startsWith('https://');
      bgLayer = isHttp
          ? TalerCachedImage(
              url: thumb,
              fit: BoxFit.cover,
              cacheWidth: cachePx,
              placeholder: fallbackBg(),
              errorWidget: fallbackBg(),
            )
          : Image.file(
              File(thumb),
              fit: BoxFit.cover,
              cacheWidth: cachePx,
              errorBuilder: (_, _, _) => fallbackBg(),
            );
    }

    final meta = overlayMeta;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap ??
          () {
            final link = attachment.url;
            if (link != null && link.isNotEmpty) {
              unawaited(TalerNativeBridge.instance.openUrl(link));
            }
          },
      child: SizedBox(
        width: targetWidth,
        child: AspectRatio(
          aspectRatio: ratio,
          child: Stack(
            fit: StackFit.expand,
            children: [
              bgLayer,
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.22),
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.42),
                    ],
                    stops: const [0.0, 0.5, 1.0],
                  ),
                ),
              ),
              Center(
                child: Container(
                  width: 50,
                  height: 50,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.56),
                    shape: BoxShape.circle,
                  ),
                  child: const Padding(
                    padding: EdgeInsets.only(left: 2),
                    child: TalerIcon(
                      TalerIcons.play,
                      size: 22,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 8,
                top: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.54),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    badgeLabel,
                    style: TalerTheme.tabularStyle(
                      size: 11,
                      weight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              if (title.isNotEmpty && meta == null)
                Positioned(
                  left: 10,
                  right: 10,
                  bottom: 8,
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                      color: Colors.white,
                    ),
                  ),
                ),
              if (meta != null)
                Positioned(
                  right: 8,
                  bottom: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.48),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: MessageMeta(
                      time: meta.time,
                      color: Colors.white,
                      edited: meta.edited,
                      deleted: meta.deleted,
                      status: meta.status,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StickerView extends StatelessWidget {
  final TalerAttachment attachment;
  final MessageMeta? overlayMeta;

  const _StickerView({required this.attachment, this.overlayMeta});

  @override
  Widget build(BuildContext context) {
    final p = TalerTheme.paletteOf(context);
    final url = (attachment.thumbnailUrl ?? attachment.url)!;
    final isHttp = url.startsWith('http://') || url.startsWith('https://');
    final placeholder = Center(
      child: TalerIcon(TalerIcons.image, size: 28, color: p.fg4),
    );
    final image = isHttp
        ? TalerCachedImage(
            url: url,
            fit: BoxFit.contain,
            cacheWidth: 320,
            placeholder: placeholder,
            errorWidget: placeholder,
          )
        : Image.file(
            File(url),
            fit: BoxFit.contain,
            cacheWidth: 320,
            errorBuilder: (_, _, _) => placeholder,
          );
    final meta = overlayMeta;
    return Padding(
      padding: const EdgeInsets.all(8),
      child: SizedBox(
        width: 148,
        height: 148,
        child: Stack(
          fit: StackFit.expand,
          children: [
            image,
            if (meta != null)
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: MessageMeta(
                    time: meta.time,
                    color: Colors.white,
                    edited: meta.edited,
                    deleted: meta.deleted,
                    status: meta.status,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _AudioView extends StatelessWidget {
  final String audioKey;
  final TalerAttachment attachment;
  final bool out;
  final TalerPalette palette;
  final Color metaColor;
  final double maxWidth;
  final MessageMeta? inlineMeta;
  final double bottomPadding;
  final Future<String?> Function()? onResolveSource;

  const _AudioView({
    required this.audioKey,
    required this.attachment,
    required this.out,
    required this.palette,
    required this.metaColor,
    required this.maxWidth,
    required this.inlineMeta,
    required this.bottomPadding,
    this.onResolveSource,
  });

  /// Нормализует амплитуды `wave` (из MAX или записи) в `targetCount` столбиков [0.12..1.0].
  static List<double> _buildNormalizedBars(
    List<int>? rawWave,
    int seed, {
    int targetCount = 34,
  }) {
    if (rawWave != null && rawWave.isNotEmpty) {
      var maxAmp = 1;
      for (final v in rawWave) {
        if (v > maxAmp) maxAmp = v;
      }
      final hasSignal = maxAmp > 1;
      if (hasSignal) {
        final bars = List<double>.filled(targetCount, 0.14);
        final step = rawWave.length / targetCount;
        for (var i = 0; i < targetCount; i++) {
          final start = (i * step).floor().clamp(0, rawWave.length - 1);
          final end = ((i + 1) * step).ceil().clamp(start + 1, rawWave.length);
          var peak = 0;
          for (var j = start; j < end; j++) {
            if (rawWave[j] > peak) peak = rawWave[j];
          }
          // Мягкая логарифмическая кривая, чтобы тихая речь читалась ровно и без резких провалов.
          final lin = (peak / maxAmp).clamp(0.0, 1.0);
          final shaped = lin <= 0 ? 0.12 : (0.12 + 0.88 * (lin * 0.65 + (lin * lin) * 0.35));
          bars[i] = shaped.clamp(0.12, 1.0);
        }
        return bars;
      }
    }

    // Спокойная естественная огибающая для аудио без присланной волны.
    return List<double>.generate(targetCount, (i) {
      final t = i / (targetCount - 1);
      final envelope = 0.32 + 0.52 * (1.0 - (2.0 * t - 1.0) * (2.0 * t - 1.0));
      final detail = (((seed ^ (i * 73)) & 0x1F) / 31.0) * 0.38;
      return (envelope * (0.58 + detail)).clamp(0.14, 0.92);
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final fg = out ? p.bubbleOutText : p.bubbleInText;
    final activeBarColor = out ? Colors.white : p.accent;
    final inactiveBarColor = out
        ? Colors.white.withValues(alpha: 0.34)
        : (p.isDark ? Colors.white.withValues(alpha: 0.22) : p.accent.withValues(alpha: 0.26));
    final seed = (attachment.audioId ?? attachment.url ?? attachment.fileName ?? 'audio').hashCode;
    final bars = _buildNormalizedBars(attachment.waveform, seed);
    final meta = inlineMeta;
    final ctrl = TalerAudioController.instance;
    final bubbleW = (maxWidth - 24).clamp(212.0, 256.0);

    return ListenableBuilder(
      listenable: ctrl,
      builder: (context, _) {
        final isActive = ctrl.activeKey == audioKey;
        final isLoading = ctrl.isLoadingKey(audioKey);
        final isPlaying = ctrl.isPlayingKey(audioKey);
        final progress = ctrl.progressFor(audioKey);
        final totalMs = (isActive && ctrl.durationMs > 0)
            ? ctrl.durationMs
            : (attachment.durationMs ?? 0);
        final totalText = totalMs > 0
            ? formatAudioDurationMs(totalMs, roundUpForTotal: true)
            : '0:00';
        final timeLabel = isActive && (isPlaying || ctrl.positionMs > 0)
            ? '${formatAudioDurationMs(ctrl.positionMs)} / $totalText'
            : totalText;

        Future<void> handlePlayToggle() async {
          final ok = await ctrl.toggle(
            key: audioKey,
            fallbackDurationMs: attachment.durationMs ?? 0,
            resolveSource: () async {
              if (onResolveSource != null) {
                return onResolveSource!();
              }
              return attachment.url;
            },
          );
          if (!ok && context.mounted) {
            final msg = ctrl.lastError ?? 'Не удалось воспроизвести голосовое';
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(msg)),
            );
          }
        }

        return SizedBox(
          width: bubbleW + 24,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              11,
              9,
              11,
              bottomPadding > 0 ? bottomPadding : 8,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => unawaited(handlePlayToggle()),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    width: 42,
                    height: 42,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: out
                          ? Colors.white.withValues(alpha: 0.22)
                          : p.accent,
                      shape: BoxShape.circle,
                    ),
                    child: isLoading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : isPlaying
                            ? Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 3.5,
                                    height: 14,
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(1.8),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Container(
                                    width: 3.5,
                                    height: 14,
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(1.8),
                                    ),
                                  ),
                                ],
                              )
                            : const Padding(
                                padding: EdgeInsets.only(left: 2.5),
                                child: TalerIcon(
                                  TalerIcons.play,
                                  size: 18,
                                  color: Colors.white,
                                  morph: false,
                                ),
                              ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _InteractiveWaveform(
                        bars: bars,
                        progress: isActive ? progress : 0.0,
                        activeColor: activeBarColor,
                        inactiveColor: inactiveBarColor,
                        interactive: isActive && totalMs > 0,
                        onSeek: (frac) => unawaited(ctrl.seek(audioKey, frac)),
                        onTapInactive: () => unawaited(handlePlayToggle()),
                      ),
                      const SizedBox(height: 5),
                      Row(
                        children: [
                          Text(
                            timeLabel,
                            style: TalerTheme.tabularStyle(
                              size: 11.5,
                              weight: FontWeight.w500,
                              color: out
                                  ? fg.withValues(alpha: 0.86)
                                  : metaColor,
                            ),
                          ),
                          if (isActive && !isLoading) ...[
                            const SizedBox(width: 6),
                            GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () => unawaited(ctrl.cycleSpeed()),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 5.5,
                                  vertical: 1.5,
                                ),
                                decoration: BoxDecoration(
                                  color: out
                                      ? Colors.white.withValues(alpha: 0.20)
                                      : p.accent.withValues(alpha: 0.14),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  ctrl.speedLabel,
                                  style: TalerTheme.tabularStyle(
                                    size: 10.5,
                                    weight: FontWeight.w600,
                                    color: out ? Colors.white : p.accent,
                                  ),
                                ),
                              ),
                            ),
                          ],
                          const Spacer(),
                          ?meta,
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _InteractiveWaveform extends StatelessWidget {
  final List<double> bars;
  final double progress;
  final Color activeColor;
  final Color inactiveColor;
  final bool interactive;
  final ValueChanged<double> onSeek;
  final VoidCallback onTapInactive;

  const _InteractiveWaveform({
    required this.bars,
    required this.progress,
    required this.activeColor,
    required this.inactiveColor,
    required this.interactive,
    required this.onSeek,
    required this.onTapInactive,
  });

  @override
  Widget build(BuildContext context) {
    void seekAt(double dx) {
      final box = context.findRenderObject() as RenderBox?;
      final w = box?.size.width ?? 0;
      if (w <= 0) return;
      onSeek((dx / w).clamp(0.0, 1.0));
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: (d) {
        if (!interactive) {
          onTapInactive();
        } else {
          seekAt(d.localPosition.dx);
        }
      },
      onHorizontalDragStart:
          interactive ? (d) => seekAt(d.localPosition.dx) : null,
      onHorizontalDragUpdate:
          interactive ? (d) => seekAt(d.localPosition.dx) : null,
      child: SizedBox(
        height: 26,
        width: double.infinity,
        child: CustomPaint(
          painter: _VoiceWaveformPainter(
            bars: bars,
            progress: progress,
            activeColor: activeColor,
            inactiveColor: inactiveColor,
          ),
        ),
      ),
    );
  }
}

class _VoiceWaveformPainter extends CustomPainter {
  final List<double> bars;
  final double progress;
  final Color activeColor;
  final Color inactiveColor;

  const _VoiceWaveformPainter({
    required this.bars,
    required this.progress,
    required this.activeColor,
    required this.inactiveColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (bars.isEmpty || size.width <= 0 || size.height <= 0) return;
    final n = bars.length;
    final slot = size.width / n;
    final barW = (slot * 0.56).clamp(2.0, 3.2);
    final radius = Radius.circular(barW / 2);
    final splitX = size.width * progress.clamp(0.0, 1.0);

    final inactivePaint = Paint()..color = inactiveColor;
    final activePaint = Paint()..color = activeColor;

    void drawBars(Paint paint) {
      for (var i = 0; i < n; i++) {
        final cx = i * slot + slot / 2;
        final h = (bars[i] * (size.height - 2)).clamp(3.0, size.height);
        final top = (size.height - h) / 2;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(cx - barW / 2, top, barW, h),
            radius,
          ),
          paint,
        );
      }
    }

    drawBars(inactivePaint);
    if (splitX > 0.5) {
      canvas.save();
      canvas.clipRect(Rect.fromLTWH(0, 0, splitX, size.height));
      drawBars(activePaint);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _VoiceWaveformPainter old) =>
      old.progress != progress ||
      old.activeColor != activeColor ||
      old.inactiveColor != inactiveColor ||
      old.bars != bars;
}

class _SharePreviewView extends StatelessWidget {
  final TalerAttachment attachment;
  final bool out;
  final TalerPalette palette;
  final Color fg;
  final double width;
  final double topMargin;
  final MessageMeta? trailingMeta;
  final void Function(String url)? onOpenLink;

  const _SharePreviewView({
    required this.attachment,
    required this.out,
    required this.palette,
    required this.fg,
    required this.width,
    required this.topMargin,
    this.trailingMeta,
    this.onOpenLink,
  });

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final host = _extractDisplayHost(attachment.url);
    final isVideoSite = _looksLikeVideoHost(host);
    final title = (attachment.previewText ?? attachment.fileName)?.trim() ?? '';
    final desc = attachment.description?.trim() ?? '';
    final showDesc = desc.isNotEmpty && desc != title;
    final thumb = attachment.thumbnailUrl;
    final cardWidth = (width - 16).clamp(180.0, 320.0);
    final accentBar = out ? Colors.white.withValues(alpha: 0.85) : p.accent;
    final cardBg = out
        ? Colors.white.withValues(alpha: 0.14)
        : (p.isDark
            ? Colors.white.withValues(alpha: 0.055)
            : ChatTokens.accentSoft(p));
    final cachePx = (cardWidth * MediaQuery.devicePixelRatioOf(context)).round();

    Widget? thumbWidget;
    if (thumb != null && thumb.isNotEmpty) {
      final isHttp = thumb.startsWith('http://') || thumb.startsWith('https://');
      final placeholder = Container(color: p.bg3);
      final img = isHttp
          ? TalerCachedImage(
              url: thumb,
              fit: BoxFit.cover,
              cacheWidth: cachePx,
              placeholder: placeholder,
              errorWidget: placeholder,
            )
          : Image.file(
              File(thumb),
              fit: BoxFit.cover,
              cacheWidth: cachePx,
              errorBuilder: (_, _, _) => placeholder,
            );
      thumbWidget = Padding(
        padding: const EdgeInsets.only(top: 8),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: cardWidth - 24,
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  img,
                  if (isVideoSite)
                    Center(
                      child: Container(
                        width: 42,
                        height: 42,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.56),
                          shape: BoxShape.circle,
                        ),
                        child: const Padding(
                          padding: EdgeInsets.only(left: 2),
                          child: TalerIcon(
                            TalerIcons.play,
                            size: 18,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final meta = trailingMeta;
    return Padding(
      padding: EdgeInsets.fromLTRB(8, topMargin, 8, meta != null ? 6 : 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: attachment.url == null || attachment.url!.isEmpty
                ? null
                : () {
                    final link = attachment.url!;
                    if (onOpenLink != null) {
                      onOpenLink!(link);
                    } else {
                      unawaited(TalerNativeBridge.instance.openUrl(link));
                    }
                  },
            onLongPress: attachment.url == null || attachment.url!.isEmpty
                ? null
                : () {
                    unawaited(Clipboard.setData(ClipboardData(text: attachment.url!)));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Ссылка скопирована')),
                    );
                  },
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: cardWidth),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(10, 7, 10, 8),
                  decoration: BoxDecoration(
                    color: cardBg,
                    border: Border(left: BorderSide(color: accentBar, width: 3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (host != null)
                        Text(
                          host,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: out ? Colors.white : p.accent,
                          ),
                        ),
                      if (title.isNotEmpty) ...[
                        if (host != null) const SizedBox(height: 2),
                        Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            height: 1.28,
                            color: fg,
                          ),
                        ),
                      ],
                      if (showDesc) ...[
                        const SizedBox(height: 3),
                        Text(
                          desc,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            height: 1.32,
                            color: fg.withValues(alpha: 0.78),
                          ),
                        ),
                      ],
                      ?thumbWidget,
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (meta != null) ...[
            const SizedBox(height: 5),
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(right: 4),
                child: meta,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

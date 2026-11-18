import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/media/taler_media_cache.dart';
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

/// Строка сообщения: аватар отправителя в группах, пузырь и реакции.
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
  final void Function(TalerAttachment photo)? onOpenPhoto;
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
    this.onOpenPhoto,
  });

  void _triggerActions(BuildContext bubbleCtx) {
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
      builder: (bubbleCtx) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: message.status == 'error' ? () => _triggerActions(bubbleCtx) : null,
        onLongPress: () => _triggerActions(bubbleCtx),
        onSecondaryTap: () => _triggerActions(bubbleCtx),
        child: MessageBubble(
          message: message,
          isMine: isMine,
          firstInRun: firstInRun,
          showName: showSender && firstInRun,
          senderName: senderName,
          maxWidth: maxBubbleWidth,
          peerReadMark: peerReadMark,
          fontSize: messageFontSize,
          cornerRadius: bubbleRadius,
          onShowHistory: onShowHistory,
          onRetry: onRetry,
          onOpenPhoto: onOpenPhoto,
        ),
      ),
    );

    return Padding(
      padding: EdgeInsets.only(top: firstInRun ? 8 : 2),
      child: Row(
        mainAxisAlignment: isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
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
                            onTap: () => onToggleReaction(r.emoji),
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
  }

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    String firstRune(String s) => String.fromCharCode(s.runes.first).toUpperCase();
    if (parts.length == 1) return firstRune(parts.first);
    return '${firstRune(parts[0])}${firstRune(parts[1])}';
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
        attachment: audio,
        out: out,
        palette: p,
        metaColor: metaColor,
        inlineMeta: metaInAudio && isLast ? meta : null,
        bottomPadding: metaInAudio && isLast ? 8 : 0,
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
      if (metaInText) {
        children.add(Stack(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(12, topPad, 12, 7),
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(text: m.text),
                  // Невидимое место под время, чтобы оно встало в последнюю строку.
                  WidgetSpan(child: SizedBox(width: meta.estimatedWidth + 6, height: 12)),
                ]),
                style: TextStyle(fontSize: fontSize, height: 1.4, color: fg),
              ),
            ),
            Positioned(right: 10, bottom: 5, child: meta),
          ],
        ));
      } else {
        children.add(Padding(
          padding: EdgeInsets.fromLTRB(12, topPad, 12, 6),
          child: Text(
            m.text,
            style: TextStyle(fontSize: fontSize, height: 1.4, color: fg),
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

class _FileView extends StatelessWidget {
  final TalerAttachment attachment;
  final bool out;
  final TalerPalette palette;
  final Color metaColor;
  final MessageMeta? inlineMeta;
  final double bottomPadding;

  const _FileView({
    required this.attachment,
    required this.out,
    required this.palette,
    required this.metaColor,
    required this.inlineMeta,
    required this.bottomPadding,
  });

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final name = attachment.fileName ?? attachment.previewText ?? 'Файл';
    final size = ChatTokens.fileSize(attachment.fileSize);
    final fg = out ? p.bubbleOutText : p.bubbleInText;
    final meta = inlineMeta;
    return Padding(
      padding: EdgeInsets.fromLTRB(12, 10, 12, bottomPadding),
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
            child: TalerIcon(TalerIcons.file, size: 20, color: Colors.white),
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
                    if (size.isNotEmpty) Text(size, style: TalerTheme.tabularStyle(size: 12, color: metaColor)),
                    if (meta != null) ...[
                      const SizedBox(width: 16),
                      meta,
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _formatAttachmentDuration(int? raw, {bool isAudio = false}) {
  if (raw == null || raw <= 0) return '';
  final secs = isAudio
      ? (raw >= 1000 ? (raw / 1000).round() : raw)
      : (raw >= 10000 ? (raw / 1000).round() : raw);
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

  const _VideoView({
    required this.attachment,
    required this.width,
    this.overlayMeta,
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
      onTap: () {
        final link = attachment.url;
        if (link != null && link.isNotEmpty) {
          unawaited(Clipboard.setData(ClipboardData(text: link)));
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Ссылка на видео скопирована')),
          );
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
  final TalerAttachment attachment;
  final bool out;
  final TalerPalette palette;
  final Color metaColor;
  final MessageMeta? inlineMeta;
  final double bottomPadding;

  const _AudioView({
    required this.attachment,
    required this.out,
    required this.palette,
    required this.metaColor,
    required this.inlineMeta,
    required this.bottomPadding,
  });

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final isVoice = attachment.type == 'VOICE';
    final dur = _formatAttachmentDuration(attachment.durationMs, isAudio: true);
    final label = isVoice
        ? (dur.isNotEmpty ? dur : 'Голосовое')
        : (attachment.fileName ?? (dur.isNotEmpty ? dur : 'Аудио'));
    final fg = out ? p.bubbleOutText : p.bubbleInText;
    final barColor = out
        ? Colors.white.withValues(alpha: 0.72)
        : p.accent.withValues(alpha: 0.72);
    final seed = (attachment.url ?? attachment.fileName ?? 'audio').hashCode;
    final meta = inlineMeta;

    return Padding(
      padding: EdgeInsets.fromLTRB(12, 10, 12, bottomPadding > 0 ? bottomPadding : 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: out ? Colors.white.withValues(alpha: 0.2) : p.accent,
              shape: BoxShape.circle,
            ),
            child: const Padding(
              padding: EdgeInsets.only(left: 2),
              child: TalerIcon(TalerIcons.play, size: 17, color: Colors.white),
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (var i = 0; i < 18; i++) ...[
                    if (i > 0) const SizedBox(width: 2.5),
                    Container(
                      width: 2.5,
                      height: 5.0 + (((seed ^ (i * 31)) & 0x7) * 2.1),
                      decoration: BoxDecoration(
                        color: barColor,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 5),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: TalerTheme.tabularStyle(
                      size: 12,
                      color: out ? fg.withValues(alpha: 0.88) : metaColor,
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
        ],
      ),
    );
  }
}

class _SharePreviewView extends StatelessWidget {
  final TalerAttachment attachment;
  final bool out;
  final TalerPalette palette;
  final Color fg;
  final double width;
  final double topMargin;
  final MessageMeta? trailingMeta;

  const _SharePreviewView({
    required this.attachment,
    required this.out,
    required this.palette,
    required this.fg,
    required this.width,
    required this.topMargin,
    this.trailingMeta,
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

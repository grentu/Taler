import 'dart:io';

import 'package:material_ui/material_ui.dart';

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
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: p.surface.withValues(alpha: 0.88),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            label,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: p.fg2),
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
  final VoidCallback onActions;
  final VoidCallback? onShowHistory;
  final VoidCallback? onRetry;
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
    required this.onActions,
    required this.onToggleReaction,
    this.peerReadMark,
    this.senderAvatarUrl,
    this.onShowHistory,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final p = TalerTheme.paletteOf(context);
    if (message.isControl) {
      return ChatDayChip(label: message.text.isNotEmpty ? message.text : 'Служебное сообщение');
    }
    final bubble = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: message.status == 'error' ? onActions : null,
      onLongPress: onActions,
      onSecondaryTap: onActions,
      child: MessageBubble(
        message: message,
        isMine: isMine,
        firstInRun: firstInRun,
        showName: showSender && firstInRun,
        senderName: senderName,
        maxWidth: maxBubbleWidth,
        peerReadMark: peerReadMark,
        onShowHistory: onShowHistory,
        onRetry: onRetry,
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
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 24,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: mine ? ChatTokens.accentSoft(p) : p.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: mine ? p.accent.withValues(alpha: 0.45) : p.line),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(reaction.emoji, style: const TextStyle(fontSize: 13)),
            const SizedBox(width: 4),
            Text(
              '${reaction.count}',
              style: TalerTheme.tabularStyle(
                size: 12,
                weight: FontWeight.w500,
                color: mine ? p.accent : p.fg2,
              ),
            ),
          ],
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
  final VoidCallback? onShowHistory;
  final VoidCallback? onRetry;

  const MessageBubble({
    super.key,
    required this.message,
    required this.isMine,
    required this.firstInRun,
    required this.showName,
    required this.senderName,
    required this.maxWidth,
    this.peerReadMark,
    this.onShowHistory,
    this.onRetry,
  });

  static const double _big = 18;
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
    final radius = isMine
        ? BorderRadius.only(
            topLeft: const Radius.circular(_big),
            topRight: Radius.circular(firstInRun ? _big : _small),
            bottomRight: const Radius.circular(_small),
            bottomLeft: const Radius.circular(_big),
          )
        : BorderRadius.only(
            topLeft: Radius.circular(firstInRun ? _big : _small),
            topRight: const Radius.circular(_big),
            bottomRight: const Radius.circular(_big),
            bottomLeft: const Radius.circular(_small),
          );
    final deleted = m.deletedByPeer;
    final out = isMine && !deleted;
    final failed = isMine && m.status == 'error';
    final bg = out ? p.bubbleOut : p.bubbleIn;
    final fg = out ? p.bubbleOutText : p.bubbleInText;
    final metaColor = out ? p.bubbleOutText.withValues(alpha: 0.72) : p.fg3;

    final photos = m.attachments.where((a) => a.type == 'PHOTO' && a.url != null).toList();
    final files = m.attachments.where((a) => a.type != 'PHOTO' && a.type != 'CONTROL').toList();
    final hasText = m.text.trim().isNotEmpty;

    final meta = MessageMeta(
      time: m.time,
      color: metaColor,
      edited: m.isEdited,
      deleted: deleted,
      status: _resolvedStatus(m),
      onTapEdited: onShowHistory,
      onTapRetry: failed ? onRetry : null,
    );

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
      children.add(_PhotoView(
        attachment: photo,
        width: maxWidth,
        overlayMeta: !hasText && files.isEmpty && photo == photos.last ? meta : null,
      ));
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
    for (final file in files) {
      final isLast = file == files.last;
      children.add(_FileView(
        attachment: file,
        out: out,
        palette: p,
        metaColor: metaColor,
        inlineMeta: !hasText && isLast ? meta : null,
        bottomPadding: !hasText && isLast ? 8 : 0,
      ));
    }
    if (hasText) {
      final topPad = (showName || reply != null || files.isNotEmpty || photos.isNotEmpty || forwarded != null) ? 4.0 : 7.0;
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
              style: TextStyle(fontSize: 15, height: 21 / 15, color: fg),
            ),
          ),
          Positioned(right: 10, bottom: 5, child: meta),
        ],
      ));
    } else if (photos.isEmpty && files.isEmpty) {
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
    final isHttp = url.startsWith('http://') || url.startsWith('https://');
    final placeholder = Container(color: p.bg3);
    final image = isHttp
        ? Image.network(url, fit: BoxFit.cover, errorBuilder: (_, _, _) => placeholder)
        : Image.file(File(url), fit: BoxFit.cover, errorBuilder: (_, _, _) => placeholder);
    final meta = overlayMeta;
    return SizedBox(
      width: width.clamp(160.0, 360.0),
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

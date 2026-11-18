import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

import '../../core/storage/taler_models.dart';
import '../icons/taler_icon.dart';
import '../theme/taler_theme.dart';
import 'message_bubble.dart';

/// Пункт стеклянного контекстного меню сообщения.
class TalerMessageAction {
  final TalerIconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;
  final bool destructive;

  const TalerMessageAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
    this.destructive = false,
  });
}

/// Показывает стеклянное меню сообщения поверх размытого чата в стиле Telegram / exteraGram:
/// сверху парящая капсула реакций, по центру подсвеченный пузырь сообщения,
/// снизу полупрозрачная стеклянная карточка действий.
Future<void> showTalerMessageActionsOverlay({
  required BuildContext context,
  required TalerMessage message,
  required bool isMine,
  required bool firstInRun,
  required bool showName,
  required String senderName,
  required double maxBubbleWidth,
  required double fontSize,
  required double cornerRadius,
  required List<TalerMessageAction> actions,
  required ValueChanged<String> onToggleReaction,
  int? peerReadMark,
  VoidCallback? onShowHistory,
  VoidCallback? onRetry,
  Rect? anchorRect,
  bool powerSaving = false,
}) {
  const quickEmojis = ['👍', '❤️', '🔥', '😂', '😮', '🙏', '🎉', '👏'];
  final myReactions = <String>{
    for (final r in message.reactions)
      if (r.isMine) r.emoji,
  };

  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Действия с сообщением',
    barrierColor: Colors.transparent,
    transitionDuration: Duration(milliseconds: powerSaving ? 140 : 220),
    pageBuilder: (dialogCtx, _, _) => const SizedBox.shrink(),
    transitionBuilder: (dialogCtx, anim, _, _) {
      final p = TalerTheme.paletteOf(dialogCtx);
      final curve = CurvedAnimation(
        parent: anim,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      final t = curve.value;
      final pad = MediaQuery.paddingOf(dialogCtx);
      final safePad = EdgeInsets.fromLTRB(
        math.max(12.0, pad.left + 8.0),
        math.max(12.0, pad.top + 8.0),
        math.max(12.0, pad.right + 8.0),
        math.max(12.0, pad.bottom + 8.0),
      );
      final screenSize = MediaQuery.sizeOf(dialogCtx);
      final availW = math.max(160.0, screenSize.width - safePad.horizontal);
      final availH = math.max(200.0, screenSize.height - safePad.vertical);
      final menuWidth = math.min(256.0, availW);
      final barMaxWidth = math.min(336.0, availW);
      final bubblePreviewMaxH = (availH * 0.30).clamp(84.0, 240.0);

      final backdropColor = (p.isDark ? Colors.black : const Color(0xFF0A0B0E))
          .withValues(alpha: (powerSaving ? 0.68 : (p.isDark ? 0.56 : 0.34)) * t);

      final normalActions = actions.where((a) => !a.destructive).toList();
      final destructiveActions = actions.where((a) => a.destructive).toList();

      Widget buildBackdropLayer() {
        final shade = ColoredBox(color: backdropColor);
        if (powerSaving || t <= 0.01) return shade;
        final sigma = 18.0 * t;
        return BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
          child: shade,
        );
      }

      Widget buildColumn() {
        return SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment:
                isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              // 1. Парящая капсула реакций
              Transform.translate(
                offset: Offset(0, 6 * (1 - t)),
                child: Transform.scale(
                  scale: 0.90 + 0.10 * t,
                  alignment:
                      isMine ? Alignment.bottomRight : Alignment.bottomLeft,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: barMaxWidth),
                    child: _GlassSurface(
                      palette: p,
                      radius: 999,
                      powerSaving: powerSaving,
                      child: SizedBox(
                        height: 50,
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              for (final emoji in quickEmojis)
                                _ReactionButton(
                                  emoji: emoji,
                                  selected: myReactions.contains(emoji),
                                  accent: p.accent,
                                  onTap: () {
                                    Navigator.of(dialogCtx).pop();
                                    onToggleReaction(emoji);
                                  },
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),

              // 2. Само сообщение в фокусе (приподнято над блюром)
              Container(
                decoration: BoxDecoration(
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.38 * t),
                      blurRadius: 28,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: bubblePreviewMaxH,
                    maxWidth: math.min(maxBubbleWidth, availW),
                  ),
                  child: SingleChildScrollView(
                    physics: const ClampingScrollPhysics(),
                    child: MessageBubble(
                      message: message,
                      isMine: isMine,
                      firstInRun: firstInRun,
                      showName: showName,
                      senderName: senderName,
                      maxWidth: math.min(maxBubbleWidth, availW),
                      peerReadMark: peerReadMark,
                      fontSize: fontSize,
                      cornerRadius: cornerRadius,
                      onShowHistory: onShowHistory == null
                          ? null
                          : () {
                              Navigator.of(dialogCtx).pop();
                              onShowHistory();
                            },
                      onRetry: onRetry == null
                          ? null
                          : () {
                              Navigator.of(dialogCtx).pop();
                              onRetry();
                            },
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),

              // 3. Парящее стеклянное меню действий
              Transform.translate(
                offset: Offset(0, -6 * (1 - t)),
                child: Transform.scale(
                  scale: 0.90 + 0.10 * t,
                  alignment: isMine ? Alignment.topRight : Alignment.topLeft,
                  child: SizedBox(
                    width: menuWidth,
                    child: _GlassSurface(
                      palette: p,
                      radius: 18,
                      powerSaving: powerSaving,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (var i = 0; i < normalActions.length; i++) ...[
                            _ActionRow(
                              action: normalActions[i],
                              palette: p,
                              onClose: () => Navigator.of(dialogCtx).pop(),
                            ),
                            if (i + 1 < normalActions.length)
                              Divider(
                                height: 1,
                                thickness: 0.5,
                                color: p.line,
                              ),
                          ],
                          if (normalActions.isNotEmpty &&
                              destructiveActions.isNotEmpty)
                            Container(
                              height: 4,
                              color: p.isDark
                                  ? Colors.black.withValues(alpha: 0.35)
                                  : Colors.black.withValues(alpha: 0.06),
                            ),
                          for (var i = 0; i < destructiveActions.length; i++) ...[
                            _ActionRow(
                              action: destructiveActions[i],
                              palette: p,
                              onClose: () => Navigator.of(dialogCtx).pop(),
                            ),
                            if (i + 1 < destructiveActions.length)
                              Divider(
                                height: 1,
                                thickness: 0.5,
                                color: p.line,
                              ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      }

      return Material(
        type: MaterialType.transparency,
        child: FadeTransition(
          opacity: curve,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => Navigator.of(dialogCtx).pop(),
                  child: buildBackdropLayer(),
                ),
              ),
              Padding(
                padding: safePad,
                child: CustomSingleChildLayout(
                  delegate: _AnchoredOverlayLayoutDelegate(
                    anchorRect: anchorRect,
                    safeTop: safePad.top,
                    alignRight: isMine,
                    bubbleTopOffset: 58.0,
                  ),
                  child: buildColumn(),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _AnchoredOverlayLayoutDelegate extends SingleChildLayoutDelegate {
  final Rect? anchorRect;
  final double safeTop;
  final bool alignRight;
  final double bubbleTopOffset;

  const _AnchoredOverlayLayoutDelegate({
    required this.anchorRect,
    required this.safeTop,
    required this.alignRight,
    required this.bubbleTopOffset,
  });

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    return BoxConstraints(
      maxWidth: constraints.maxWidth,
      maxHeight: constraints.maxHeight,
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final dx = alignRight
        ? math.max(0.0, size.width - childSize.width)
        : 0.0;
    final maxY = math.max(0.0, size.height - childSize.height);
    if (anchorRect != null) {
      final desiredTop = (anchorRect!.top - safeTop) - bubbleTopOffset;
      return Offset(dx, desiredTop.clamp(0.0, maxY));
    }
    return Offset(dx, ((size.height - childSize.height) * 0.5).clamp(0.0, maxY));
  }

  @override
  bool shouldRelayout(covariant _AnchoredOverlayLayoutDelegate old) =>
      old.anchorRect != anchorRect ||
      old.safeTop != safeTop ||
      old.alignRight != alignRight ||
      old.bubbleTopOffset != bubbleTopOffset;
}

class _GlassSurface extends StatelessWidget {
  final TalerPalette palette;
  final double radius;
  final bool powerSaving;
  final Widget child;

  const _GlassSurface({
    required this.palette,
    required this.radius,
    required this.powerSaving,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = palette.isDark;
    final fillColor = isDark
        ? (powerSaving ? const Color(0xF51A1B20) : const Color(0xD91A1B20))
        : (powerSaving ? const Color(0xF7FFFFFF) : const Color(0xEBFFFFFF));
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.14)
        : Colors.black.withValues(alpha: 0.08);

    final decorated = Container(
      decoration: BoxDecoration(
        color: fillColor,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: borderColor, width: 0.9),
      ),
      child: child,
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.55 : 0.18),
            blurRadius: 26,
            offset: const Offset(0, 10),
            spreadRadius: -4,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: powerSaving
            ? decorated
            : BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                child: decorated,
              ),
      ),
    );
  }
}

class _ReactionButton extends StatelessWidget {
  final String emoji;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  const _ReactionButton({
    required this.emoji,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        splashFactory: NoSplash.splashFactory,
        child: Container(
          width: 38,
          height: 38,
          margin: const EdgeInsets.symmetric(horizontal: 1),
          alignment: Alignment.center,
          decoration: selected
              ? BoxDecoration(
                  color: accent.withValues(alpha: 0.24),
                  shape: BoxShape.circle,
                  border: Border.all(color: accent.withValues(alpha: 0.55)),
                )
              : null,
          child: Text(emoji, style: const TextStyle(fontSize: 21)),
        ),
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  final TalerMessageAction action;
  final TalerPalette palette;
  final VoidCallback onClose;

  const _ActionRow({
    required this.action,
    required this.palette,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final fg = action.color ??
        (action.destructive ? palette.danger : palette.fg);
    final iconColor = action.color ??
        (action.destructive ? palette.danger : palette.fg2);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          onClose();
          action.onTap();
        },
        splashFactory: NoSplash.splashFactory,
        highlightColor: palette.surface2.withValues(alpha: 0.55),
        child: SizedBox(
          height: 46,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    action.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w400,
                      color: fg,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                TalerIcon(action.icon, size: 19, color: iconColor),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

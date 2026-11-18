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
/// пузырь остаётся точно на своём месте без прыжков, а капсула реакций и меню действий
/// автоматически размещаются сверху или снизу в зависимости от свободного места.
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
      final screenSize = MediaQuery.sizeOf(dialogCtx);
      final safeLeft = math.max(12.0, pad.left + 8.0);
      final safeRight = screenSize.width - math.max(12.0, pad.right + 8.0);
      final safeTop = math.max(12.0, pad.top + 8.0);
      final safeBottom = screenSize.height - math.max(12.0, pad.bottom + 8.0);
      final availW = math.max(160.0, safeRight - safeLeft);
      final availH = math.max(200.0, safeBottom - safeTop);

      const barH = 50.0;
      const gap = 8.0;
      final menuWidth = math.min(256.0, availW);
      final barWidth = math.min(332.0, availW);
      final bubbleMaxW = math.min(maxBubbleWidth, availW);

      final normalActions = actions.where((a) => !a.destructive).toList();
      final destructiveActions = actions.where((a) => a.destructive).toList();
      final rawMenuH = normalActions.length * 46.0 +
          math.max(0, normalActions.length - 1) * 1.0 +
          (normalActions.isNotEmpty && destructiveActions.isNotEmpty ? 4.0 : 0.0) +
          destructiveActions.length * 46.0 +
          math.max(0, destructiveActions.length - 1) * 1.0 +
          2.0;
      final menuMaxH = math.max(96.0, availH - barH - gap * 2 - 84.0);
      final menuH = math.min(rawMenuH, menuMaxH);

      final layout = _computeOverlayPlacement(
        anchorRect: anchorRect,
        isMine: isMine,
        screenSize: screenSize,
        safeLeft: safeLeft,
        safeRight: safeRight,
        safeTop: safeTop,
        safeBottom: safeBottom,
        availH: availH,
        barW: barWidth,
        barH: barH,
        menuW: menuWidth,
        menuH: menuH,
        gap: gap,
        t: t,
      );

      final backdropColor = (p.isDark ? Colors.black : const Color(0xFF0A0B0E))
          .withValues(alpha: (powerSaving ? 0.68 : (p.isDark ? 0.56 : 0.34)) * t);

      Widget buildBackdropLayer() {
        final shade = ColoredBox(color: backdropColor);
        if (powerSaving || t <= 0.01) return shade;
        final sigma = 18.0 * t;
        return BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
          child: shade,
        );
      }

      final reactionsWidget = Opacity(
        opacity: t.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset(0, layout.barSlideDy * (1 - t)),
          child: Transform.scale(
            scale: 0.90 + 0.10 * t,
            alignment: layout.barScaleAlignment,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: barWidth),
              child: _GlassSurface(
                palette: p,
                radius: 999,
                powerSaving: powerSaving,
                child: SizedBox(
                  height: barH,
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
      );

      final bubbleContent = Container(
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
            maxHeight: layout.bubbleMaxH,
            maxWidth: bubbleMaxW,
          ),
          child: SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            child: MessageBubble(
              message: message,
              isMine: isMine,
              firstInRun: firstInRun,
              showName: showName,
              senderName: senderName,
              maxWidth: bubbleMaxW,
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
      );

      final menuWidget = Opacity(
        opacity: t.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset(0, layout.menuSlideDy * (1 - t)),
          child: Transform.scale(
            scale: 0.90 + 0.10 * t,
            alignment: layout.menuScaleAlignment,
            child: SizedBox(
              width: menuWidth,
              child: _GlassSurface(
                palette: p,
                radius: 18,
                powerSaving: powerSaving,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: menuMaxH),
                  child: SingleChildScrollView(
                    physics: const ClampingScrollPhysics(),
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
          ),
        ),
      );

      return Material(
        type: MaterialType.transparency,
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
            Positioned(
              left: layout.bubbleLeft,
              right: layout.bubbleRight,
              top: layout.bubbleTop,
              child: bubbleContent,
            ),
            Positioned(
              left: layout.barLeft,
              top: layout.barTop,
              child: reactionsWidget,
            ),
            Positioned(
              left: layout.menuLeft,
              top: layout.menuTop,
              child: menuWidget,
            ),
          ],
        ),
      );
    },
  );
}

class _OverlayPlacement {
  final double? bubbleLeft;
  final double? bubbleRight;
  final double bubbleTop;
  final double bubbleMaxH;
  final double barLeft;
  final double barTop;
  final double barSlideDy;
  final Alignment barScaleAlignment;
  final double menuLeft;
  final double menuTop;
  final double menuSlideDy;
  final Alignment menuScaleAlignment;

  const _OverlayPlacement({
    required this.bubbleLeft,
    required this.bubbleRight,
    required this.bubbleTop,
    required this.bubbleMaxH,
    required this.barLeft,
    required this.barTop,
    required this.barSlideDy,
    required this.barScaleAlignment,
    required this.menuLeft,
    required this.menuTop,
    required this.menuSlideDy,
    required this.menuScaleAlignment,
  });
}

_OverlayPlacement _computeOverlayPlacement({
  required Rect? anchorRect,
  required bool isMine,
  required Size screenSize,
  required double safeLeft,
  required double safeRight,
  required double safeTop,
  required double safeBottom,
  required double availH,
  required double barW,
  required double barH,
  required double menuW,
  required double menuH,
  required double gap,
  required double t,
}) {
  final maxBubbleFitH = math.max(84.0, availH - barH - menuH - gap * 2);

  // Горизонтальная привязка пузыря ровно к его реальным координатам.
  final double? bubbleLeft;
  final double? bubbleRight;
  final double alignEdgeX;
  if (anchorRect != null) {
    if (isMine) {
      bubbleLeft = null;
      bubbleRight = (screenSize.width - anchorRect.right)
          .clamp(0.0, math.max(0.0, screenSize.width - 48.0));
      alignEdgeX = anchorRect.right;
    } else {
      bubbleLeft = anchorRect.left
          .clamp(0.0, math.max(0.0, screenSize.width - 48.0));
      bubbleRight = null;
      alignEdgeX = anchorRect.left;
    }
  } else {
    if (isMine) {
      bubbleLeft = null;
      bubbleRight = screenSize.width - safeRight;
      alignEdgeX = safeRight;
    } else {
      bubbleLeft = safeLeft;
      bubbleRight = null;
      alignEdgeX = safeLeft;
    }
  }

  final double barLeft = (isMine
          ? (alignEdgeX - barW).clamp(safeLeft, math.max(safeLeft, safeRight - barW))
          : alignEdgeX.clamp(safeLeft, math.max(safeLeft, safeRight - barW)))
      .toDouble();
  final double menuLeft = (isMine
          ? (alignEdgeX - menuW).clamp(safeLeft, math.max(safeLeft, safeRight - menuW))
          : alignEdgeX.clamp(safeLeft, math.max(safeLeft, safeRight - menuW)))
      .toDouble();

  final double rawTop;
  final double rawHeight;
  if (anchorRect != null) {
    rawTop = anchorRect.top;
    rawHeight = anchorRect.height;
  } else {
    rawHeight = math.min(96.0, maxBubbleFitH);
    rawTop = (safeTop + (availH - rawHeight) * 0.42)
        .clamp(safeTop + barH + gap, math.max(safeTop + barH + gap, safeBottom - rawHeight - menuH - gap));
  }

  final bubbleH = math.min(rawHeight, maxBubbleFitH);
  final bubbleMaxH = math.max(bubbleH, math.min(rawHeight, maxBubbleFitH));
  final bubbleBottom = rawTop + bubbleH;
  final spaceAbove = rawTop - safeTop;
  final spaceBelow = safeBottom - bubbleBottom;

  double targetBubbleTop = rawTop;
  double barTop;
  double menuTop;
  double barSlideDy;
  double menuSlideDy;
  Alignment barAlign;
  Alignment menuAlign;

  if (spaceAbove >= barH + gap && spaceBelow >= menuH + gap) {
    // Стандартно: реакции над сообщением, меню под сообщением, пузырь не двигается.
    barTop = rawTop - gap - barH;
    menuTop = rawTop + bubbleH + gap;
    barSlideDy = 6.0;
    menuSlideDy = -6.0;
    barAlign = isMine ? Alignment.bottomRight : Alignment.bottomLeft;
    menuAlign = isMine ? Alignment.topRight : Alignment.topLeft;
  } else if (spaceBelow < menuH + gap &&
      spaceBelow >= barH + gap &&
      spaceAbove >= menuH + gap) {
    // Нижняя часть экрана: меню сверху, реакции снизу — сообщение остаётся на месте!
    menuTop = rawTop - gap - menuH;
    barTop = rawTop + bubbleH + gap;
    barSlideDy = -6.0;
    menuSlideDy = 6.0;
    barAlign = isMine ? Alignment.topRight : Alignment.topLeft;
    menuAlign = isMine ? Alignment.bottomRight : Alignment.bottomLeft;
  } else if (spaceBelow < menuH + gap &&
      spaceAbove >= menuH + gap + barH + gap) {
    // Самый низ экрана (у поля ввода): меню и реакции над сообщением — пузырь на месте!
    menuTop = rawTop - gap - menuH;
    barTop = menuTop - gap - barH;
    barSlideDy = 8.0;
    menuSlideDy = 6.0;
    barAlign = isMine ? Alignment.bottomRight : Alignment.bottomLeft;
    menuAlign = isMine ? Alignment.bottomRight : Alignment.bottomLeft;
  } else if (spaceAbove < barH + gap &&
      spaceBelow >= barH + gap + menuH + gap) {
    // Самый верх экрана (у шапки): реакции и меню под сообщением — пузырь на месте!
    barTop = rawTop + bubbleH + gap;
    menuTop = barTop + barH + gap;
    barSlideDy = -6.0;
    menuSlideDy = -8.0;
    barAlign = isMine ? Alignment.topRight : Alignment.topLeft;
    menuAlign = isMine ? Alignment.topRight : Alignment.topLeft;
  } else {
    // Сверхвысокое или частично скрытое за краем экрана сообщение:
    // плавно подтягиваем на минимальное расстояние, чтобы всё поместилось.
    final preferAbove = (rawTop + bubbleH * 0.5) > (safeTop + availH * 0.5);
    if (preferAbove) {
      final minTop = safeTop + barH + gap + menuH + gap;
      final maxTop = math.max(minTop, safeBottom - bubbleH);
      targetBubbleTop = rawTop.clamp(minTop, maxTop);
      menuTop = targetBubbleTop - gap - menuH;
      barTop = menuTop - gap - barH;
      barSlideDy = 8.0;
      menuSlideDy = 6.0;
      barAlign = isMine ? Alignment.bottomRight : Alignment.bottomLeft;
      menuAlign = isMine ? Alignment.bottomRight : Alignment.bottomLeft;
    } else {
      final minTop = safeTop;
      final maxTop = math.max(minTop, safeBottom - bubbleH - barH - gap - menuH - gap);
      targetBubbleTop = rawTop.clamp(minTop, maxTop);
      barTop = targetBubbleTop + bubbleH + gap;
      menuTop = barTop + barH + gap;
      barSlideDy = -6.0;
      menuSlideDy = -8.0;
      barAlign = isMine ? Alignment.topRight : Alignment.topLeft;
      menuAlign = isMine ? Alignment.topRight : Alignment.topLeft;
    }
  }

  final currentBubbleTop = ui.lerpDouble(rawTop, targetBubbleTop, t)!;

  return _OverlayPlacement(
    bubbleLeft: bubbleLeft,
    bubbleRight: bubbleRight,
    bubbleTop: currentBubbleTop,
    bubbleMaxH: bubbleMaxH,
    barLeft: barLeft,
    barTop: barTop.clamp(safeTop, math.max(safeTop, safeBottom - barH)).toDouble(),
    barSlideDy: barSlideDy,
    barScaleAlignment: barAlign,
    menuLeft: menuLeft,
    menuTop: menuTop.clamp(safeTop, math.max(safeTop, safeBottom - menuH)).toDouble(),
    menuSlideDy: menuSlideDy,
    menuScaleAlignment: menuAlign,
  );
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
                  color: accent.withValues(alpha: 0.28),
                  shape: BoxShape.circle,
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

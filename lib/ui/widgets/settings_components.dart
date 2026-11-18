import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

import '../icons/taler_icon.dart';
import '../theme/taler_theme.dart';

/// Подложка-сквиркл 28×28 (`borderRadius: 10`) с внутренним стеклянным бликом,
/// повторяющая `SettingCell.Background` из `exteraless` в чёрном монохромном стиле.
class TalerSettingsBadge extends StatelessWidget {
  final TalerIconData icon;
  final Color? color;
  final Color? iconColor;
  final double size;
  final double iconSize;

  const TalerSettingsBadge({
    super.key,
    required this.icon,
    this.color,
    this.iconColor,
    this.size = 28,
    this.iconSize = 22,
  });

  @override
  Widget build(BuildContext context) {
    final p = TalerTheme.paletteOf(context);
    final topColor = color ??
        (p.isDark ? const Color(0xFF25262C) : const Color(0xFF2B2D35));
    final bottomColor = color ??
        (p.isDark ? const Color(0xFF17181C) : const Color(0xFF1D1F26));

    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _SquircleGlarePainter(
          topColor: topColor,
          bottomColor: bottomColor,
          drawGlare: p.isDark,
        ),
        child: Center(
          child: TalerIcon(
            icon,
            size: iconSize,
            color: iconColor ?? Colors.white,
          ),
        ),
      ),
    );
  }
}

class _SquircleGlarePainter extends CustomPainter {
  final Color topColor;
  final Color bottomColor;
  final bool drawGlare;

  const _SquircleGlarePainter({
    required this.topColor,
    required this.bottomColor,
    required this.drawGlare,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final radius = Radius.circular((size.width / 28.0) * 10.0);
    final rrect = RRect.fromRectAndRadius(rect, radius);

    final fillPaint = Paint()
      ..isAntiAlias = true
      ..shader = ui.Gradient.linear(
        Offset.zero,
        Offset(0, size.height),
        [topColor, bottomColor],
      );
    canvas.drawRRect(rrect, fillPaint);

    if (drawGlare) {
      // Фирменная блик-обводка из exteraless (SettingCell.Background / GlassOutlineStyle.GLARE).
      const strokeWidth = 1.0;
      final strokeRect = rect.deflate(strokeWidth / 2.0);
      final strokeRRect = RRect.fromRectAndRadius(
        strokeRect,
        Radius.circular((radius.x - strokeWidth / 2.0).clamp(0.0, 20.0)),
      );
      final strokePaint = Paint()
        ..isAntiAlias = true
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..shader = ui.Gradient.linear(
          Offset.zero,
          Offset(0, size.height),
          const [
            Color(0x4DFFFFFF),
            Color(0x00FFFFFF),
            Color(0x1AFFFFFF),
          ],
          const [0.0, 0.5, 1.0],
        );
      canvas.drawRRect(strokeRRect, strokePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _SquircleGlarePainter old) =>
      old.topColor != topColor ||
      old.bottomColor != bottomColor ||
      old.drawGlare != drawGlare;
}

/// Прогрессивный верхний эффект кромки с размытием и затуханием,
/// как `actionBarFadeView` / `GlassFadeBlurredDrawable` в `exteraless`.
class TalerTopFadeOverlay extends StatelessWidget {
  final double height;
  final double factor;
  final bool powerSaving;
  final Color backgroundColor;

  const TalerTopFadeOverlay({
    super.key,
    required this.height,
    required this.backgroundColor,
    this.factor = 1.0,
    this.powerSaving = false,
  });

  @override
  Widget build(BuildContext context) {
    final clamped = factor.clamp(0.0, 1.0);
    if (clamped <= 0.01) return const SizedBox.shrink();

    final scrim = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            backgroundColor.withValues(alpha: (powerSaving ? 0.96 : 0.88) * clamped),
            backgroundColor.withValues(alpha: (powerSaving ? 0.84 : 0.62) * clamped),
            backgroundColor.withValues(alpha: 0.0),
          ],
          stops: const [0.0, 0.58, 1.0],
        ),
      ),
    );

    return IgnorePointer(
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: powerSaving
            ? scrim
            : Stack(
                fit: StackFit.expand,
                children: [
                  Opacity(
                    opacity: clamped,
                    child: ShaderMask(
                      blendMode: BlendMode.dstIn,
                      shaderCallback: (bounds) => const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.white, Colors.white, Colors.transparent],
                        stops: [0.0, 0.52, 1.0],
                      ).createShader(bounds),
                      child: ClipRect(
                        child: BackdropFilter(
                          filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                          child: const SizedBox.expand(),
                        ),
                      ),
                    ),
                  ),
                  scrim,
                ],
              ),
      ),
    );
  }
}

/// Нижний мягкий фейд кромки над доком (`createNavigationBarFadeDrawable`).
class TalerBottomFadeOverlay extends StatelessWidget {
  final double height;
  final Color backgroundColor;

  const TalerBottomFadeOverlay({
    super.key,
    required this.height,
    required this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [
                backgroundColor.withValues(alpha: 0.90),
                backgroundColor.withValues(alpha: 0.55),
                backgroundColor.withValues(alpha: 0.0),
              ],
              stops: const [0.0, 0.45, 1.0],
            ),
          ),
        ),
      ),
    );
  }
}

/// Чёрно-графитовая скруглённая секция настроек (стиль exteraGram / exteraless).
class TalerSettingsGroup extends StatelessWidget {
  final String? title;
  final bool accentTitle;
  final bool showDividers;
  final List<Widget> children;

  const TalerSettingsGroup({
    super.key,
    this.title,
    this.accentTitle = true,
    this.showDividers = false,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final p = TalerTheme.paletteOf(context);
    final cardColor = p.isDark ? const Color(0xFF121215) : p.surface;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (title != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 4, 18, 8),
            child: Text(
              title!,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: accentTitle ? p.accent : p.fg2,
              ),
            ),
          ),
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(18),
            border: p.isDark ? null : Border.all(color: p.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: showDividers ? _withDividers(children, p) : children,
          ),
        ),
      ],
    );
  }

  List<Widget> _withDividers(List<Widget> items, TalerPalette p) {
    if (items.length <= 1) return items;
    final out = <Widget>[];
    for (var i = 0; i < items.length; i++) {
      out.add(items[i]);
      if (i + 1 < items.length) {
        out.add(
          Divider(
            height: 1,
            thickness: 1,
            indent: 64,
            color: p.line,
          ),
        );
      }
    }
    return out;
  }
}

/// Строка настроек с точной геометрией `SettingCell` из `exteraless`:
/// 18px слева — 28×28 сквиркл — 18px — заголовок (16sp) — 20px справа.
class TalerSettingsTile extends StatelessWidget {
  final TalerIconData icon;
  final Color? badgeColor;
  final Color? iconColor;
  final String title;
  final String? subtitle;
  final String? valueText;
  final Color? titleColor;
  final Widget? trailing;
  final bool showChevron;
  final VoidCallback? onTap;

  const TalerSettingsTile({
    super.key,
    required this.icon,
    this.badgeColor,
    this.iconColor,
    required this.title,
    this.subtitle,
    this.valueText,
    this.titleColor,
    this.trailing,
    this.showChevron = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = TalerTheme.paletteOf(context);
    final hasSub = subtitle != null && subtitle!.isNotEmpty;
    final row = ConstrainedBox(
      constraints: BoxConstraints(minHeight: hasSub ? 60 : 50),
      child: Padding(
        padding: EdgeInsets.fromLTRB(18, hasSub ? 10 : 11, 20, hasSub ? 10 : 11),
        child: Row(
          children: [
            TalerSettingsBadge(
              icon: icon,
              color: badgeColor,
              iconColor: iconColor,
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w400,
                      color: titleColor ?? p.fg,
                    ),
                  ),
                  if (hasSub) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12.5, color: p.fg3),
                    ),
                  ],
                ],
              ),
            ),
            if (valueText != null && valueText!.isNotEmpty) ...[
              const SizedBox(width: 12),
              Text(
                valueText!,
                style: TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w400,
                  color: p.accent,
                ),
              ),
            ],
            if (trailing != null) ...[
              const SizedBox(width: 10),
              trailing!,
            ] else if (showChevron) ...[
              const SizedBox(width: 6),
              TalerIcon(TalerIcons.chevronRight, size: 15, color: p.fg3),
            ],
          ],
        ),
      ),
    );

    if (onTap == null) return row;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        splashFactory: NoSplash.splashFactory,
        highlightColor: p.surface2.withValues(alpha: 0.45),
        child: row,
      ),
    );
  }
}

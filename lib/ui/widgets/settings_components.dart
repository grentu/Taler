import 'package:material_ui/material_ui.dart';

import '../icons/taler_icon.dart';
import '../theme/taler_theme.dart';

/// Цветной круглый бейдж для пунктов настроек, в стиле Solar / exteraGram.
class TalerSettingsBadge extends StatelessWidget {
  final TalerIconData icon;
  final Color color;
  final double size;
  final bool roundedSquare;

  const TalerSettingsBadge({
    super.key,
    required this.icon,
    required this.color,
    this.size = 30,
    this.roundedSquare = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(roundedSquare ? 9 : size / 2),
      ),
      child: TalerIcon(
        icon,
        size: size * 0.56,
        color: Colors.white,
        strokeWidth: 1.9,
      ),
    );
  }
}

/// Групповая секция настроек: опциональный заголовок и скруглённая карточка.
class TalerSettingsGroup extends StatelessWidget {
  final String? title;
  final bool accentTitle;
  final List<Widget> children;

  const TalerSettingsGroup({
    super.key,
    this.title,
    this.accentTitle = true,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final p = TalerTheme.paletteOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (title != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
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
            color: p.surface,
            borderRadius: BorderRadius.circular(18),
            border: p.isDark ? null : Border.all(color: p.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: _withDividers(children, p),
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
            indent: 60,
            color: p.line,
          ),
        );
      }
    }
    return out;
  }
}

/// Строка настроек: цветной бейдж, заголовок, опциональный подзаголовок,
/// правое синее значение и стрелка или переключатель.
class TalerSettingsTile extends StatelessWidget {
  final TalerIconData icon;
  final Color badgeColor;
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
    required this.badgeColor,
    required this.title,
    this.subtitle,
    this.valueText,
    this.titleColor,
    this.trailing,
    this.showChevron = true,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = TalerTheme.paletteOf(context);
    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          TalerSettingsBadge(icon: icon, color: badgeColor),
          const SizedBox(width: 14),
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
                    fontSize: 15.5,
                    fontWeight: FontWeight.w500,
                    color: titleColor ?? p.fg,
                  ),
                ),
                if (subtitle != null && subtitle!.isNotEmpty) ...[
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
            const SizedBox(width: 10),
            Text(
              valueText!,
              style: TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w500,
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

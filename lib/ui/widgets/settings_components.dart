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
      mainAxisSize: MainAxisSize.min,
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
            mainAxisSize: MainAxisSize.min,
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

/// Определяет подходящую иконку устройства по строке клиента активной сессии.
TalerIconData talerDeviceIconForClient(String clientName) {
  final lower = clientName.toLowerCase();
  if (lower.contains('web') ||
      lower.contains('browser') ||
      lower.contains('chrome') ||
      lower.contains('safari') ||
      lower.contains('firefox') ||
      lower.contains('edge')) {
    return TalerIcons.settingsLanguage;
  }
  if (lower.contains('windows') ||
      lower.contains('desktop') ||
      lower.contains('macos') ||
      lower.contains('mac os') ||
      lower.contains('linux') ||
      lower.contains('darwin')) {
    return TalerIcons.settingsDevices;
  }
  if (lower.contains('android') ||
      lower.contains('ios') ||
      lower.contains('iphone') ||
      lower.contains('ipad') ||
      lower.contains('mobile') ||
      lower.contains('taler') ||
      lower.contains('max') ||
      lower.contains('pixel') ||
      lower.contains('samsung') ||
      lower.contains('xiaomi') ||
      lower.contains('redmi') ||
      lower.contains('poco')) {
    return TalerIcons.smartphone;
  }
  return TalerIcons.devicesOther;
}

Widget _sheetHandle(TalerPalette p) => Center(
      child: Container(
        width: 36,
        height: 4,
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
          color: p.fg.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );

/// Чёрный лист редактирования имени и фамилии в стиле `exteraless`.
Future<void> showTalerEditNameSheet(
  BuildContext context, {
  required String initialFirstName,
  String? initialLastName,
  required Future<void> Function(String firstName, String? lastName) onSave,
}) async {
  final result = await showModalBottomSheet<({String first, String? last})>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _EditNameSheetBody(
      initialFirstName: initialFirstName,
      initialLastName: initialLastName,
    ),
  );

  if (result != null && result.first.isNotEmpty) {
    await onSave(result.first, result.last);
  }
}

class _EditNameSheetBody extends StatefulWidget {
  final String initialFirstName;
  final String? initialLastName;

  const _EditNameSheetBody({
    required this.initialFirstName,
    this.initialLastName,
  });

  @override
  State<_EditNameSheetBody> createState() => _EditNameSheetBodyState();
}

class _EditNameSheetBodyState extends State<_EditNameSheetBody> {
  late final TextEditingController _firstCtrl;
  late final TextEditingController _lastCtrl;

  @override
  void initState() {
    super.initState();
    _firstCtrl = TextEditingController(text: widget.initialFirstName);
    _lastCtrl = TextEditingController(text: widget.initialLastName ?? '');
  }

  @override
  void dispose() {
    _firstCtrl.dispose();
    _lastCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final first = _firstCtrl.text.trim();
    if (first.isEmpty) return;
    final last = _lastCtrl.text.trim();
    Navigator.of(context).pop((
      first: first,
      last: last.isEmpty ? null : last,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final p = TalerTheme.paletteOf(context);
    final bottom =
        MediaQuery.viewInsetsOf(context).bottom + MediaQuery.paddingOf(context).bottom;
    return Container(
      decoration: BoxDecoration(
        color: p.settingsBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        border: Border(top: BorderSide(color: p.line2)),
      ),
      padding: EdgeInsets.fromLTRB(16, 12, 16, bottom + 16),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _sheetHandle(p),
            Row(
              children: [
                const TalerSettingsBadge(
                  icon: TalerIcons.pencil,
                  size: 32,
                  iconSize: 19,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Изменить имя',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: p.fg,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TalerSettingsGroup(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: TextField(
                    controller: _firstCtrl,
                    autofocus: true,
                    textInputAction: TextInputAction.next,
                    textCapitalization: TextCapitalization.words,
                    style: TextStyle(fontSize: 16, color: p.fg),
                    decoration: InputDecoration(
                      labelText: 'Имя',
                      labelStyle: TextStyle(fontSize: 13, color: p.fg3),
                      filled: false,
                      contentPadding: const EdgeInsets.symmetric(vertical: 8),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: TextField(
                    controller: _lastCtrl,
                    textInputAction: TextInputAction.done,
                    textCapitalization: TextCapitalization.words,
                    onSubmitted: (_) => _submit(),
                    style: TextStyle(fontSize: 16, color: p.fg),
                    decoration: InputDecoration(
                      labelText: 'Фамилия (необязательно)',
                      labelStyle: TextStyle(fontSize: 13, color: p.fg3),
                      filled: false,
                      contentPadding: const EdgeInsets.symmetric(vertical: 8),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 46,
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: p.line2),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text('Отмена'),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SizedBox(
                    height: 46,
                    child: FilledButton(
                      onPressed: _submit,
                      style: FilledButton.styleFrom(
                        backgroundColor: p.accent,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text('Сохранить'),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Информационный чёрный лист в стиле `exteraless` (для справки, политики, вопросов и т.д.).
Future<void> showTalerInfoSheet(
  BuildContext context, {
  required TalerIconData icon,
  required String title,
  required String body,
  String? copyText,
  String? copyButtonLabel,
  ValueChanged<String>? onCopied,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      final p = TalerTheme.paletteOf(ctx);
      final bottom = MediaQuery.paddingOf(ctx).bottom;
      return Container(
        decoration: BoxDecoration(
          color: p.settingsBg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
          border: Border(top: BorderSide(color: p.line2)),
        ),
        padding: EdgeInsets.fromLTRB(16, 12, 16, bottom + 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _sheetHandle(p),
            Row(
              children: [
                TalerSettingsBadge(icon: icon, size: 34, iconSize: 21),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: p.fg,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            TalerSettingsGroup(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                  child: SelectableText(
                    body,
                    style: TextStyle(
                      fontSize: 14.5,
                      height: 1.48,
                      color: p.fg2,
                    ),
                  ),
                ),
              ],
            ),
            if (copyText != null && copyButtonLabel != null) ...[
              const SizedBox(height: 12),
              TalerSettingsGroup(
                children: [
                  TalerSettingsTile(
                    icon: TalerIcons.copy,
                    title: copyButtonLabel,
                    subtitle: copyText,
                    onTap: () {
                      Navigator.of(ctx).pop();
                      onCopied?.call(copyText);
                    },
                  ),
                ],
              ),
            ],
            const SizedBox(height: 14),
            SizedBox(
              height: 46,
              child: FilledButton(
                onPressed: () => Navigator.of(ctx).pop(),
                style: FilledButton.styleFrom(
                  backgroundColor: p.accent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text('Понятно'),
              ),
            ),
          ],
        ),
      );
    },
  );
}

/// Чёрный лист подтверждения опасного или важного действия.
Future<bool> showTalerConfirmSheet(
  BuildContext context, {
  required TalerIconData icon,
  required String title,
  required String message,
  required String confirmLabel,
  bool destructive = true,
}) async {
  final res = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      final p = TalerTheme.paletteOf(ctx);
      final bottom = MediaQuery.paddingOf(ctx).bottom;
      final confirmColor = destructive ? p.danger : p.accent;
      return Container(
        decoration: BoxDecoration(
          color: p.settingsBg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
          border: Border(top: BorderSide(color: p.line2)),
        ),
        padding: EdgeInsets.fromLTRB(16, 12, 16, bottom + 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _sheetHandle(p),
            Row(
              children: [
                TalerSettingsBadge(
                  icon: icon,
                  size: 34,
                  iconSize: 21,
                  iconColor: confirmColor,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: p.fg,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            TalerSettingsGroup(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                  child: Text(
                    message,
                    style: TextStyle(
                      fontSize: 14.5,
                      height: 1.45,
                      color: p.fg2,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 46,
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(ctx).pop(false),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: p.line2),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text('Отмена'),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SizedBox(
                    height: 46,
                    child: FilledButton(
                      onPressed: () => Navigator.of(ctx).pop(true),
                      style: FilledButton.styleFrom(
                        backgroundColor: confirmColor,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: Text(confirmLabel),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    },
  );
  return res == true;
}

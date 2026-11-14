import 'package:material_ui/material_ui.dart';

/// Палитра монохромной тактильной дизайн-системы Taler (Dark Obsidian и Light Paper).
class TalerPalette {
  final Brightness brightness;
  final Color bg;
  final Color bg2;
  final Color bg3;
  final Color fg;
  final Color fg2;
  final Color fg3;
  final Color fg4;
  final Color surface;
  final Color surface2;
  final Color surface3;
  final Color line;
  final Color line2;
  final Color solid;
  final Color onSolid;
  final Color glass;
  final Color statusLive;
  final Color statusLiveSurface;
  final Color warning;
  final Color warningSurface;
  final Color warningLine;
  final Color danger;
  final Color dangerSurface;
  final Color dangerLine;

  const TalerPalette({
    required this.brightness,
    required this.bg,
    required this.bg2,
    required this.bg3,
    required this.fg,
    required this.fg2,
    required this.fg3,
    required this.fg4,
    required this.surface,
    required this.surface2,
    required this.surface3,
    required this.line,
    required this.line2,
    required this.solid,
    required this.onSolid,
    required this.glass,
    required this.statusLive,
    required this.statusLiveSurface,
    required this.warning,
    required this.warningSurface,
    required this.warningLine,
    required this.danger,
    required this.dangerSurface,
    required this.dangerLine,
  });

  bool get isDark => brightness == Brightness.dark;
}

/// Тема оформления и тактильные примитивы интерфейса Taler.
class TalerTheme {
  static const Color accent = Color(0xFFF4F4F2);
  static const Color shieldGreen = Color(0xFF30A46C);
  static const Color warningAmber = Color(0xFFE5A000);
  static const Color dangerRed = Color(0xFFE5484D);

  static const Color darkBg = Color(0xFF0A0A0B);
  static const Color darkSurface = Color(0xFF111113);
  static const Color darkSurfaceElevated = Color(0xFF18181B);
  static const Color darkBorder = Color(0x16FFFFFF);

  static const Color lightBg = Color(0xFFF3F3F3);
  static const Color lightSurface = Color(0xFFFBFBFB);
  static const Color lightSurfaceElevated = Color(0xFFFFFFFF);
  static const Color lightBorder = Color(0x14000000);

  static const Curve springCurve = Cubic(0.32, 0.72, 0, 1);
  static const Curve easeOutCurve = Cubic(0.16, 1, 0.3, 1);
  static const Duration fastDuration = Duration(milliseconds: 140);
  static const Duration pillDuration = Duration(milliseconds: 220);

  static const TalerPalette darkPalette = TalerPalette(
    brightness: Brightness.dark,
    bg: Color(0xFF0A0A0B),
    bg2: Color(0xFF111113),
    bg3: Color(0xFF18181B),
    fg: Color(0xFFF4F4F2),
    fg2: Color(0xA8F4F4F2),
    fg3: Color(0x6BF4F4F2),
    fg4: Color(0x33F4F4F2),
    surface: Color(0x0EFFFFFF),
    surface2: Color(0x18FFFFFF),
    surface3: Color(0x26FFFFFF),
    line: Color(0x16FFFFFF),
    line2: Color(0x2BFFFFFF),
    solid: Color(0xFFF4F4F2),
    onSolid: Color(0xFF0A0A0B),
    glass: Color(0xD2111113),
    statusLive: shieldGreen,
    statusLiveSurface: Color(0x1E30A46C),
    warning: warningAmber,
    warningSurface: Color(0x1EE5A000),
    warningLine: Color(0x4DE5A000),
    danger: dangerRed,
    dangerSurface: Color(0x1FE5484D),
    dangerLine: Color(0x47E5484D),
  );

  static const TalerPalette lightPalette = TalerPalette(
    brightness: Brightness.light,
    bg: Color(0xFFF3F3F3),
    bg2: Color(0xFFFBFBFB),
    bg3: Color(0xFFFFFFFF),
    fg: Color(0xFF0B0B0B),
    fg2: Color(0xA60B0B0B),
    fg3: Color(0x6B0B0B0B),
    fg4: Color(0x330B0B0B),
    surface: Color(0x0B000000),
    surface2: Color(0x14000000),
    surface3: Color(0x1F000000),
    line: Color(0x14000000),
    line2: Color(0x26000000),
    solid: Color(0xFF0B0B0B),
    onSolid: Color(0xFFFAFAFA),
    glass: Color(0xDEFAFAFA),
    statusLive: Color(0xFF238656),
    statusLiveSurface: Color(0x1A238656),
    warning: Color(0xFFB87D00),
    warningSurface: Color(0x1AE5A000),
    warningLine: Color(0x47B87D00),
    danger: Color(0xFFCD3A3F),
    dangerSurface: Color(0x1AE5484D),
    dangerLine: Color(0x47CD3A3F),
  );

  static TalerPalette paletteOf(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? darkPalette
        : lightPalette;
  }

  static TextStyle monoStyle({
    double size = 12,
    FontWeight weight = FontWeight.w400,
    Color? color,
  }) {
    return TextStyle(
      fontFamily: 'monospace',
      fontFamilyFallback: const ['Consolas', 'Menlo', 'Courier New'],
      fontSize: size,
      fontWeight: weight,
      color: color,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
  }

  static TextStyle tabularStyle({
    double size = 13,
    FontWeight weight = FontWeight.w400,
    Color? color,
    double? height,
  }) {
    return TextStyle(
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: height,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
  }

  static ThemeData dark() => _buildTheme(darkPalette);

  static ThemeData light() => _buildTheme(lightPalette);

  static ThemeData _buildTheme(TalerPalette p) {
    final isDark = p.isDark;
    final scheme = ColorScheme(
      brightness: p.brightness,
      primary: p.solid,
      onPrimary: p.onSolid,
      secondary: p.surface2,
      onSecondary: p.fg,
      error: p.danger,
      onError: p.fg,
      surface: p.bg2,
      onSurface: p.fg,
      onSurfaceVariant: p.fg2,
      surfaceContainerLowest: p.bg,
      surfaceContainerLow: p.bg2,
      surfaceContainer: p.bg3,
      surfaceContainerHigh: p.surface2,
      outline: p.line,
      outlineVariant: p.line2,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: p.brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: p.bg,
      canvasColor: p.bg2,
      dividerColor: p.line,
      splashFactory: NoSplash.splashFactory,
      highlightColor: p.surface2,
      hoverColor: p.surface,
      textTheme: (isDark
              ? Typography.material2021().white
              : Typography.material2021().black)
          .apply(
        bodyColor: p.fg,
        displayColor: p.fg,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: p.bg2,
        foregroundColor: p.fg,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        color: p.bg2,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: p.line),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: p.bg2,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: p.line2),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: p.bg2,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          side: BorderSide(color: p.line),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return p.onSolid;
          return p.fg2;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return p.solid;
          return p.surface2;
        }),
        trackOutlineColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return p.solid;
          return p.line2;
        }),
        trackOutlineWidth: const WidgetStatePropertyAll(1),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: p.bg3,
        contentTextStyle: TextStyle(color: p.fg, fontSize: 13),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: p.line2),
        ),
        behavior: SnackBarBehavior.floating,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.surface,
        labelStyle: TextStyle(color: p.fg2, fontSize: 13),
        hintStyle: TextStyle(color: p.fg3, fontSize: 13),
        prefixIconColor: p.fg3,
        suffixIconColor: p.fg3,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: p.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: p.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: p.line2, width: 1.2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: p.dangerLine),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: p.solid,
          foregroundColor: p.onSolid,
          elevation: 0,
          textStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: p.fg,
          side: BorderSide(color: p.line2),
          textStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: p.fg2,
          textStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
    );
  }
}

/// Миниатюрная точка состояния без неонового свечения.
class TalerStatusDot extends StatelessWidget {
  final Color color;
  final double size;

  const TalerStatusDot({
    super.key,
    required this.color,
    this.size = 6,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
    );
  }
}

/// Описание сегмента для скользящей капсулы [TalerSlidingPillSwitch].
class TalerSegment<T> {
  final T value;
  final String label;
  final IconData? icon;
  final String? badge;

  const TalerSegment({
    required this.value,
    required this.label,
    this.icon,
    this.badge,
  });
}

/// Тактильный переключатель со скользящей монохромной капсулой (spring-кривая).
class TalerSlidingPillSwitch<T> extends StatelessWidget {
  final List<TalerSegment<T>> items;
  final T value;
  final ValueChanged<T>? onChanged;
  final double height;
  final bool pillShape;

  const TalerSlidingPillSwitch({
    super.key,
    required this.items,
    required this.value,
    required this.onChanged,
    this.height = 36,
    this.pillShape = false,
  });

  @override
  Widget build(BuildContext context) {
    final p = TalerTheme.paletteOf(context);
    final selectedIdx = items.indexWhere((e) => e.value == value).clamp(
          0,
          items.isEmpty ? 0 : items.length - 1,
        );
    final outerRadius = pillShape ? 999.0 : 12.0;
    final innerRadius = pillShape ? 999.0 : 8.0;

    return Container(
      height: height + 8,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(outerRadius),
        border: Border.all(color: p.line),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final count = items.isEmpty ? 1 : items.length;
          final slotWidth = constraints.maxWidth / count;

          return Stack(
            children: [
              AnimatedPositioned(
                duration: TalerTheme.pillDuration,
                curve: TalerTheme.springCurve,
                left: selectedIdx * slotWidth,
                top: 0,
                bottom: 0,
                width: slotWidth,
                child: Container(
                  decoration: BoxDecoration(
                    color: p.bg3,
                    borderRadius: BorderRadius.circular(innerRadius),
                    border: Border.all(color: p.line2),
                  ),
                ),
              ),
              Row(
                children: [
                  for (final item in items)
                    Expanded(
                      child: _SegmentItem<T>(
                        item: item,
                        selected: item.value == value,
                        radius: innerRadius,
                        onTap: onChanged == null
                            ? null
                            : () => onChanged!(item.value),
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SegmentItem<T> extends StatefulWidget {
  final TalerSegment<T> item;
  final bool selected;
  final double radius;
  final VoidCallback? onTap;

  const _SegmentItem({
    required this.item,
    required this.selected,
    required this.radius,
    required this.onTap,
  });

  @override
  State<_SegmentItem<T>> createState() => _SegmentItemState<T>();
}

class _SegmentItemState<T> extends State<_SegmentItem<T>> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final p = TalerTheme.paletteOf(context);
    final fg = widget.selected
        ? p.fg
        : _hovered
            ? p.fg2
            : p.fg3;

    return MouseRegion(
      cursor: widget.onTap != null
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.item.icon != null) ...[
                  Icon(widget.item.icon, size: 15, color: fg),
                  const SizedBox(width: 6),
                ],
                Flexible(
                  child: Text(
                    widget.item.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight:
                          widget.selected ? FontWeight.w500 : FontWeight.w400,
                      color: fg,
                    ),
                  ),
                ),
                if (widget.item.badge != null) ...[
                  const SizedBox(width: 6),
                  Text(
                    widget.item.badge!,
                    style: TalerTheme.monoStyle(
                      size: 11,
                      color: widget.selected ? p.fg2 : p.fg3,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

enum TalerButtonVariant { primary, keycap, danger }

/// Тактильная кнопка в стиле Hoplite keycap / инвертированного монохрома без скачков вверх.
class TalerTactileButton extends StatefulWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final TalerButtonVariant variant;
  final bool loading;
  final bool compact;
  final bool pill;

  const TalerTactileButton({
    super.key,
    required this.label,
    this.icon,
    required this.onPressed,
    this.variant = TalerButtonVariant.keycap,
    this.loading = false,
    this.compact = false,
    this.pill = false,
  });

  @override
  State<TalerTactileButton> createState() => _TalerTactileButtonState();
}

class _TalerTactileButtonState extends State<TalerTactileButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final p = TalerTheme.paletteOf(context);
    final enabled = widget.onPressed != null && !widget.loading;
    final height = widget.compact ? 32.0 : 40.0;
    final radius = widget.pill ? 999.0 : (widget.compact ? 8.0 : 10.0);

    final (bg, fg, border) = switch (widget.variant) {
      TalerButtonVariant.primary => (
          enabled
              ? (_hovered ? p.solid.withValues(alpha: 0.90) : p.solid)
              : p.surface2,
          enabled ? p.onSolid : p.fg3,
          enabled ? p.solid : p.line,
        ),
      TalerButtonVariant.keycap => (
          _hovered && enabled ? p.surface2 : p.surface,
          enabled ? p.fg : p.fg3,
          _hovered && enabled ? p.line2 : p.line,
        ),
      TalerButtonVariant.danger => (
          _hovered && enabled
              ? p.danger.withValues(alpha: 0.18)
              : p.dangerSurface,
          enabled ? p.danger : p.fg3,
          p.dangerLine,
        ),
    };

    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
        onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
        onTapCancel: () => setState(() => _pressed = false),
        onTap: enabled ? widget.onPressed : null,
        child: AnimatedScale(
          scale: _pressed ? 0.97 : 1.0,
          duration: const Duration(milliseconds: 90),
          curve: TalerTheme.easeOutCurve,
          child: AnimatedContainer(
            duration: TalerTheme.fastDuration,
            curve: TalerTheme.easeOutCurve,
            height: height,
            padding: EdgeInsets.symmetric(
              horizontal: widget.compact ? 10 : 16,
            ),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(color: border),
              boxShadow: widget.variant == TalerButtonVariant.keycap && enabled
                  ? [
                      BoxShadow(
                        color: p.isDark
                            ? const Color(0x55000000)
                            : const Color(0x14000000),
                        blurRadius: 4,
                        offset: const Offset(0, 1),
                      ),
                    ]
                  : null,
            ),
            child: Center(
              child: widget.loading
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.8,
                        color: fg,
                      ),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (widget.icon != null) ...[
                          Icon(
                            widget.icon,
                            size: widget.compact ? 14 : 16,
                            color: fg,
                          ),
                          const SizedBox(width: 8),
                        ],
                        Text(
                          widget.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: widget.compact ? 12 : 13,
                            fontWeight: FontWeight.w500,
                            color: fg,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Оптически отцентрированная кнопка с одной иконкой (без сдвигов отступов Material).
class TalerIconButton extends StatefulWidget {
  final IconData icon;
  final String? tooltip;
  final VoidCallback? onPressed;
  final double size;
  final double iconSize;
  final Color? color;
  final Color? backgroundColor;
  final bool circle;

  const TalerIconButton({
    super.key,
    required this.icon,
    this.tooltip,
    required this.onPressed,
    this.size = 36,
    this.iconSize = 18,
    this.color,
    this.backgroundColor,
    this.circle = false,
  });

  @override
  State<TalerIconButton> createState() => _TalerIconButtonState();
}

class _TalerIconButtonState extends State<TalerIconButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final p = TalerTheme.paletteOf(context);
    final enabled = widget.onPressed != null;
    final radius = widget.circle ? 999.0 : 10.0;
    final bg = widget.backgroundColor ??
        (_hovered && enabled ? p.surface2 : Colors.transparent);
    final border = widget.backgroundColor != null || (_hovered && enabled)
        ? p.line
        : Colors.transparent;
    final fg = widget.color ?? (enabled ? (_hovered ? p.fg : p.fg2) : p.fg4);

    final core = MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
        onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
        onTapCancel: () => setState(() => _pressed = false),
        onTap: enabled ? widget.onPressed : null,
        child: AnimatedScale(
          scale: _pressed ? 0.94 : 1.0,
          duration: const Duration(milliseconds: 90),
          child: AnimatedContainer(
            duration: TalerTheme.fastDuration,
            width: widget.size,
            height: widget.size,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(color: border),
            ),
            child: Icon(
              widget.icon,
              size: widget.iconSize,
              color: fg,
            ),
          ),
        ),
      ),
    );

    if (widget.tooltip != null && widget.tooltip!.isNotEmpty) {
      return Tooltip(message: widget.tooltip!, child: core);
    }
    return core;
  }
}

/// Двухслойная тактильная таблица/панель: внешняя оболочка (`16px`) + вложенное тело (`12px`).
class TalerTableShell extends StatelessWidget {
  final String? title;
  final Widget? titleLeading;
  final Widget? trailing;
  final Widget child;
  final EdgeInsetsGeometry bodyPadding;

  const TalerTableShell({
    super.key,
    this.title,
    this.titleLeading,
    this.trailing,
    required this.child,
    this.bodyPadding = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) {
    final p = TalerTheme.paletteOf(context);
    final hasHeader = title != null || trailing != null;

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: p.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hasHeader)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 6, 8),
              child: Row(
                children: [
                  if (titleLeading != null) ...[
                    titleLeading!,
                    const SizedBox(width: 8),
                  ],
                  if (title != null)
                    Expanded(
                      child: Text(
                        title!,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: p.fg2,
                        ),
                      ),
                    )
                  else
                    const Spacer(),
                  ?trailing,
                ],
              ),
            ),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: bodyPadding,
              decoration: BoxDecoration(
                color: p.bg2,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: p.line),
              ),
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}

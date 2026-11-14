import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

/// Палитра дизайн-системы Taler в обсидианово-графитовом стиле (Obsidian Monochrome + Muted Indigo).
class TalerPalette {
  final Brightness brightness;
  final Color bg;
  final Color settingsBg;
  final Color bg2;
  final Color bg3;
  final Color surfaceHigh;
  final Color bubbleOut;
  final Color bubbleIn;
  final Color bubbleOutText;
  final Color bubbleInText;
  final Color accent;
  final Color accentMuted;
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
    required this.settingsBg,
    required this.bg2,
    required this.bg3,
    required this.surfaceHigh,
    required this.bubbleOut,
    required this.bubbleIn,
    required this.bubbleOutText,
    required this.bubbleInText,
    required this.accent,
    required this.accentMuted,
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

  static const List<(Color, Color)> _avatarGradients = [
    (Color(0xFF8B84E2), Color(0xFF5E58B0)), // Slate Indigo
    (Color(0xFFE07A5F), Color(0xFFB5543D)), // Muted Terracotta
    (Color(0xFF52A88B), Color(0xFF337C64)), // Sage Emerald
    (Color(0xFF6B8FB8), Color(0xFF47688F)), // Steel Blue
    (Color(0xFFD49B54), Color(0xFFA77434)), // Warm Ochre
    (Color(0xFFC46D8E), Color(0xFF964A67)), // Dusty Rose
    (Color(0xFF7B818E), Color(0xFF525763)), // Graphite Pewter
  ];

  static const List<Color> _peerColorsDark = [
    Color(0xFFABA6F2),
    Color(0xFFEF9A7F),
    Color(0xFF74C6A8),
    Color(0xFF8FB4DE),
    Color(0xFFE5B87A),
    Color(0xFFDF92AF),
    Color(0xFFB2B7C4),
  ];

  static const List<Color> _peerColorsLight = [
    Color(0xFF5B54AD),
    Color(0xFFBA5136),
    Color(0xFF2D7D61),
    Color(0xFF3E6896),
    Color(0xFFA96E24),
    Color(0xFFA4486A),
    Color(0xFF565B68),
  ];

  /// Возвращает спокойную 2-цветную градиентную аватарку по `id.abs() % 7`.
  static List<Color> avatarGradientForId(int id) {
    final pair = _avatarGradients[id.abs() % _avatarGradients.length];
    return [pair.$1, pair.$2];
  }

  /// Возвращает читаемый цвет имени отправителя в групповом чате по `id.abs() % 7`.
  Color peerColorForId(int id) {
    final list = isDark ? _peerColorsDark : _peerColorsLight;
    return list[id.abs() % list.length];
  }
}

/// Тема оформления и тактильные UI-примитивы Taler (Monochrome Tactile UI + Obsidian Indigo).
class TalerTheme {
  static const Color obsidianIndigo = Color(0xFF7C76D6);
  static const Color bubbleIndigo = Color(0xFF6862B8);
  static const Color shieldGreen = Color(0xFF30A46C);
  static const Color warningAmber = Color(0xFFE5A000);
  static const Color dangerRed = Color(0xFFE5484D);

  static const Curve springCurve = Cubic(0.32, 0.72, 0, 1);
  static const Curve easeOutCurve = Cubic(0.16, 1, 0.3, 1);
  static const Duration fastDuration = Duration(milliseconds: 140);
  static const Duration pillDuration = Duration(milliseconds: 220);

  static const TalerPalette darkPalette = TalerPalette(
    brightness: Brightness.dark,
    bg: Color(0xFF0A0A0C),
    settingsBg: Color(0xFF0A0A0C),
    bg2: Color(0xFF121216),
    bg3: Color(0xFF1A1A20),
    surfaceHigh: Color(0xFF23232C),
    bubbleOut: bubbleIndigo,
    bubbleIn: Color(0xFF1C1C22),
    bubbleOutText: Color(0xFFF5F5F7),
    bubbleInText: Color(0xFFF2F2F4),
    accent: obsidianIndigo,
    accentMuted: Color(0xFF4E4A8A),
    fg: Color(0xFFF2F2F0),
    fg2: Color(0xFF9A9AA4),
    fg3: Color(0xFF63636E),
    fg4: Color(0x389A9AA4),
    surface: Color(0xFF17171C),
    surface2: Color(0xFF1F1F26),
    surface3: Color(0xFF2A2A34),
    line: Color(0x14FFFFFF),
    line2: Color(0x22FFFFFF),
    solid: Color(0xFFF2F2F0),
    onSolid: Color(0xFF0A0A0C),
    glass: Color(0xE6121216),
    statusLive: shieldGreen,
    statusLiveSurface: Color(0x1F30A46C),
    warning: warningAmber,
    warningSurface: Color(0x1FE5A000),
    warningLine: Color(0x4DE5A000),
    danger: dangerRed,
    dangerSurface: Color(0x1FE5484D),
    dangerLine: Color(0x4DE5484D),
  );

  static const TalerPalette lightPalette = TalerPalette(
    brightness: Brightness.light,
    bg: Color(0xFFF1F1F3),
    settingsBg: Color(0xFFF1F1F3),
    bg2: Color(0xFFFAFAFB),
    bg3: Color(0xFFEAEAEF),
    surfaceHigh: Color(0xFFE4E3F5),
    bubbleOut: bubbleIndigo,
    bubbleIn: Color(0xFFFFFFFF),
    bubbleOutText: Color(0xFFFFFFFF),
    bubbleInText: Color(0xFF111113),
    accent: Color(0xFF5E58B0),
    accentMuted: Color(0xFF8882D0),
    fg: Color(0xFF111113),
    fg2: Color(0xFF60606C),
    fg3: Color(0xFF8C8C98),
    fg4: Color(0x3860606C),
    surface: Color(0xFFEFEFF2),
    surface2: Color(0xFFE5E5EA),
    surface3: Color(0xFFD9D9E0),
    line: Color(0x14000000),
    line2: Color(0x22000000),
    solid: Color(0xFF111113),
    onSolid: Color(0xFFFFFFFF),
    glass: Color(0xEBFAFAFB),
    statusLive: Color(0xFF288E5B),
    statusLiveSurface: Color(0x1A288E5B),
    warning: Color(0xFFC28200),
    warningSurface: Color(0x1AE5A000),
    warningLine: Color(0x4DC28200),
    danger: Color(0xFFD63B40),
    dangerSurface: Color(0x1AE5484D),
    dangerLine: Color(0x4DD63B40),
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
      primary: p.accent,
      onPrimary: Colors.white,
      secondary: p.accentMuted,
      onSecondary: Colors.white,
      error: p.danger,
      onError: Colors.white,
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
      highlightColor: p.surface.withValues(alpha: 0.7),
      hoverColor: p.surface.withValues(alpha: 0.5),
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
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: p.line),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: p.bg2,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: p.line2),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: p.bg2,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          side: BorderSide(color: p.line),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return Colors.white;
          return p.isDark ? p.fg2 : Colors.white;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return p.accent;
          return p.isDark ? p.surface3 : const Color(0xFFC8C8D0);
        }),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
        trackOutlineWidth: const WidgetStatePropertyAll(0),
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
        fillColor: p.bg3,
        labelStyle: TextStyle(color: p.fg2, fontSize: 13),
        hintStyle: TextStyle(color: p.fg3, fontSize: 13.5),
        prefixIconColor: p.fg2,
        suffixIconColor: p.fg2,
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
          borderSide: BorderSide(color: p.line2, width: 1.4),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: p.danger),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: p.solid,
          foregroundColor: p.onSolid,
          elevation: 0,
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: p.fg,
          side: BorderSide(color: p.line2),
          textStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13.5),
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

/// Круглая аватарка пользователя или чата с мягкой палитрой по ID.
class TalerAvatar extends StatelessWidget {
  final int seedId;
  final String initials;
  final double size;
  final bool isOnline;
  final Color? onlineBorderColor;
  final double? fontSize;

  const TalerAvatar({
    super.key,
    required this.seedId,
    required this.initials,
    this.size = 44,
    this.isOnline = false,
    this.onlineBorderColor,
    this.fontSize,
  });

  @override
  Widget build(BuildContext context) {
    final p = TalerTheme.paletteOf(context);
    final colors = TalerPalette.avatarGradientForId(seedId);
    final textSize = fontSize ?? (size * 0.34).clamp(11.0, 22.0);
    final dotSize = (size * 0.24).clamp(9.0, 13.0);

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: size,
            height: size,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: colors,
              ),
              border: Border.all(color: p.line, width: 0.7),
            ),
            child: Text(
              initials.isEmpty ? 'T' : initials,
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: textSize,
                letterSpacing: -0.2,
              ),
            ),
          ),
          if (isOnline)
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: dotSize,
                height: dotSize,
                decoration: BoxDecoration(
                  color: p.statusLive,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: onlineBorderColor ?? p.bg2,
                    width: 2,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Монохромный тактильный бокс для иконки настройки без цветной заливки.
class TelegramIconBadge extends StatelessWidget {
  final IconData icon;
  final Color? color;
  final double size;

  const TelegramIconBadge({
    super.key,
    required this.icon,
    this.color,
    this.size = 30,
  });

  @override
  Widget build(BuildContext context) {
    final p = TalerTheme.paletteOf(context);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: p.bg3,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: p.line2),
      ),
      child: Icon(
        icon,
        size: size * 0.54,
        color: p.fg2,
      ),
    );
  }
}

/// Миниатюрная точка состояния без свечения и теней.
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

/// Сверхлёгкий статический точечный холст чата в стиле Hoplite (нулевая нагрузка на CPU).
class TelegramChatBackground extends StatelessWidget {
  final Widget child;

  const TelegramChatBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final p = TalerTheme.paletteOf(context);
    return Container(
      color: p.bg,
      child: Stack(
        fit: StackFit.expand,
        children: [
          RepaintBoundary(
            child: CustomPaint(
              isComplex: true,
              willChange: false,
              painter: _DotMatrixPainter(isDark: p.isDark),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class _DotMatrixPainter extends CustomPainter {
  final bool isDark;

  const _DotMatrixPainter({required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    final dotColor =
        isDark ? const Color(0x0BFFFFFF) : const Color(0x10000000);
    final paint = Paint()
      ..color = dotColor
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;

    const step = 32.0;
    final cols = math.min(96, (size.width / step).ceil() + 1);
    final rows = math.min(64, (size.height / step).ceil() + 1);
    final points = <Offset>[];

    for (var r = 0; r < rows; r++) {
      final y = r * step + 16;
      final rowOffset = r.isOdd ? step * 0.5 : 0.0;
      for (var c = 0; c < cols; c++) {
        points.add(Offset(c * step + rowOffset + 12, y));
      }
    }

    canvas.drawPoints(ui.PointMode.points, points, paint);
  }

  @override
  bool shouldRepaint(covariant _DotMatrixPainter oldDelegate) =>
      oldDelegate.isDark != isDark;
}

/// Описание сегмента для скользящего переключателя [TalerSlidingPillSwitch].
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

/// Тактильный сегментированный переключатель со скользящей пилюлей.
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
    this.height = 34,
    this.pillShape = false,
  });

  @override
  Widget build(BuildContext context) {
    final p = TalerTheme.paletteOf(context);
    final selectedIdx = items.indexWhere((e) => e.value == value).clamp(
          0,
          items.isEmpty ? 0 : items.length - 1,
        );
    final outerRadius = pillShape ? 999.0 : 10.0;
    final innerRadius = pillShape ? 999.0 : 7.0;

    return Container(
      height: height + 6,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: p.isDark ? p.bg : p.bg3,
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
                    color: p.isDark ? p.surfaceHigh : p.bg2,
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
  final VoidCallback? onTap;

  const _SegmentItem({
    required this.item,
    required this.selected,
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
            ? p.fg
            : p.fg2;

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
                          widget.selected ? FontWeight.w600 : FontWeight.w400,
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
                      color: widget.selected ? p.accent : p.fg3,
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

/// Тактильная кнопка в стиле Monochrome Tactile UI (инвертированная `solid` для `primary`).
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
    final height = widget.compact ? 32.0 : 42.0;
    final radius = widget.pill ? 999.0 : (widget.compact ? 8.0 : 10.0);

    final (bg, fg, border) = switch (widget.variant) {
      TalerButtonVariant.primary => (
          enabled
              ? (_hovered ? p.solid.withValues(alpha: 0.9) : p.solid)
              : p.surface2,
          enabled ? p.onSolid : p.fg3,
          Colors.transparent,
        ),
      TalerButtonVariant.keycap => (
          _hovered && enabled ? p.surfaceHigh : p.bg3,
          enabled ? p.fg : p.fg3,
          p.line2,
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
          scale: _pressed ? 0.985 : 1.0,
          duration: const Duration(milliseconds: 90),
          curve: TalerTheme.easeOutCurve,
          child: AnimatedContainer(
            duration: TalerTheme.fastDuration,
            curve: TalerTheme.easeOutCurve,
            height: height,
            padding: EdgeInsets.symmetric(
              horizontal: widget.compact ? 12 : 16,
            ),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(radius),
              border: border == Colors.transparent
                  ? null
                  : Border.all(color: border),
            ),
            child: Center(
              child: widget.loading
                  ? SizedBox(
                      width: 17,
                      height: 17,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: fg,
                      ),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (widget.icon != null) ...[
                          Icon(
                            widget.icon,
                            size: widget.compact ? 15 : 17,
                            color: fg,
                          ),
                          const SizedBox(width: 8),
                        ],
                        Flexible(
                          child: Text(
                            widget.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: widget.compact ? 12.5 : 13.5,
                              fontWeight: FontWeight.w600,
                              color: fg,
                            ),
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

/// Компактная кнопка с одной иконкой в шапке и панели ввода.
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
    this.iconSize = 19,
    this.color,
    this.backgroundColor,
    this.circle = true,
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
    final radius = widget.circle ? 999.0 : 9.0;
    final bg = widget.backgroundColor ??
        (_hovered && enabled
            ? p.surfaceHigh.withValues(alpha: 0.75)
            : Colors.transparent);
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

/// Секционная карточка настроек в стиле Monochrome Tactile UI (`1px solid line`, `p.bg2`).
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (hasHeader)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 2, 4, 8),
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
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
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
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: bodyPadding,
            decoration: BoxDecoration(
              color: p.bg2,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: p.line),
            ),
            child: child,
          ),
        ),
      ],
    );
  }
}

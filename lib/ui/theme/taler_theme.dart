import 'package:material_ui/material_ui.dart';

import '../icons/taler_icon.dart';

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
    (Color(0xFF5E7D8C), Color(0xFF5E7D8C)), // Slate
    (Color(0xFFA0715A), Color(0xFFA0715A)), // Clay
    (Color(0xFF5C8A72), Color(0xFF5C8A72)), // Patina
    (Color(0xFF6E7AA0), Color(0xFF6E7AA0)), // Steel
    (Color(0xFFA08A55), Color(0xFFA08A55)), // Brass
    (Color(0xFF9A6B7C), Color(0xFF9A6B7C)), // Rosewood
    (Color(0xFF6B6F78), Color(0xFF6B6F78)), // Graphite
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
  static const Color obsidianIndigo = Color(0xFF5DBB94);
  static const Color bubbleIndigo = Color(0xFF1F3A31);
  static const Color shieldGreen = Color(0xFF30A46C);
  static const Color warningAmber = Color(0xFFE5A000);
  static const Color dangerRed = Color(0xFFE5484D);

  static const Curve springCurve = Cubic(0.32, 0.72, 0, 1);
  static const Curve easeOutCurve = Cubic(0.16, 1, 0.3, 1);
  static const Duration fastDuration = Duration(milliseconds: 140);
  static const Duration pillDuration = Duration(milliseconds: 220);

  static const TalerPalette darkPalette = TalerPalette(
    brightness: Brightness.dark,
    bg: Color(0xFF09090B),
    settingsBg: Color(0xFF09090B),
    bg2: Color(0xFF0C0C0E),
    bg3: Color(0xFF222226),
    surfaceHigh: Color(0xFF27272A),
    bubbleOut: Color(0xFF2563EB),
    bubbleIn: Color(0xFF1C1C20),
    bubbleOutText: Color(0xFFFFFFFF),
    bubbleInText: Color(0xFFF4F4F5),
    accent: Color(0xFF4C8DFF),
    accentMuted: Color(0x244C8DFF),
    fg: Color(0xFFFAFAFA),
    fg2: Color(0xFFA1A1AA),
    fg3: Color(0xFF71717A),
    fg4: Color(0x3871717A),
    surface: Color(0xFF18181B),
    surface2: Color(0xFF222226),
    surface3: Color(0xFF2A2A2E),
    line: Color(0x12FFFFFF),
    line2: Color(0x1FFFFFFF),
    solid: Color(0xFFFAFAFA),
    onSolid: Color(0xFF09090B),
    glass: Color(0xE618181A),
    statusLive: Color(0xFF22C55E),
    statusLiveSurface: Color(0x1F22C55E),
    warning: Color(0xFFF59E0B),
    warningSurface: Color(0x1FF59E0B),
    warningLine: Color(0x40F59E0B),
    danger: Color(0xFFEF4444),
    dangerSurface: Color(0x1AEF4444),
    dangerLine: Color(0x40EF4444),
  );

  static const TalerPalette lightPalette = TalerPalette(
    brightness: Brightness.light,
    bg: Color(0xFFFFFFFF),
    settingsBg: Color(0xFFF4F4F5),
    bg2: Color(0xFFFFFFFF),
    bg3: Color(0xFFF4F4F5),
    surfaceHigh: Color(0xFFE4E4E7),
    bubbleOut: Color(0xFF2563EB),
    bubbleIn: Color(0xFFFFFFFF),
    bubbleOutText: Color(0xFFFFFFFF),
    bubbleInText: Color(0xFF09090B),
    accent: Color(0xFF2563EB),
    accentMuted: Color(0x1A2563EB),
    fg: Color(0xFF09090B),
    fg2: Color(0xFF52525B),
    fg3: Color(0xFF71717A),
    fg4: Color(0x3871717A),
    surface: Color(0xFFFFFFFF),
    surface2: Color(0xFFF4F4F5),
    surface3: Color(0xFFE4E4E7),
    line: Color(0x1409090B),
    line2: Color(0x2409090B),
    solid: Color(0xFF09090B),
    onSolid: Color(0xFFFFFFFF),
    glass: Color(0xC7FAFAFA),
    statusLive: Color(0xFF16A34A),
    statusLiveSurface: Color(0x1A16A34A),
    warning: Color(0xFFB45309),
    warningSurface: Color(0x1AF59E0B),
    warningLine: Color(0x40B45309),
    danger: Color(0xFFDC2626),
    dangerSurface: Color(0x1ADC2626),
    dangerLine: Color(0x40DC2626),
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
      fontFamily: 'GeistMono',
      fontFamilyFallback: const ['Consolas', 'Menlo'],
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
      fontFamily: 'Geist',
      brightness: p.brightness,
      iconTheme: IconThemeData(color: p.fg2, size: 18),
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
        fontFamily: 'Geist',
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
          textStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
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

/// Палитра аватарок и имён в группах (по id, стабильно).
const List<Color> kTalerPeerColors = [
  Color(0xFFE17076),
  Color(0xFF7BC862),
  Color(0xFF65AADD),
  Color(0xFFA695E7),
  Color(0xFFEE7AAE),
  Color(0xFF6EC9CB),
  Color(0xFFFAA774),
  Color(0xFF8E97A6),
];

/// Круглая аватарка: фото с сервера MAX, а пока оно грузится или если его нет —
/// инициалы на цветном круге.
class TalerAvatar extends StatelessWidget {
  final int seedId;
  final String initials;
  final double size;
  final bool isOnline;
  final Color? onlineBorderColor;
  final double? fontSize;
  final String? imageUrl;

  const TalerAvatar({
    super.key,
    required this.seedId,
    required this.initials,
    this.size = 44,
    this.isOnline = false,
    this.onlineBorderColor,
    this.fontSize,
    this.imageUrl,
  });

  @override
  Widget build(BuildContext context) {
    final p = TalerTheme.paletteOf(context);
    final base = kTalerPeerColors[seedId.abs() % kTalerPeerColors.length];
    final textSize = fontSize ?? (size * 0.36).clamp(10.0, 36.0);
    final dotSize = (size * 0.26).clamp(9.0, 16.0);
    final fallback = DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [base, Color.lerp(base, Colors.black, 0.22)!],
        ),
      ),
      child: Center(
        child: Text(
          initials.isEmpty ? '?' : initials,
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500, fontSize: textSize),
        ),
      ),
    );
    final url = imageUrl;
    final Widget face;
    if (url != null && (url.startsWith('http://') || url.startsWith('https://'))) {
      final px = (size * MediaQuery.devicePixelRatioOf(context)).round();
      face = ClipOval(
        child: Image.network(
          url,
          width: size,
          height: size,
          fit: BoxFit.cover,
          cacheWidth: px,
          filterQuality: FilterQuality.medium,
          errorBuilder: (_, _, _) => fallback,
          frameBuilder: (context, child, frame, sync) => frame == null && !sync ? fallback : child,
        ),
      );
    } else {
      face = fallback;
    }
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(child: face),
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
                  border: Border.all(color: onlineBorderColor ?? p.bg2, width: 2),
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
  final TalerIconData icon;
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
      child: TalerIcon(
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
    return ColoredBox(color: p.bg, child: child);
  }
}

/// Описание сегмента для скользящего переключателя [TalerSlidingPillSwitch].
class TalerSegment<T> {
  final T value;
  final String label;
  final TalerIconData? icon;
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
                  TalerIcon(widget.item.icon, size: 15, color: fg),
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
  final TalerIconData? icon;
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
                          TalerIcon(
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
  final TalerIconData icon;
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
            child: TalerIcon(
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

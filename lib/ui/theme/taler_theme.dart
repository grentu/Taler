import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

/// Палитра дизайн-системы Taler в стиле Telegram (Night Blue и Classic Day).
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
    (Color(0xFFFF885E), Color(0xFFD45246)), // Coral Red
    (Color(0xFFFEBB5B), Color(0xFFF68136)), // Amber Orange
    (Color(0xFFB694F9), Color(0xFF6C61DF)), // Royal Violet
    (Color(0xFF9AD164), Color(0xFF46BA43)), // Emerald Green
    (Color(0xFF53EDCE), Color(0xFF28A8A8)), // Teal Cyan
    (Color(0xFF5CAFFA), Color(0xFF408ACF)), // Sky Blue
    (Color(0xFFFF8AAC), Color(0xFFD95574)), // Rose Pink
  ];

  static const List<Color> _peerColorsDark = [
    Color(0xFFFF8A65),
    Color(0xFFFFB74D),
    Color(0xFFB39DDB),
    Color(0xFF81C784),
    Color(0xFF4DD0E1),
    Color(0xFF64B5F6),
    Color(0xFFF48FB1),
  ];

  static const List<Color> _peerColorsLight = [
    Color(0xFFCC5049),
    Color(0xFFD67722),
    Color(0xFF6F62D2),
    Color(0xFF3E9D3B),
    Color(0xFF1D9999),
    Color(0xFF3581C9),
    Color(0xFFC94B69),
  ];

  /// Возвращает классический 2-цветный градиент аватарки Telegram по `id.abs() % 7`.
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

/// Тема оформления и UI-примитивы Taler в стиле Telegram.
class TalerTheme {
  static const Color telegramBlue = Color(0xFF2AABEE);
  static const Color telegramBlueDeep = Color(0xFF229ED9);
  static const Color shieldGreen = Color(0xFF4ECC5E);
  static const Color warningAmber = Color(0xFFF5A623);
  static const Color dangerRed = Color(0xFFE55353);

  static const Curve springCurve = Cubic(0.32, 0.72, 0, 1);
  static const Curve easeOutCurve = Cubic(0.16, 1, 0.3, 1);
  static const Duration fastDuration = Duration(milliseconds: 140);
  static const Duration pillDuration = Duration(milliseconds: 220);

  static const TalerPalette darkPalette = TalerPalette(
    brightness: Brightness.dark,
    bg: Color(0xFF0E1621),
    settingsBg: Color(0xFF0E1621),
    bg2: Color(0xFF17212B),
    bg3: Color(0xFF242F3D),
    surfaceHigh: Color(0xFF2B5278),
    bubbleOut: Color(0xFF2B5278),
    bubbleIn: Color(0xFF182533),
    bubbleOutText: Color(0xFFF5F5F5),
    bubbleInText: Color(0xFFF5F5F5),
    accent: Color(0xFF2AABEE),
    accentMuted: Color(0xFF5288C1),
    fg: Color(0xFFF5F5F5),
    fg2: Color(0xFF7F91A4),
    fg3: Color(0xFF5D6E80),
    fg4: Color(0x407F91A4),
    surface: Color(0xFF1E2C3A),
    surface2: Color(0xFF242F3D),
    surface3: Color(0xFF2F3E4F),
    line: Color(0xFF101921),
    line2: Color(0x1CFFFFFF),
    solid: Color(0xFF2AABEE),
    onSolid: Color(0xFFFFFFFF),
    glass: Color(0xEB17212B),
    statusLive: shieldGreen,
    statusLiveSurface: Color(0x1F4ECC5E),
    warning: warningAmber,
    warningSurface: Color(0x21F5A623),
    warningLine: Color(0x52F5A623),
    danger: dangerRed,
    dangerSurface: Color(0x21E55353),
    dangerLine: Color(0x52E55353),
  );

  static const TalerPalette lightPalette = TalerPalette(
    brightness: Brightness.light,
    bg: Color(0xFFD6E3EE),
    settingsBg: Color(0xFFF1F3F6),
    bg2: Color(0xFFFFFFFF),
    bg3: Color(0xFFF1F3F6),
    surfaceHigh: Color(0xFF419FD9),
    bubbleOut: Color(0xFFEFFDDE),
    bubbleIn: Color(0xFFFFFFFF),
    bubbleOutText: Color(0xFF111111),
    bubbleInText: Color(0xFF111111),
    accent: Color(0xFF3390EC),
    accentMuted: Color(0xFF3390EC),
    fg: Color(0xFF111111),
    fg2: Color(0xFF707579),
    fg3: Color(0xFF8E959B),
    fg4: Color(0x40707579),
    surface: Color(0xFFF4F6F8),
    surface2: Color(0xFFEBEEF2),
    surface3: Color(0xFFDFE4EA),
    line: Color(0xFFE4E8EC),
    line2: Color(0x1F000000),
    solid: Color(0xFF3390EC),
    onSolid: Color(0xFFFFFFFF),
    glass: Color(0xF5FFFFFF),
    statusLive: shieldGreen,
    statusLiveSurface: Color(0x1A4ECC5E),
    warning: Color(0xFFCC8400),
    warningSurface: Color(0x1EF5A623),
    warningLine: Color(0x4DCC8400),
    danger: Color(0xFFD93C3C),
    dangerSurface: Color(0x1EE55353),
    dangerLine: Color(0x4DD93C3C),
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
      onPrimary: p.onSolid,
      secondary: p.accentMuted,
      onSecondary: p.onSolid,
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
          return p.isDark ? const Color(0xFF7F91A4) : Colors.white;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return p.accent;
          return p.isDark ? p.bg3 : const Color(0xFFC4C9D0);
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
        labelStyle: TextStyle(color: p.fg2, fontSize: 13.5),
        hintStyle: TextStyle(color: p.fg3, fontSize: 13.5),
        prefixIconColor: p.fg2,
        suffixIconColor: p.fg2,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: p.line2),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: p.line2),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: p.accent, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: p.danger),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: p.accent,
          foregroundColor: p.onSolid,
          elevation: 0,
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: p.accent,
          side: BorderSide(color: p.line2),
          textStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: p.accent,
          textStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
    );
  }
}

/// Круглая градиентная аватарка в стиле Telegram (7 классических палитр по ID).
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
    final dotSize = (size * 0.25).clamp(10.0, 14.0);

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
                    width: 2.2,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Скруглённый цветной квадратный значок настройки в стиле Telegram (30x30).
class TelegramIconBadge extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;

  const TelegramIconBadge({
    super.key,
    required this.icon,
    required this.color,
    this.size = 30,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(size * 0.27),
      ),
      child: Icon(
        icon,
        size: size * 0.58,
        color: Colors.white,
      ),
    );
  }
}

/// Миниатюрная точка состояния.
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

/// Лёгкий векторный паттерн фона чата в духе Telegram Wallpaper.
class TelegramChatBackground extends StatelessWidget {
  final Widget child;

  const TelegramChatBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final p = TalerTheme.paletteOf(context);
    return Container(
      color: p.bg,
      child: CustomPaint(
        painter: _TelegramPatternPainter(isDark: p.isDark),
        child: child,
      ),
    );
  }
}

class _TelegramPatternPainter extends CustomPainter {
  final bool isDark;

  const _TelegramPatternPainter({required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    final strokeColor = isDark
        ? const Color(0x0AFFFFFF)
        : const Color(0x0F537B9E);

    final paint = Paint()
      ..color = strokeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    const tileW = 140.0;
    const tileH = 140.0;
    final cols = (size.width / tileW).ceil() + 1;
    final rows = (size.height / tileH).ceil() + 1;

    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        final ox = c * tileW + (r.isOdd ? 46.0 : 0.0);
        final oy = r * tileH;
        final kind = (r * 3 + c) % 4;
        switch (kind) {
          case 0:
            // Бумажный самолётик
            final path = Path()
              ..moveTo(ox + 18, oy + 32)
              ..lineTo(ox + 42, oy + 20)
              ..lineTo(ox + 34, oy + 42)
              ..lineTo(ox + 28, oy + 34)
              ..close();
            canvas.drawPath(path, paint);
            canvas.drawLine(
              Offset(ox + 28, oy + 34),
              Offset(ox + 42, oy + 20),
              paint,
            );
          case 1:
            // Щит приватности
            final shield = Path()
              ..moveTo(ox + 82, oy + 26)
              ..lineTo(ox + 94, oy + 30)
              ..lineTo(ox + 94, oy + 40)
              ..quadraticBezierTo(ox + 94, oy + 50, ox + 82, oy + 55)
              ..quadraticBezierTo(ox + 70, oy + 50, ox + 70, oy + 40)
              ..lineTo(ox + 70, oy + 30)
              ..close();
            canvas.drawPath(shield, paint);
          case 2:
            // Замок шифрования
            canvas.drawRRect(
              RRect.fromRectAndRadius(
                Rect.fromLTWH(ox + 24, oy + 86, 18, 14),
                const Radius.circular(3.5),
              ),
              paint,
            );
            canvas.drawArc(
              Rect.fromLTWH(ox + 27, oy + 78, 12, 14),
              math.pi,
              math.pi,
              false,
              paint,
            );
          default:
            // Облачко диалога
            canvas.drawRRect(
              RRect.fromRectAndRadius(
                Rect.fromLTWH(ox + 74, oy + 82, 24, 16),
                const Radius.circular(6),
              ),
              paint,
            );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _TelegramPatternPainter oldDelegate) =>
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

/// Сегментированный переключатель со скользящей пилюлей в стиле Telegram.
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
    final outerRadius = pillShape ? 999.0 : 12.0;
    final innerRadius = pillShape ? 999.0 : 9.0;

    return Container(
      height: height + 6,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: p.isDark ? p.bg : p.surface2,
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
                    color: p.isDark ? p.bg3 : p.bg2,
                    borderRadius: BorderRadius.circular(innerRadius),
                    boxShadow: p.isDark
                        ? null
                        : const [
                            BoxShadow(
                              color: Color(0x14000000),
                              blurRadius: 4,
                              offset: Offset(0, 1),
                            ),
                          ],
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
        ? (p.isDark ? p.fg : p.accent)
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

/// Аккуратная кнопка в стиле Telegram (с акцентом `#2AABEE` для `primary`).
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
    final height = widget.compact ? 32.0 : 44.0;
    final radius = widget.pill ? 999.0 : (widget.compact ? 8.0 : 12.0);

    final (bg, fg, border) = switch (widget.variant) {
      TalerButtonVariant.primary => (
          enabled
              ? (_hovered ? p.accent.withValues(alpha: 0.88) : p.accent)
              : p.surface2,
          enabled ? Colors.white : p.fg3,
          Colors.transparent,
        ),
      TalerButtonVariant.keycap => (
          _hovered && enabled ? p.bg3 : p.surface,
          enabled ? p.accent : p.fg3,
          p.line,
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
          scale: _pressed ? 0.98 : 1.0,
          duration: const Duration(milliseconds: 90),
          curve: TalerTheme.easeOutCurve,
          child: AnimatedContainer(
            duration: TalerTheme.fastDuration,
            curve: TalerTheme.easeOutCurve,
            height: height,
            padding: EdgeInsets.symmetric(
              horizontal: widget.compact ? 12 : 18,
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
                      width: 18,
                      height: 18,
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
                            size: widget.compact ? 15 : 18,
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
                              fontSize: widget.compact ? 12.5 : 14,
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

/// Кнопка с одной иконкой в стиле Telegram header/composer buttons.
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
    this.size = 38,
    this.iconSize = 20,
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
    final radius = widget.circle ? 999.0 : 10.0;
    final bg = widget.backgroundColor ??
        (_hovered && enabled
            ? p.fg2.withValues(alpha: 0.14)
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
          scale: _pressed ? 0.92 : 1.0,
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

/// Сгруппированная карточка секции настроек в стиле Telegram Settings (синий заголовок + карточка `#17212B`).
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
            padding: const EdgeInsets.fromLTRB(14, 4, 4, 8),
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
                        fontWeight: FontWeight.w600,
                        color: p.accent,
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

import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import '../icons/taler_icon.dart';

/// Векторный логотип Taler: чеканный обсидианово-серебряный талер с
/// геометрической монограммой «T» и акцентом щита.
class TalerLogo extends StatelessWidget {
  final double size;
  final bool showShieldBadge;
  final bool circular;

  const TalerLogo({
    super.key,
    this.size = 48,
    this.showShieldBadge = false,
    this.circular = true,
  });

  @override
  Widget build(BuildContext context) {
    final badgeSize = (size * 0.30).clamp(11.0, 26.0);

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          CustomPaint(
            size: Size.square(size),
            painter: _TalerLogoPainter(circular: circular),
          ),
          if (showShieldBadge)
            Positioned(
              right: -size * 0.02,
              bottom: -size * 0.02,
              child: Container(
                width: badgeSize,
                height: badgeSize,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFF30A46C),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    width: (size * 0.032).clamp(1.5, 2.8),
                  ),
                ),
                child: TalerIcon(
                  TalerIcons.shieldCheck,
                  size: badgeSize * 0.56,
                  color: Colors.white,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TalerLogoPainter extends CustomPainter {
  final bool circular;

  const _TalerLogoPainter({required this.circular});

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final rect = Offset.zero & size;
    final center = Offset(s / 2, s / 2);

    // 1. Обсидианово-графитовая основа монеты без глянцевого свечения
    final bgShader = const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Color(0xFF1E1E26),
        Color(0xFF101015),
      ],
    ).createShader(rect);

    final bgPaint = Paint()..shader = bgShader;
    final borderPaint = Paint()
      ..color = const Color(0x2EFFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = (s * 0.022).clamp(1.0, 2.0);

    if (circular) {
      canvas.drawCircle(center, s / 2 - 0.5, bgPaint);
      canvas.drawCircle(center, s / 2 - 0.5, borderPaint);
    } else {
      final rr = RRect.fromRectAndRadius(
        rect.deflate(0.5),
        Radius.circular(s * 0.26),
      );
      canvas.drawRRect(rr, bgPaint);
      canvas.drawRRect(rr, borderPaint);
    }

    // 2. Тонкий ободок чеканки серебряного талера + 8 засечек
    final coinRadius = s * 0.405;
    final ringPaint = Paint()
      ..color = const Color(0x24FFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = (s * 0.014).clamp(0.7, 1.5);
    canvas.drawCircle(center, coinRadius, ringPaint);

    final tickPaint = Paint()
      ..color = const Color(0x36FFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = (s * 0.015).clamp(0.7, 1.6);

    final tickInner = s * 0.395;
    final tickOuter = s * 0.435;
    for (var i = 0; i < 8; i++) {
      final angle = (math.pi / 8) + (i * math.pi / 4);
      final cosA = math.cos(angle);
      final sinA = math.sin(angle);
      canvas.drawLine(
        Offset(center.dx + cosA * tickInner, center.dy + sinA * tickInner),
        Offset(center.dx + cosA * tickOuter, center.dy + sinA * tickOuter),
        tickPaint,
      );
    }

    // 3. Геометрическая серебристая монограмма «T» с заострённым крылом
    final tPath = Path()
      ..moveTo(0.25 * s, 0.36 * s)
      ..lineTo(0.77 * s, 0.30 * s)
      ..lineTo(0.64 * s, 0.45 * s)
      ..lineTo(0.55 * s, 0.45 * s)
      ..lineTo(0.53 * s, 0.73 * s)
      ..quadraticBezierTo(0.485 * s, 0.755 * s, 0.44 * s, 0.73 * s)
      ..lineTo(0.44 * s, 0.45 * s)
      ..lineTo(0.28 * s, 0.45 * s)
      ..close();

    canvas.drawPath(
      tPath,
      Paint()
        ..color = const Color(0xFFF2F2F0)
        ..style = PaintingStyle.fill,
    );

    // 4. Спокойная индиго-грань сгиба (#7C76D6)
    final foldPath = Path()
      ..moveTo(0.46 * s, 0.45 * s)
      ..lineTo(0.77 * s, 0.30 * s)
      ..lineTo(0.55 * s, 0.54 * s)
      ..lineTo(0.55 * s, 0.45 * s)
      ..close();

    canvas.drawPath(
      foldPath,
      Paint()
        ..color = const Color(0xFF7C76D6)
        ..style = PaintingStyle.fill,
    );

    final creasePath = Path()
      ..moveTo(0.46 * s, 0.45 * s)
      ..lineTo(0.77 * s, 0.30 * s)
      ..lineTo(0.64 * s, 0.45 * s)
      ..close();

    canvas.drawPath(
      creasePath,
      Paint()
        ..color = const Color(0xFFA7A2EC)
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(covariant _TalerLogoPainter oldDelegate) =>
      oldDelegate.circular != circular;
}

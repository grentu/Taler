import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

/// Векторный логотип мессенджера Taler: серебряный кант талера в градиенте
/// Telegram Blue с геометрической монограммой «T», переходящей в крыло
/// бумажного самолётика.
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
    final badgeSize = (size * 0.32).clamp(12.0, 28.0);

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
                  color: const Color(0xFF4ECC5E),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    width: (size * 0.032).clamp(1.5, 3.0),
                  ),
                ),
                child: Icon(
                  Icons.shield_rounded,
                  size: badgeSize * 0.58,
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

    // 1. Внешний силуэт (круг или мягкий сквиркл) с градиентом Telegram Blue
    final bgGradient = const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Color(0xFF37AEE2),
        Color(0xFF2AABEE),
        Color(0xFF229ED9),
      ],
      stops: [0.0, 0.45, 1.0],
    ).createShader(rect);

    final bgPaint = Paint()..shader = bgGradient;

    if (circular) {
      canvas.drawCircle(center, s / 2, bgPaint);
    } else {
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(s * 0.28)),
        bgPaint,
      );
    }

    // 2. Тонкий внутренний кант серебряного талера + 8 монетных засечек
    final coinRadius = s * 0.415;
    final ringPaint = Paint()
      ..color = const Color(0x38FFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = (s * 0.018).clamp(0.8, 2.0);
    canvas.drawCircle(center, coinRadius, ringPaint);

    final tickPaint = Paint()
      ..color = const Color(0x47FFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = (s * 0.017).clamp(0.8, 1.8);

    final tickInner = s * 0.405;
    final tickOuter = s * 0.448;
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

    // 3. Геометрическая белая монограмма «T» с заострённым правым крылом-самолётиком
    final tPath = Path()
      ..moveTo(0.24 * s, 0.35 * s)
      ..lineTo(0.79 * s, 0.29 * s)
      ..lineTo(0.65 * s, 0.45 * s)
      ..lineTo(0.55 * s, 0.45 * s)
      ..lineTo(0.53 * s, 0.74 * s)
      ..quadraticBezierTo(0.48 * s, 0.765 * s, 0.43 * s, 0.74 * s)
      ..lineTo(0.43 * s, 0.45 * s)
      ..lineTo(0.27 * s, 0.45 * s)
      ..close();

    // Мягкая тень под белым знаком на крупных размерах
    if (s >= 40) {
      canvas.drawPath(
        tPath.shift(Offset(0, s * 0.018)),
        Paint()..color = const Color(0x280B3B5E),
      );
    }

    canvas.drawPath(
      tPath,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill,
    );

    // 4. Двухтоновая теневая грань сгиба бумажного самолётика (#1A7DB8)
    final foldShadowPath = Path()
      ..moveTo(0.46 * s, 0.45 * s)
      ..lineTo(0.79 * s, 0.29 * s)
      ..lineTo(0.55 * s, 0.54 * s)
      ..lineTo(0.55 * s, 0.45 * s)
      ..close();

    canvas.drawPath(
      foldShadowPath,
      Paint()
        ..color = const Color(0xCC1A7DB8)
        ..style = PaintingStyle.fill,
    );

    // Светлый подгиб крыла поверх сгиба для объёма (как у крыла Telegram)
    final wingCreasePath = Path()
      ..moveTo(0.46 * s, 0.45 * s)
      ..lineTo(0.79 * s, 0.29 * s)
      ..lineTo(0.65 * s, 0.45 * s)
      ..close();

    canvas.drawPath(
      wingCreasePath,
      Paint()
        ..color = const Color(0xFFD5EEFC)
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(covariant _TalerLogoPainter oldDelegate) =>
      oldDelegate.circular != circular;
}

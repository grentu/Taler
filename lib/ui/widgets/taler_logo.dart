import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import '../icons/taler_icon.dart';

/// Векторный градиентный логотип Taler: сапфирово-индиговый градиент с
/// мягким световым бликом, тонким кольцом талера и скульптурной монограммой «T».
class TalerLogo extends StatelessWidget {
  final double size;
  final bool showShieldBadge;
  final bool circular;

  const TalerLogo({
    super.key,
    this.size = 48,
    this.showShieldBadge = false,
    this.circular = false,
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
                  color: const Color(0xFF22C55E),
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

  static Path _buildRoundedPolygon(
    List<Offset> pts,
    List<double> radii,
  ) {
    final path = Path();
    final n = pts.length;
    for (var i = 0; i < n; i++) {
      final prev = pts[(i - 1 + n) % n];
      final curr = pts[i];
      final next = pts[(i + 1) % n];
      final r = radii[i];

      final v1 = prev - curr;
      final v2 = next - curr;
      final l1 = v1.distance;
      final l2 = v2.distance;
      if (l1 < 1e-4 || l2 < 1e-4 || r <= 0) {
        if (i == 0) {
          path.moveTo(curr.dx, curr.dy);
        } else {
          path.lineTo(curr.dx, curr.dy);
        }
        continue;
      }
      final d = math.min(r, math.min(l1, l2) * 0.45);
      final a = curr + v1 * (d / l1);
      final b = curr + v2 * (d / l2);
      if (i == 0) {
        path.moveTo(a.dx, a.dy);
      } else {
        path.lineTo(a.dx, a.dy);
      }
      path.quadraticBezierTo(curr.dx, curr.dy, b.dx, b.dy);
    }
    path.close();
    return path;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final rect = Offset.zero & size;
    final center = Offset(s / 2, s / 2);

    canvas.save();
    if (circular) {
      canvas.clipPath(Path()..addOval(rect));
    } else {
      canvas.clipRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(s * 0.24)),
      );
    }

    // 1. Многоступенчатый диагональный градиент (sky cyan -> Taler blue -> electric indigo -> midnight)
    final bgShader = const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      stops: [0.0, 0.30, 0.66, 1.0],
      colors: [
        Color(0xFF38BDF8),
        Color(0xFF2576FF),
        Color(0xFF4F46E5),
        Color(0xFF181242),
      ],
    ).createShader(rect);
    canvas.drawRect(rect, Paint()..shader = bgShader);

    // 2. Мягкий верхне-левый световой блик и нижне-правая глубина
    final topGlow = RadialGradient(
      center: const Alignment(-0.72, -0.80),
      radius: 1.1,
      colors: [
        const Color(0x47BAE6FD),
        const Color(0x00BAE6FD),
      ],
    ).createShader(rect);
    canvas.drawRect(rect, Paint()..shader = topGlow);

    final bottomGlow = RadialGradient(
      center: const Alignment(0.80, 0.76),
      radius: 0.95,
      colors: [
        const Color(0x3D7C3AED),
        const Color(0x007C3AED),
      ],
    ).createShader(rect);
    canvas.drawRect(rect, Paint()..shader = bottomGlow);

    // 3. Деликатное чеканное кольцо талера
    final ringPaint = Paint()
      ..color = const Color(0x1EFFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = (s * 0.013).clamp(0.75, 1.8);
    canvas.drawCircle(center, s * 0.39, ringPaint);

    // 4. Скульптурная двухчастная монограмма «T» с параллельным диагональным срезом
    Offset pt(double nx, double ny, [double dy = 0]) =>
        Offset(nx * s, (ny + dy) * s);

    Path buildMainPath([double dy = 0]) => _buildRoundedPolygon(
          [
            pt(0.214, 0.282, dy),
            pt(0.602, 0.282, dy),
            pt(0.566, 0.402, dy),
            pt(0.566, 0.776, dy),
            pt(0.432, 0.776, dy),
            pt(0.432, 0.414, dy),
            pt(0.246, 0.414, dy),
          ],
          [
            0.052 * s,
            0.028 * s,
            0.044 * s,
            0.067 * s,
            0.067 * s,
            0.044 * s,
            0.052 * s,
          ],
        );

    Path buildWingPath([double dy = 0]) => _buildRoundedPolygon(
          [
            pt(0.648, 0.282, dy),
            pt(0.790, 0.282, dy),
            pt(0.752, 0.414, dy),
            pt(0.610, 0.414, dy),
          ],
          [
            0.028 * s,
            0.052 * s,
            0.052 * s,
            0.028 * s,
          ],
        );

    // Мягкая тень глубины под монограммой
    final shadowPaint = Paint()
      ..color = const Color(0x3D0A0C30)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, (s * 0.028).clamp(1.0, 6.0));
    canvas.drawPath(buildMainPath(0.022), shadowPaint);
    canvas.drawPath(buildWingPath(0.022), shadowPaint);

    // Основной белый контур + морозно-голубое правое крыло
    canvas.drawPath(
      buildMainPath(),
      Paint()..color = const Color(0xFFFFFFFF),
    );
    canvas.drawPath(
      buildWingPath(),
      Paint()..color = const Color(0xECE0F4FF),
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _TalerLogoPainter oldDelegate) =>
      oldDelegate.circular != circular;
}

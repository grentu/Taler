import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import 'taler_icon_data.dart';

export 'taler_icon_data.dart';
export 'taler_icons.dart';

/// Vector icon widget backed by multi-layer Solar paths with spring glyph morphing.
class TalerIcon extends StatefulWidget {
  final TalerIconData? icon;
  final double? size;
  final Color? color;

  /// Optional stroke width multiplier baseline (24x24 box).
  /// When null, each icon uses its native Solar stroke weight (typically 1.67–2.0).
  final double? strokeWidth;
  final String? semanticLabel;

  /// Set to false to swap glyphs without the morph animation.
  final bool morph;

  /// Adds a subtle interior tint on pure stroke-only icons when true.
  final bool duotone;

  const TalerIcon(
    this.icon, {
    super.key,
    this.size,
    this.color,
    this.strokeWidth,
    this.semanticLabel,
    this.morph = true,
    this.duotone = false,
  });

  /// Draws [icon] inside a 24x24 logical canvas coordinate space.
  static void paintIconLayers(
    Canvas canvas,
    TalerIconData icon, {
    required Color color,
    double scale = 1.0,
    double? strokeOverride,
    bool duotone = false,
  }) {
    final layers = icon.layers;
    final paths = icon.layerPaths;
    for (var i = 0; i < layers.length; i++) {
      final layer = layers[i];
      final path = paths[i];
      final layerColor = color.withValues(alpha: color.a * layer.opacity);
      if (layer.isFill) {
        canvas.drawPath(
          path,
          Paint()
            ..color = layerColor
            ..style = PaintingStyle.fill
            ..isAntiAlias = true,
        );
      } else {
        final baseSw = strokeOverride != null && layer.strokeWidth != null
            ? layer.strokeWidth! * (strokeOverride / 1.85)
            : (strokeOverride ?? layer.strokeWidth ?? 1.67);
        final pixelStroke = math.max(1.15, baseSw * scale);
        if (duotone) {
          final fillPath = Path.from(path)..fillType = PathFillType.evenOdd;
          canvas.drawPath(
            fillPath,
            Paint()
              ..color = layerColor.withValues(alpha: layerColor.a * 0.20)
              ..style = PaintingStyle.fill
              ..isAntiAlias = true,
          );
        }
        canvas.drawPath(
          path,
          Paint()
            ..color = layerColor
            ..style = PaintingStyle.stroke
            ..strokeWidth = pixelStroke / scale
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..isAntiAlias = true,
        );
      }
    }
  }

  @override
  State<TalerIcon> createState() => _TalerIconState();
}

class _TalerIconState extends State<TalerIcon>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;
  TalerIconData? _from;

  static const Duration _morphDuration = Duration(milliseconds: 520);

  @override
  void didUpdateWidget(covariant TalerIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = widget.icon;
    final prev = oldWidget.icon;
    if (next == prev || !widget.morph || next == null || prev == null) {
      return;
    }
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduceMotion) return;
    _from = prev;
    final controller = _controller ??= AnimationController(
      vsync: this,
      duration: _morphDuration,
    )..addListener(_onTick);
    controller.forward(from: 0);
  }

  void _onTick() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final iconTheme = IconTheme.of(context);
    final size = widget.size ?? iconTheme.size ?? 24;
    var color = widget.color ?? iconTheme.color ?? const Color(0xFF888888);
    final opacity = iconTheme.opacity;
    if (opacity != null && opacity < 1) {
      color = color.withValues(alpha: color.a * opacity);
    }
    final controller = _controller;
    final animating = controller != null && controller.isAnimating;
    final t = animating ? const _SpringCurve().transform(controller.value) : 1.0;

    Widget result = SizedBox.square(
      dimension: size,
      child: widget.icon == null
          ? null
          : CustomPaint(
              painter: _TalerIconPainter(
                from: animating ? _from : null,
                to: widget.icon!,
                t: t,
                color: color,
                strokeOverride: widget.strokeWidth,
                duotone: widget.duotone,
              ),
            ),
    );

    final label = widget.semanticLabel;
    if (label != null) {
      result = Semantics(label: label, child: ExcludeSemantics(child: result));
    } else {
      result = ExcludeSemantics(child: result);
    }
    return result;
  }
}

/// Under-damped spring (stiffness ~ 180, damping ratio ~ 0.62) as a curve.
class _SpringCurve extends Curve {
  const _SpringCurve();

  static const double _zeta = 0.62;
  static const double _omega = 13.0;
  static const double _seconds = 0.52;

  @override
  double transformInternal(double t) {
    final omegaD = _omega * math.sqrt(1 - _zeta * _zeta);
    final s = t * _seconds;
    final decay = math.exp(-_zeta * _omega * s);
    return 1 -
        decay *
            (math.cos(omegaD * s) +
                (_zeta * _omega / omegaD) * math.sin(omegaD * s));
  }
}

class _Contour {
  final List<Offset> points;
  final bool closed;
  final double length;

  const _Contour(this.points, this.closed, this.length);

  Offset get centroid {
    var x = 0.0;
    var y = 0.0;
    for (final p in points) {
      x += p.dx;
      y += p.dy;
    }
    return Offset(x / points.length, y / points.length);
  }
}

/// Resamples icons into point lists so any glyph can flow into any other.
class _MorphGeometry {
  static const int samples = 48;
  static final Map<String, List<_Contour>> _cache = <String, List<_Contour>>{};

  static List<_Contour> contoursOf(TalerIconData icon) {
    return _cache.putIfAbsent(icon.name, () {
      final contours = <_Contour>[];
      for (final metric in icon.path.computeMetrics()) {
        final len = metric.length;
        if (len <= 0) continue;
        final points = <Offset>[];
        final divisor = metric.isClosed ? samples : samples - 1;
        for (var i = 0; i < samples; i++) {
          final tangent = metric.getTangentForOffset(len * i / divisor);
          if (tangent != null) points.add(tangent.position);
        }
        if (points.isNotEmpty) {
          contours.add(_Contour(points, metric.isClosed, len));
        }
      }
      contours.sort((a, b) => b.length.compareTo(a.length));
      return contours;
    });
  }

  /// Rotates/reverses a closed contour so its points line up with [ref].
  static List<Offset> align(List<Offset> ref, List<Offset> pts, bool closed) {
    if (ref.length != pts.length) return pts;
    final n = pts.length;
    final candidates = <List<Offset>>[pts, pts.reversed.toList()];
    var best = pts;
    var bestCost = double.infinity;
    for (final cand in candidates) {
      final shifts = closed ? n : 1;
      for (var s = 0; s < shifts; s += closed ? 2 : 1) {
        var cost = 0.0;
        for (var i = 0; i < n; i += 3) {
          cost += (ref[i] - cand[(i + s) % n]).distanceSquared;
        }
        if (cost < bestCost) {
          bestCost = cost;
          best = s == 0 ? cand : <Offset>[for (var i = 0; i < n; i++) cand[(i + s) % n]];
        }
      }
    }
    return best;
  }
}

class _TalerIconPainter extends CustomPainter {
  final TalerIconData? from;
  final TalerIconData to;
  final double t;
  final Color color;
  final double? strokeOverride;
  final bool duotone;

  const _TalerIconPainter({
    required this.from,
    required this.to,
    required this.t,
    required this.color,
    required this.strokeOverride,
    required this.duotone,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.shortestSide / 24.0;
    if (scale <= 0) return;

    canvas.save();
    canvas.translate(
      (size.width - 24 * scale) / 2,
      (size.height - 24 * scale) / 2,
    );
    canvas.scale(scale);

    final source = from;
    if (source == null || t >= 1.0) {
      TalerIcon.paintIconLayers(
        canvas,
        to,
        color: color,
        scale: scale,
        strokeOverride: strokeOverride,
        duotone: duotone,
      );
    } else {
      final morphed = _morphPath(source, to, t);
      final clamped = t.clamp(0.0, 1.0);
      final fillAlpha = source.hasFillLayers && to.hasFillLayers
          ? 1.0
          : (to.hasFillLayers ? clamped : (source.hasFillLayers ? 1.0 - clamped : 0.0));
      if (fillAlpha > 0.01) {
        canvas.drawPath(
          morphed,
          Paint()
            ..color = color.withValues(alpha: color.a * fillAlpha)
            ..style = PaintingStyle.fill
            ..isAntiAlias = true,
        );
      }
      final strokeAlpha = 1.0 - fillAlpha * 0.65;
      final pixelStroke = math.max(1.15, (strokeOverride ?? 1.67) * scale);
      canvas.drawPath(
        morphed,
        Paint()
          ..color = color.withValues(alpha: color.a * strokeAlpha)
          ..style = PaintingStyle.stroke
          ..strokeWidth = pixelStroke / scale
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..isAntiAlias = true,
      );
    }
    canvas.restore();
  }

  static Path _morphPath(TalerIconData a, TalerIconData b, double t) {
    final ca = _MorphGeometry.contoursOf(a);
    final cb = _MorphGeometry.contoursOf(b);
    final count = math.max(ca.length, cb.length);
    final path = Path()..fillType = PathFillType.evenOdd;
    for (var k = 0; k < count; k++) {
      final src = k < ca.length ? ca[k] : null;
      final dst = k < cb.length ? cb[k] : null;
      final List<Offset> pa;
      final List<Offset> pb;
      final bool closed;
      if (src != null && dst != null) {
        pa = src.points;
        pb = _MorphGeometry.align(pa, dst.points, dst.closed && src.closed);
        closed = t > 0.5 ? dst.closed : src.closed;
      } else if (src != null) {
        final c = src.centroid;
        pa = src.points;
        pb = List<Offset>.filled(pa.length, c);
        closed = src.closed;
      } else {
        final c = dst!.centroid;
        pb = dst.points;
        pa = List<Offset>.filled(pb.length, c);
        closed = dst.closed;
      }
      final n = math.min(pa.length, pb.length);
      for (var i = 0; i < n; i++) {
        final p = Offset.lerp(pa[i], pb[i], t)!;
        if (i == 0) {
          path.moveTo(p.dx, p.dy);
        } else {
          path.lineTo(p.dx, p.dy);
        }
      }
      if (closed) path.close();
    }
    return path;
  }

  @override
  bool shouldRepaint(covariant _TalerIconPainter old) =>
      old.to != to ||
      old.from != from ||
      old.t != t ||
      old.color != color ||
      old.strokeOverride != strokeOverride ||
      old.duotone != duotone;
}

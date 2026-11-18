import 'dart:ui' show Offset, Path, PathFillType;

/// Single vector layer inside [TalerIconData] (fill or stroke in a 24x24 box).
///
/// Commands use a compact flat list:
/// `0 = moveTo(x, y)`, `1 = lineTo(x, y)`, `2 = cubicTo(x1, y1, x2, y2, x, y)`,
/// `3 = close`.
class TalerIconLayer {
  final List<double> commands;
  final bool isFill;
  final bool evenOdd;
  final double? strokeWidth;
  final double opacity;

  const TalerIconLayer.fill(
    this.commands, {
    this.evenOdd = false,
    this.opacity = 1.0,
  })  : isFill = true,
        strokeWidth = null;

  const TalerIconLayer.stroke(
    this.commands, {
    this.strokeWidth,
    this.opacity = 1.0,
  })  : isFill = false,
        evenOdd = false;

  /// Builds a fresh [Path] from [commands] inside the 24x24 box.
  Path buildPath() {
    final path = Path()
      ..fillType = evenOdd ? PathFillType.evenOdd : PathFillType.nonZero;
    final c = commands;
    var i = 0;
    while (i < c.length) {
      final op = c[i].toInt();
      if (op == 0) {
        path.moveTo(c[i + 1], c[i + 2]);
        i += 3;
      } else if (op == 1) {
        path.lineTo(c[i + 1], c[i + 2]);
        i += 3;
      } else if (op == 2) {
        path.cubicTo(
          c[i + 1],
          c[i + 2],
          c[i + 3],
          c[i + 4],
          c[i + 5],
          c[i + 6],
        );
        i += 7;
      } else {
        path.close();
        i += 1;
      }
    }
    return path;
  }
}

/// Multi-layer vector icon described in a normalized 24x24 box.
class TalerIconData {
  final String name;
  final List<TalerIconLayer> layers;

  const TalerIconData.layered(this.name, this.layers);

  TalerIconData(String name, List<double> commands)
      : this.layered(name, <TalerIconLayer>[TalerIconLayer.stroke(commands)]);

  static final Map<String, Path> _pathCache = <String, Path>{};
  static final Map<String, List<Path>> _layerPathCache = <String, List<Path>>{};

  /// Whether at least one layer is a filled shape (as opposed to pure stroke).
  bool get hasFillLayers => layers.any((l) => l.isFill);

  /// Cached individual layer paths matching [layers]. Never mutate the returned paths.
  List<Path> get layerPaths => _layerPathCache.putIfAbsent(
        name,
        () => List<Path>.unmodifiable([for (final l in layers) l.buildPath()]),
      );

  /// Cached combined path in the 24x24 icon box (for bounds checks & morphing).
  Path get path => _pathCache.putIfAbsent(name, buildPath);

  /// Builds a combined [Path] across all [layers].
  Path buildPath() {
    final combined = Path()
      ..fillType = layers.any((l) => l.evenOdd)
          ? PathFillType.evenOdd
          : PathFillType.nonZero;
    for (final l in layers) {
      combined.addPath(l.buildPath(), Offset.zero);
    }
    return combined;
  }

  @override
  bool operator ==(Object other) => other is TalerIconData && other.name == name;

  @override
  int get hashCode => name.hashCode;

  @override
  String toString() => 'TalerIconData($name)';
}

import 'dart:ui' show Path;

/// Vector line icon described by absolute drawing commands in a 24x24 box.
///
/// Commands are a flat list: 0 = moveTo(x, y), 1 = lineTo(x, y),
/// 2 = cubicTo(x1, y1, x2, y2, x, y), 3 = close.
class TalerIconData {
  final String name;
  final List<double> commands;

  const TalerIconData(this.name, this.commands);

  static final Map<String, Path> _pathCache = <String, Path>{};

  /// Cached path in the 24x24 icon box. Never mutate the returned path.
  Path get path => _pathCache.putIfAbsent(name, buildPath);

  /// Builds a fresh path from [commands].
  Path buildPath() {
    final path = Path();
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
        path.cubicTo(c[i + 1], c[i + 2], c[i + 3], c[i + 4], c[i + 5], c[i + 6]);
        i += 7;
      } else {
        path.close();
        i += 1;
      }
    }
    return path;
  }

  @override
  bool operator ==(Object other) => other is TalerIconData && other.name == name;

  @override
  int get hashCode => name.hashCode;

  @override
  String toString() => 'TalerIconData($name)';
}

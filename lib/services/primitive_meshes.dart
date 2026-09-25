import 'dart:math' as math;
import 'dart:typed_data';

/// Triangle meshes for URDF primitives, centered at the origin like URDF
/// (cylinders along Z). 9 floats per triangle.

Float32List boxMesh(double sx, double sy, double sz) {
  final x = sx / 2, y = sy / 2, z = sz / 2;
  final v = [
    [-x, -y, -z], [x, -y, -z], [x, y, -z], [-x, y, -z],
    [-x, -y, z], [x, -y, z], [x, y, z], [-x, y, z],
  ];
  const faces = [
    [0, 2, 1], [0, 3, 2], [4, 5, 6], [4, 6, 7], [0, 1, 5], [0, 5, 4],
    [1, 2, 6], [1, 6, 5], [2, 3, 7], [2, 7, 6], [3, 0, 4], [3, 4, 7],
  ];
  return Float32List.fromList([
    for (final f in faces)
      for (final i in f) ...v[i],
  ]);
}

Float32List cylinderMesh(double r, double length, {int segments = 32}) {
  final h = length / 2;
  final out = <double>[];
  for (var i = 0; i < segments; i++) {
    final a0 = 2 * math.pi * i / segments, a1 = 2 * math.pi * (i + 1) / segments;
    final x0 = r * math.cos(a0), y0 = r * math.sin(a0);
    final x1 = r * math.cos(a1), y1 = r * math.sin(a1);
    out.addAll([x0, y0, -h, x1, y1, -h, x1, y1, h]);
    out.addAll([x0, y0, -h, x1, y1, h, x0, y0, h]);
    out.addAll([0, 0, h, x0, y0, h, x1, y1, h]);
    out.addAll([0, 0, -h, x1, y1, -h, x0, y0, -h]);
  }
  return Float32List.fromList(out);
}

Float32List sphereMesh(double r, {int rings = 16, int segments = 24}) {
  List<double> p(int ring, int seg) {
    final th = math.pi * ring / rings, ph = 2 * math.pi * seg / segments;
    return [r * math.sin(th) * math.cos(ph), r * math.sin(th) * math.sin(ph), r * math.cos(th)];
  }
  final out = <double>[];
  for (var i = 0; i < rings; i++) {
    for (var j = 0; j < segments; j++) {
      final a = p(i, j), b = p(i + 1, j), c = p(i + 1, j + 1), d = p(i, j + 1);
      out..addAll(a)..addAll(b)..addAll(c)..addAll(a)..addAll(c)..addAll(d);
    }
  }
  return Float32List.fromList(out);
}

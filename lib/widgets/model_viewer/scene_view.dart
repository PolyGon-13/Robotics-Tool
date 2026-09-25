import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// One mesh in the scene: triangles in its local frame (meters, Z-up),
/// placed in the world by a row-major 4x4 [transform].
class ScenePart {
  final Float32List tris;
  final Color color;
  final List<double> transform;
  const ScenePart(this.tris, this.color, [this.transform = identity4]);

  static const identity4 = <double>[1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1];
}

/// World-space triangles, per-triangle colors and normals, built once per
/// scene change and shared by every frame.
class SceneGeometry {
  final Float32List tris; // 9 floats per triangle, world coords
  final Float32List normals; // 3 floats per triangle
  final Int32List colors; // ARGB per triangle

  /// Per triangle: +1 if its mesh is closed with outward winding, -1 if
  /// consistently inverted, 0 if unknown (open or mixed winding).
  final Int8List orientation;
  final double cx, cy, cz, radius, minZ;

  SceneGeometry._(this.tris, this.normals, this.colors, this.orientation, this.cx, this.cy,
      this.cz, this.radius, this.minZ);

  int get triangleCount => colors.length;

  factory SceneGeometry.build(List<ScenePart> parts) {
    var n = 0;
    for (final p in parts) {
      n += p.tris.length ~/ 9;
    }
    final tris = Float32List(n * 9);
    final normals = Float32List(n * 3);
    final colors = Int32List(n);
    final orientation = Int8List(n);
    double lx = double.infinity, ly = double.infinity, lz = double.infinity;
    double hx = double.negativeInfinity, hy = double.negativeInfinity, hz = double.negativeInfinity;

    var t = 0;
    for (final p in parts) {
      final m = p.transform;
      final src = p.tris;
      final argb = p.color.toARGB32();
      final orient = _windingOf(src) * (_det3(m) < 0 ? -1 : 1);
      final first = t;
      for (var i = 0; i + 8 < src.length; i += 9, t++) {
        for (var v = 0; v < 3; v++) {
          final x = src[i + v * 3], y = src[i + v * 3 + 1], z = src[i + v * 3 + 2];
          final wx = m[0] * x + m[1] * y + m[2] * z + m[3];
          final wy = m[4] * x + m[5] * y + m[6] * z + m[7];
          final wz = m[8] * x + m[9] * y + m[10] * z + m[11];
          tris[t * 9 + v * 3] = wx;
          tris[t * 9 + v * 3 + 1] = wy;
          tris[t * 9 + v * 3 + 2] = wz;
          if (wx < lx) lx = wx;
          if (wy < ly) ly = wy;
          if (wz < lz) lz = wz;
          if (wx > hx) hx = wx;
          if (wy > hy) hy = wy;
          if (wz > hz) hz = wz;
        }
        // Normal from the vertices: files often store none or wrong ones
        final b = t * 9;
        final ax = tris[b + 3] - tris[b], ay = tris[b + 4] - tris[b + 1], az = tris[b + 5] - tris[b + 2];
        final bx = tris[b + 6] - tris[b], by = tris[b + 7] - tris[b + 1], bz = tris[b + 8] - tris[b + 2];
        var nx = ay * bz - az * by, ny = az * bx - ax * bz, nz = ax * by - ay * bx;
        final l = math.sqrt(nx * nx + ny * ny + nz * nz);
        if (l > 0) {
          nx /= l;
          ny /= l;
          nz /= l;
        }
        normals[t * 3] = nx;
        normals[t * 3 + 1] = ny;
        normals[t * 3 + 2] = nz;
        colors[t] = argb;
      }
      for (var k = first; k < t; k++) {
        orientation[k] = orient;
      }
    }
    if (!lx.isFinite) {
      lx = ly = lz = hx = hy = hz = 0;
    }
    final r = 0.5 * math.sqrt(math.pow(hx - lx, 2) + math.pow(hy - ly, 2) + math.pow(hz - lz, 2));
    return SceneGeometry._(tris, normals, colors, orientation, (lx + hx) / 2, (ly + hy) / 2,
        (lz + hz) / 2, r > 0 ? r : 1, lz);
  }

  static double _det3(List<double> m) =>
      m[0] * (m[5] * m[10] - m[6] * m[9]) -
      m[1] * (m[4] * m[10] - m[6] * m[8]) +
      m[2] * (m[4] * m[9] - m[5] * m[8]);

  /// Signed-volume test: a closed mesh wound counter-clockwise (outward
  /// normals) has a clearly positive volume; mixed or open meshes do not.
  static int _windingOf(Float32List t) {
    final n = t.length ~/ 9;
    if (n < 4) return 0;
    double ox = 0, oy = 0, oz = 0;
    for (var i = 0; i < n * 9; i += 3) {
      ox += t[i];
      oy += t[i + 1];
      oz += t[i + 2];
    }
    ox /= n * 3;
    oy /= n * 3;
    oz /= n * 3;
    double signed = 0, total = 0;
    for (var i = 0; i < n; i++) {
      final b = i * 9;
      final ax = t[b] - ox, ay = t[b + 1] - oy, az = t[b + 2] - oz;
      final bx = t[b + 3] - ox, by = t[b + 4] - oy, bz = t[b + 5] - oz;
      final cx = t[b + 6] - ox, cy = t[b + 7] - oy, cz = t[b + 8] - oz;
      final v = ax * (by * cz - bz * cy) - ay * (bx * cz - bz * cx) + az * (bx * cy - by * cx);
      signed += v;
      total += v.abs();
    }
    if (total == 0) return 0;
    final ratio = signed / total;
    return ratio > 0.8 ? 1 : ratio < -0.8 ? -1 : 0;
  }
}

/// Sort bucket for a triangle depth: 0 = farthest. [depth] is stored as
/// float32, so it can round slightly past the float64 [dMax]; the result is
/// clamped to a valid index.
int depthBucket(double depth, double dMax, double span, int buckets) =>
    span > 0 ? ((dMax - depth) / span * (buckets - 1)).floor().clamp(0, buckets - 1) : 0;

/// Orbit view of a [SceneGeometry]: drag to rotate, pinch to zoom, two
/// fingers to pan, double-tap to reset. Z is up, like RViz.
class SceneView extends StatefulWidget {
  final SceneGeometry geometry;

  /// When this changes the camera re-frames the model; joint moves keep it.
  final Object fitKey;
  final bool showGrid;

  const SceneView({
    super.key,
    required this.geometry,
    required this.fitKey,
    this.showGrid = true,
  });

  @override
  State<SceneView> createState() => SceneViewState();
}

class SceneViewState extends State<SceneView> {
  static const _defaultAzimuth = -0.6; // look at the front-left of the robot
  static const _defaultElevation = 0.45;

  double _azimuth = _defaultAzimuth, _elevation = _defaultElevation;
  double _zoom = 1;
  Offset _pan = Offset.zero;
  // Framing (center + radius) captured per fitKey
  late double _cx, _cy, _cz, _radius, _groundZ;

  double _startZoom = 1;
  Offset? _lastFocal;

  @override
  void initState() {
    super.initState();
    _frame();
  }

  @override
  void didUpdateWidget(SceneView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.fitKey != widget.fitKey) _frame();
  }

  void _frame() {
    final g = widget.geometry;
    _cx = g.cx;
    _cy = g.cy;
    _cz = g.cz;
    _radius = g.radius;
    _groundZ = g.minZ;
  }

  void resetView() => setState(() {
        _azimuth = _defaultAzimuth;
        _elevation = _defaultElevation;
        _zoom = 1;
        _pan = Offset.zero;
        _frame();
      });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onScaleStart: (d) {
        _startZoom = _zoom;
        _lastFocal = d.focalPoint;
      },
      onScaleUpdate: (d) {
        final last = _lastFocal ?? d.focalPoint;
        final delta = d.focalPoint - last;
        _lastFocal = d.focalPoint;
        setState(() {
          if (d.pointerCount >= 2) {
            _zoom = (_startZoom * d.scale).clamp(0.2, 30.0);
            _pan += delta;
          } else {
            _azimuth -= delta.dx * 0.01;
            _elevation = (_elevation + delta.dy * 0.01).clamp(-1.55, 1.55);
          }
        });
      },
      onDoubleTap: resetView,
      child: ClipRect(
        child: CustomPaint(
          size: Size.infinite,
          painter: _ScenePainter(
            g: widget.geometry,
            azimuth: _azimuth,
            elevation: _elevation,
            zoom: _zoom,
            pan: _pan,
            cx: _cx, cy: _cy, cz: _cz, radius: _radius, groundZ: _groundZ,
            showGrid: widget.showGrid,
            background: dark ? const Color(0xFF1B1D21) : const Color(0xFFE9ECF0),
            gridColor: dark ? const Color(0xFF3A3F47) : const Color(0xFFC3C9D2),
          ),
        ),
      ),
    );
  }
}

class _ScenePainter extends CustomPainter {
  final SceneGeometry g;
  final double azimuth, elevation, zoom, cx, cy, cz, radius, groundZ;
  final Offset pan;
  final bool showGrid;
  final Color background, gridColor;

  _ScenePainter({
    required this.g,
    required this.azimuth,
    required this.elevation,
    required this.zoom,
    required this.pan,
    required this.cx,
    required this.cy,
    required this.cz,
    required this.radius,
    required this.groundZ,
    required this.showGrid,
    required this.background,
    required this.gridColor,
  });

  static const _camDist = 4.0; // in model radii

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = background);
    if (size.isEmpty) return;

    // View rotation: azimuth about world Z, then elevation. The camera looks
    // along -Y' of the rotated frame; screen x = X', screen up = Z'.
    final ca = math.cos(azimuth), sa = math.sin(azimuth);
    final ce = math.cos(elevation), se = math.sin(elevation);
    final inv = 1 / radius;
    final focal = math.min(size.width, size.height) * 0.42 * _camDist * zoom;
    final ox = size.width / 2 + pan.dx, oy = size.height / 2 + pan.dy;

    // world → (screen x, screen y, depth); depth grows away from the camera
    double sx = 0, sy = 0, depth = 0;
    void project(double x, double y, double z) {
      x = (x - cx) * inv;
      y = (y - cy) * inv;
      z = (z - cz) * inv;
      final x1 = ca * x - sa * y;
      final y1 = sa * x + ca * y;
      final y2 = ce * y1 - se * z; // toward/away from camera
      final z2 = se * y1 + ce * z; // up on screen
      final d = y2 + _camDist;
      final k = focal / (d < 0.05 ? 0.05 : d);
      sx = ox + x1 * k;
      sy = oy - z2 * k;
      depth = y2;
    }

    if (showGrid) _grid(canvas, project, () => (sx, sy));

    final n = g.triangleCount;
    if (n == 0) return;
    final pos = Float32List(n * 6);
    final dep = Float32List(n);
    final back = Uint8List(n);
    final nrm = g.normals;
    final orient = g.orientation;
    double dMin = double.infinity, dMax = double.negativeInfinity;
    final t = g.tris;
    for (var i = 0; i < n; i++) {
      var dsum = 0.0;
      for (var v = 0; v < 3; v++) {
        final b = i * 9 + v * 3;
        project(t[b], t[b + 1], t[b + 2]);
        pos[i * 6 + v * 2] = sx;
        pos[i * 6 + v * 2 + 1] = sy;
        dsum += depth;
      }
      dep[i] = dsum;
      if (dsum < dMin) dMin = dsum;
      if (dsum > dMax) dMax = dsum;
      // Faces of closed meshes that point away from the camera are drawn
      // first, so they can never cover front faces.
      final o = orient[i];
      if (o != 0) {
        final ny1 = sa * nrm[i * 3] + ca * nrm[i * 3 + 1];
        final towardCam = -(ce * ny1 - se * nrm[i * 3 + 2]) * o;
        if (towardCam < 0) back[i] = 1;
      }
    }

    // Painter's algorithm with a counting sort on quantized depth: far first
    const buckets = 4096; // per group: back faces, then front faces
    final span = dMax - dMin;
    final key = Int32List(n);
    final count = Int32List(2 * buckets + 1);
    for (var i = 0; i < n; i++) {
      var k = depthBucket(dep[i], dMax, span, buckets);
      if (back[i] == 0) k += buckets;
      key[i] = k;
      count[k + 1]++;
    }
    for (var b = 0; b < 2 * buckets; b++) {
      count[b + 1] += count[b];
    }
    final order = Int32List(n);
    for (var i = 0; i < n; i++) {
      order[count[key[i]]++] = i;
    }

    // Two-sided headlight shading from the upper left of the camera
    const lx = -0.35, ly = -0.75, lz = 0.55; // in rotated frame
    final outPos = Float32List(n * 6);
    final outCol = Int32List(n * 3);
    for (var j = 0; j < n; j++) {
      final i = order[j];
      final nx = nrm[i * 3], ny = nrm[i * 3 + 1], nz = nrm[i * 3 + 2];
      final nx1 = ca * nx - sa * ny;
      final ny1 = sa * nx + ca * ny;
      final ny2 = ce * ny1 - se * nz;
      final nz2 = se * ny1 + ce * nz;
      final lambert = (nx1 * lx + ny2 * ly + nz2 * lz).abs();
      final shade = 0.38 + 0.62 * lambert;
      final c = g.colors[i];
      final r = (((c >> 16) & 0xFF) * shade).round();
      final gg = (((c >> 8) & 0xFF) * shade).round();
      final bb = ((c & 0xFF) * shade).round();
      final argb = (0xFF << 24) | (r << 16) | (gg << 8) | bb;
      for (var k = 0; k < 6; k++) {
        outPos[j * 6 + k] = pos[i * 6 + k];
      }
      outCol[j * 3] = outCol[j * 3 + 1] = outCol[j * 3 + 2] = argb;
    }
    canvas.drawVertices(
      ui.Vertices.raw(ui.VertexMode.triangles, outPos, colors: outCol),
      BlendMode.dst,
      Paint(),
    );

    _axes(canvas, size);
  }

  /// Ground grid under the model with 1-2-5 spacing.
  void _grid(Canvas canvas, void Function(double, double, double) project,
      (double, double) Function() read) {
    final extent = radius * 1.6;
    final raw = extent / 5;
    final e = math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
    final f = raw / e;
    final step = (f <= 1 ? 1 : f <= 2 ? 2 : f <= 5 ? 5 : 10) * e;
    final paint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    final x0 = ((cx - extent) / step).floorToDouble() * step;
    final y0 = ((cy - extent) / step).floorToDouble() * step;
    for (var x = x0; x <= cx + extent; x += step) {
      project(x, cy - extent, groundZ);
      final a = read();
      project(x, cy + extent, groundZ);
      final b = read();
      canvas.drawLine(Offset(a.$1, a.$2), Offset(b.$1, b.$2), paint);
    }
    for (var y = y0; y <= cy + extent; y += step) {
      project(cx - extent, y, groundZ);
      final a = read();
      project(cx + extent, y, groundZ);
      final b = read();
      canvas.drawLine(Offset(a.$1, a.$2), Offset(b.$1, b.$2), paint);
    }
  }

  /// X/Y/Z gizmo in the top-right corner (RViz colors).
  void _axes(Canvas canvas, Size size) {
    final ca = math.cos(azimuth), sa = math.sin(azimuth);
    final ce = math.cos(elevation), se = math.sin(elevation);
    final o = Offset(size.width - 34, 34);
    for (final (label, v, color) in [
      ('X', [1.0, 0.0, 0.0], const Color(0xFFE53935)),
      ('Y', [0.0, 1.0, 0.0], const Color(0xFF43A047)),
      ('Z', [0.0, 0.0, 1.0], const Color(0xFF1E88E5)),
    ]) {
      final x1 = ca * v[0] - sa * v[1];
      final y1 = sa * v[0] + ca * v[1];
      final z2 = se * y1 + ce * v[2];
      final end = o + Offset(x1, -z2) * 22;
      canvas.drawLine(o, end, Paint()
        ..color = color
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round);
      final tp = TextPainter(
        text: TextSpan(text: label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, end + Offset(x1 >= 0 ? 2 : -tp.width - 2, -tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(covariant _ScenePainter old) =>
      old.g != g ||
      old.azimuth != azimuth ||
      old.elevation != elevation ||
      old.zoom != zoom ||
      old.pan != pan ||
      old.radius != radius ||
      old.background != background;
}

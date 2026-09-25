import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Color;

import 'package:xml/xml.dart';

/// Triangles in a flat list: 9 floats (x0 y0 z0 x1 y1 z1 x2 y2 z2) each.
/// Coordinates are in meters, Z-up (ROS convention).
class TriMesh {
  final Float32List tris;

  /// Color from the file (COLLADA material), if any.
  final Color? color;

  const TriMesh(this.tris, {this.color});

  int get triangleCount => tris.length ~/ 9;
}

/// Parses binary or ASCII STL. STL has no units; values are returned as is
/// (URDF `<mesh scale>` handles mm files).
TriMesh parseStl(Uint8List bytes) {
  return _isBinaryStl(bytes) ? _parseBinaryStl(bytes) : _parseAsciiStl(bytes);
}

bool _isBinaryStl(Uint8List bytes) {
  if (bytes.length < 84) return false;
  final view = ByteData.sublistView(bytes);
  final count = view.getUint32(80, Endian.little);
  // Size check first: binary files may also start with "solid"
  if (84 + count * 50 == bytes.length) return true;
  final head = String.fromCharCodes(bytes.sublist(0, math.min(bytes.length, 512)));
  return !(head.trimLeft().startsWith('solid') && head.contains('facet'));
}

TriMesh _parseBinaryStl(Uint8List bytes) {
  final view = ByteData.sublistView(bytes);
  final declared = view.getUint32(80, Endian.little);
  final count = math.min(declared, (bytes.length - 84) ~/ 50);
  final out = Float32List(count * 9);
  for (var i = 0; i < count; i++) {
    final o = 84 + i * 50 + 12; // skip the stored normal
    for (var k = 0; k < 9; k++) {
      out[i * 9 + k] = view.getFloat32(o + k * 4, Endian.little);
    }
  }
  return TriMesh(out);
}

TriMesh _parseAsciiStl(Uint8List bytes) {
  final text = String.fromCharCodes(bytes);
  final values = <double>[];
  final vertex = RegExp(r'vertex\s+(\S+)\s+(\S+)\s+(\S+)');
  for (final m in vertex.allMatches(text)) {
    values
      ..add(double.tryParse(m.group(1)!) ?? 0)
      ..add(double.tryParse(m.group(2)!) ?? 0)
      ..add(double.tryParse(m.group(3)!) ?? 0);
  }
  final usable = values.length - values.length % 9;
  return TriMesh(Float32List.fromList(values.sublist(0, usable)));
}

// ─── COLLADA (.dae) ──────────────────────────────────────────────────────────

/// Parses the triangle geometry of a COLLADA file into meshes (one per
/// geometry instance and material), applying node transforms, `<unit>` and
/// `<up_axis>` so the result is in meters, Z-up.
///
/// Supports `<triangles>` and `<polylist>`/`<polygons>` (fan-triangulated)
/// and diffuse material colors. Textures are ignored.
List<TriMesh> parseDae(String xmlText) {
  final doc = XmlDocument.parse(xmlText);
  final root = doc.rootElement;

  final unit = double.tryParse(
          _first(root, 'unit')?.getAttribute('meter') ?? '') ??
      1.0;
  final upAxis = (_first(root, 'up_axis')?.innerText ?? 'Y_UP').trim();

  final colors = _daeMaterialColors(root);

  // geometry id → list of (triangles, material symbol)
  final geometries = <String, List<(Float32List, String?)>>{};
  for (final g in root.findAllElements('geometry')) {
    final id = g.getAttribute('id');
    final mesh = _child(g, 'mesh');
    if (id == null || mesh == null) continue;
    geometries[id] = _daeMeshTriangles(mesh);
  }

  final out = <TriMesh>[];

  void emit(String geomId, List<double> m, Map<String, String> bind) {
    for (final (tris, symbol) in geometries[geomId] ?? const <(Float32List, String?)>[]) {
      final t = Float32List(tris.length);
      for (var i = 0; i < tris.length; i += 3) {
        var x = tris[i], y = tris[i + 1], z = tris[i + 2];
        // node transform (row-major 4x4)
        final tx = m[0] * x + m[1] * y + m[2] * z + m[3];
        final ty = m[4] * x + m[5] * y + m[6] * z + m[7];
        final tz = m[8] * x + m[9] * y + m[10] * z + m[11];
        x = tx * unit;
        y = ty * unit;
        z = tz * unit;
        switch (upAxis) {
          case 'Y_UP': // rotate +90° about X: Y becomes Z
            (x, y, z) = (x, -z, y);
          case 'X_UP': // X becomes Z
            (x, y, z) = (-y, z, x);
          default:
            break;
        }
        t[i] = x;
        t[i + 1] = y;
        t[i + 2] = z;
      }
      final material = symbol == null ? null : (bind[symbol] ?? symbol);
      out.add(TriMesh(t, color: material == null ? null : colors[material]));
    }
  }

  void walk(XmlElement node, List<double> parent) {
    final m = _mul(parent, _daeNodeMatrix(node));
    for (final ig in node.findElements('instance_geometry')) {
      final url = (ig.getAttribute('url') ?? '').replaceFirst('#', '');
      final bind = <String, String>{
        for (final im in ig.findAllElements('instance_material'))
          if (im.getAttribute('symbol') != null)
            im.getAttribute('symbol')!: (im.getAttribute('target') ?? '').replaceFirst('#', ''),
      };
      emit(url, m, bind);
    }
    for (final child in node.findElements('node')) {
      walk(child, m);
    }
  }

  final scene = _first(root, 'visual_scene');
  if (scene != null) {
    for (final n in scene.findElements('node')) {
      walk(n, _identity);
    }
  }
  // No scene graph: show every geometry once
  if (out.isEmpty) {
    for (final id in geometries.keys) {
      emit(id, _identity, const {});
    }
  }
  return out;
}

const _identity = <double>[1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1];

XmlElement? _first(XmlElement root, String name) {
  final it = root.findAllElements(name);
  return it.isEmpty ? null : it.first;
}

XmlElement? _child(XmlElement e, String name) {
  final it = e.findElements(name);
  return it.isEmpty ? null : it.first;
}

List<double> _floats(String s) => s
    .trim()
    .split(RegExp(r'\s+'))
    .where((t) => t.isNotEmpty)
    .map((t) => double.tryParse(t) ?? 0)
    .toList();

List<int> _ints(String s) => s
    .trim()
    .split(RegExp(r'\s+'))
    .where((t) => t.isNotEmpty)
    .map((t) => int.tryParse(t) ?? 0)
    .toList();

List<(Float32List, String?)> _daeMeshTriangles(XmlElement mesh) {
  // source id → (floats, stride)
  final sources = <String, (List<double>, int)>{};
  for (final src in mesh.findElements('source')) {
    final id = src.getAttribute('id');
    final fa = _child(src, 'float_array');
    if (id == null || fa == null) continue;
    final acc = src.findAllElements('accessor');
    final stride = acc.isEmpty ? 3 : int.tryParse(acc.first.getAttribute('stride') ?? '') ?? 3;
    sources[id] = (_floats(fa.innerText), stride);
  }
  // <vertices id> → its POSITION source
  final vertices = <String, String>{};
  for (final v in mesh.findElements('vertices')) {
    for (final input in v.findElements('input')) {
      if (input.getAttribute('semantic') == 'POSITION') {
        vertices[v.getAttribute('id') ?? ''] = (input.getAttribute('source') ?? '').replaceFirst('#', '');
      }
    }
  }

  final result = <(Float32List, String?)>[];
  for (final prim in mesh.childElements) {
    final kind = prim.name.local;
    if (kind != 'triangles' && kind != 'polylist' && kind != 'polygons') continue;
    final inputs = prim.findElements('input').toList();
    if (inputs.isEmpty) continue;
    var stride = 0;
    int? posOffset;
    String? posSource;
    for (final input in inputs) {
      final offset = int.tryParse(input.getAttribute('offset') ?? '0') ?? 0;
      stride = math.max(stride, offset + 1);
      final sem = input.getAttribute('semantic');
      final src = (input.getAttribute('source') ?? '').replaceFirst('#', '');
      if (sem == 'VERTEX') {
        posOffset = offset;
        posSource = vertices[src] ?? src;
      } else if (sem == 'POSITION') {
        posOffset = offset;
        posSource = src;
      }
    }
    final positions = sources[posSource];
    if (posOffset == null || positions == null) continue;
    final (pos, pstride) = positions;

    // Polygons as lists of vertex (position) indices
    final polys = <List<int>>[];
    if (kind == 'polygons') {
      for (final p in prim.findElements('p')) {
        final idx = _ints(p.innerText);
        polys.add([for (var i = posOffset; i < idx.length; i += stride) idx[i]]);
      }
    } else {
      final pEl = _child(prim, 'p');
      if (pEl == null) continue;
      final idx = _ints(pEl.innerText);
      final vcount = kind == 'polylist' ? _ints(_child(prim, 'vcount')?.innerText ?? '') : null;
      var cursor = 0;
      final n = idx.length ~/ stride;
      if (vcount == null) {
        for (var v = 0; v + 2 < n; v += 3) {
          polys.add([for (var k = 0; k < 3; k++) idx[(v + k) * stride + posOffset]]);
        }
      } else {
        for (final c in vcount) {
          if (cursor + c > n) break;
          polys.add([for (var k = 0; k < c; k++) idx[(cursor + k) * stride + posOffset]]);
          cursor += c;
        }
      }
    }

    final tris = <double>[];
    void addVertex(int i) {
      final b = i * pstride;
      if (b + 2 >= pos.length) {
        tris..add(0)..add(0)..add(0);
      } else {
        tris..add(pos[b])..add(pos[b + 1])..add(pos[b + 2]);
      }
    }
    for (final poly in polys) {
      for (var k = 1; k + 1 < poly.length; k++) {
        addVertex(poly[0]);
        addVertex(poly[k]);
        addVertex(poly[k + 1]);
      }
    }
    result.add((Float32List.fromList(tris), prim.getAttribute('material')));
  }
  return result;
}

/// material id → diffuse color (through material → instance_effect → effect).
Map<String, Color> _daeMaterialColors(XmlElement root) {
  final effectColors = <String, Color>{};
  for (final effect in root.findAllElements('effect')) {
    final id = effect.getAttribute('id');
    final diffuse = effect.findAllElements('diffuse');
    if (id == null || diffuse.isEmpty) continue;
    final colorEl = diffuse.first.findElements('color');
    if (colorEl.isEmpty) continue;
    final c = _floats(colorEl.first.innerText);
    if (c.length < 3) continue;
    int ch(double v) => (v.clamp(0.0, 1.0) * 255).round();
    effectColors[id] = Color.fromARGB(255, ch(c[0]), ch(c[1]), ch(c[2]));
  }
  final out = <String, Color>{};
  for (final mat in root.findAllElements('material')) {
    final id = mat.getAttribute('id');
    final ie = mat.findElements('instance_effect');
    if (id == null || ie.isEmpty) continue;
    final effect = (ie.first.getAttribute('url') ?? '').replaceFirst('#', '');
    final c = effectColors[effect];
    if (c != null) out[id] = c;
  }
  return out;
}

/// A node's local transform as a row-major 4x4 matrix.
List<double> _daeNodeMatrix(XmlElement node) {
  var m = _identity;
  for (final t in node.childElements) {
    final v = _floats(t.innerText);
    switch (t.name.local) {
      case 'matrix' when v.length >= 16:
        m = _mul(m, v.sublist(0, 16));
      case 'translate' when v.length >= 3:
        m = _mul(m, [1, 0, 0, v[0], 0, 1, 0, v[1], 0, 0, 1, v[2], 0, 0, 0, 1]);
      case 'scale' when v.length >= 3:
        m = _mul(m, [v[0], 0, 0, 0, 0, v[1], 0, 0, 0, 0, v[2], 0, 0, 0, 0, 1]);
      case 'rotate' when v.length >= 4:
        m = _mul(m, _axisAngle(v[0], v[1], v[2], v[3] * math.pi / 180));
    }
  }
  return m;
}

List<double> _axisAngle(double x, double y, double z, double a) {
  final l = math.sqrt(x * x + y * y + z * z);
  if (l == 0) return _identity;
  x /= l;
  y /= l;
  z /= l;
  final c = math.cos(a), s = math.sin(a), t = 1 - c;
  return [
    t * x * x + c, t * x * y - s * z, t * x * z + s * y, 0,
    t * x * y + s * z, t * y * y + c, t * y * z - s * x, 0,
    t * x * z - s * y, t * y * z + s * x, t * z * z + c, 0,
    0, 0, 0, 1,
  ];
}

List<double> _mul(List<double> a, List<double> b) {
  final r = List<double>.filled(16, 0);
  for (var i = 0; i < 4; i++) {
    for (var j = 0; j < 4; j++) {
      var s = 0.0;
      for (var k = 0; k < 4; k++) {
        s += a[i * 4 + k] * b[k * 4 + j];
      }
      r[i * 4 + j] = s;
    }
  }
  return r;
}

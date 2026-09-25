import 'dart:ui' show Color;

import 'package:xml/xml.dart';

class UrdfGeometry {
  final String type; // 'box' | 'cylinder' | 'sphere' | 'mesh'
  final double sx, sy, sz; // box size
  final double radius;     // cylinder/sphere
  final double length;     // cylinder
  final String meshFile;
  final List<double> meshScale;

  const UrdfGeometry({
    required this.type,
    this.sx = 0, this.sy = 0, this.sz = 0,
    this.radius = 0,
    this.length = 0,
    this.meshFile = '',
    this.meshScale = const [1, 1, 1],
  });

  /// File name without the package:// or directory part, lower-case, used to
  /// match a mesh reference with a file the user picked.
  String get meshKey => meshBaseName(meshFile);
}

String meshBaseName(String path) {
  final p = path.replaceAll('\\', '/');
  return p.substring(p.lastIndexOf('/') + 1).toLowerCase();
}

class UrdfOrigin {
  final double x, y, z;       // translation
  final double roll, pitch, yaw; // rotation

  const UrdfOrigin({
    this.x = 0, this.y = 0, this.z = 0,
    this.roll = 0, this.pitch = 0, this.yaw = 0,
  });

  static UrdfOrigin fromElement(XmlElement? el) {
    if (el == null) return const UrdfOrigin();
    final xyz = _parseVec3(el.getAttribute('xyz'));
    final rpy = _parseVec3(el.getAttribute('rpy'));
    return UrdfOrigin(
      x: xyz[0], y: xyz[1], z: xyz[2],
      roll: rpy[0], pitch: rpy[1], yaw: rpy[2],
    );
  }
}

class UrdfVisual {
  final UrdfOrigin origin;
  final UrdfGeometry geometry;

  /// Material color (inline or a named top-level material); null if none.
  final Color? color;

  const UrdfVisual({
    required this.origin,
    required this.geometry,
    this.color,
  });
}

class UrdfLink {
  final String name;
  final List<UrdfVisual> visuals;

  const UrdfLink({required this.name, required this.visuals});
}

class UrdfJoint {
  final String name;
  final String type; // fixed | revolute | prismatic | continuous | floating | planar
  final String parent;
  final String child;
  final UrdfOrigin origin;
  final double axisX, axisY, axisZ;
  final double limitLower;
  final double limitUpper;

  const UrdfJoint({
    required this.name,
    required this.type,
    required this.parent,
    required this.child,
    required this.origin,
    this.axisX = 1, this.axisY = 0, this.axisZ = 0,
    this.limitLower = -3.14159,
    this.limitUpper =  3.14159,
  });

  bool get isMovable => type == 'revolute' || type == 'continuous' || type == 'prismatic';
}

class UrdfRobot {
  final String name;
  final List<UrdfLink> links;
  final List<UrdfJoint> joints;

  /// The file still contains xacro macros/expressions (`${...}`, `$(...)`,
  /// `xacro:` tags), which this viewer does not evaluate.
  final bool looksLikeXacro;

  const UrdfRobot({
    required this.name,
    required this.links,
    required this.joints,
    this.looksLikeXacro = false,
  });

  /// Mesh file names (see [UrdfGeometry.meshKey]) referenced by visuals.
  Set<String> get meshKeys => {
        for (final l in links)
          for (final v in l.visuals)
            if (v.geometry.type == 'mesh' && v.geometry.meshFile.isNotEmpty) v.geometry.meshKey,
      };
}

class UrdfParserService {
  static UrdfRobot parse(String xmlText) {
    final doc = XmlDocument.parse(xmlText);
    final robot = doc.getElement('robot');
    if (robot == null) {
      throw const FormatException('No <robot> element found');
    }
    final robotName = robot.getAttribute('name') ?? 'robot';

    // Top-level <material name="..."><color rgba="..."/></material>
    final materials = <String, Color>{};
    for (final m in robot.findElements('material')) {
      final name = m.getAttribute('name');
      final c = _color(m);
      if (name != null && c != null) materials[name] = c;
    }

    final links = [
      for (final linkEl in robot.findElements('link')) _parseLink(linkEl, materials),
    ];
    final joints = [
      for (final jointEl in robot.findElements('joint')) _parseJoint(jointEl),
    ];

    final looksLikeXacro = xmlText.contains(r'${') ||
        xmlText.contains(r'$(') ||
        robot.descendants.whereType<XmlElement>().any((e) => e.name.prefix == 'xacro');

    return UrdfRobot(
      name: robotName,
      links: links,
      joints: joints,
      looksLikeXacro: looksLikeXacro,
    );
  }

  static Color? _color(XmlElement material) {
    final rgba = material.getElement('color')?.getAttribute('rgba');
    if (rgba == null) return null;
    final v = rgba.trim().split(RegExp(r'\s+')).map((s) => double.tryParse(s) ?? 0).toList();
    if (v.length < 3) return null;
    int ch(double x) => (x.clamp(0.0, 1.0) * 255).round();
    return Color.fromARGB(255, ch(v[0]), ch(v[1]), ch(v[2]));
  }

  static UrdfLink _parseLink(XmlElement el, Map<String, Color> materials) {
    final name = el.getAttribute('name') ?? 'link';
    final visuals = <UrdfVisual>[];

    for (final visEl in el.findElements('visual')) {
      final origin = UrdfOrigin.fromElement(visEl.getElement('origin'));
      final geomEl = visEl.getElement('geometry');
      if (geomEl == null) continue;

      Color? color;
      final matEl = visEl.getElement('material');
      if (matEl != null) {
        color = _color(matEl) ?? materials[matEl.getAttribute('name')];
      }
      visuals.add(UrdfVisual(origin: origin, geometry: _parseGeometry(geomEl), color: color));
    }

    return UrdfLink(name: name, visuals: visuals);
  }

  static UrdfGeometry _parseGeometry(XmlElement el) {
    final boxEl = el.getElement('box');
    if (boxEl != null) {
      final size = _parseVec3(boxEl.getAttribute('size'));
      return UrdfGeometry(type: 'box', sx: size[0], sy: size[1], sz: size[2]);
    }

    final cylEl = el.getElement('cylinder');
    if (cylEl != null) {
      return UrdfGeometry(
        type: 'cylinder',
        radius: double.tryParse(cylEl.getAttribute('radius') ?? '') ?? 0.1,
        length: double.tryParse(cylEl.getAttribute('length') ?? '') ?? 0.1,
      );
    }

    final sphEl = el.getElement('sphere');
    if (sphEl != null) {
      return UrdfGeometry(
        type: 'sphere',
        radius: double.tryParse(sphEl.getAttribute('radius') ?? '') ?? 0.1,
      );
    }

    final meshEl = el.getElement('mesh');
    if (meshEl != null) {
      final scaleAttr = meshEl.getAttribute('scale');
      return UrdfGeometry(
        type: 'mesh',
        meshFile: meshEl.getAttribute('filename') ?? '',
        meshScale: scaleAttr == null ? const [1, 1, 1] : _parseVec3(scaleAttr, fallback: 1),
      );
    }

    return const UrdfGeometry(type: 'box', sx: 0.1, sy: 0.1, sz: 0.1);
  }

  static UrdfJoint _parseJoint(XmlElement el) {
    final name = el.getAttribute('name') ?? 'joint';
    final type = el.getAttribute('type') ?? 'fixed';
    final parent = el.getElement('parent')?.getAttribute('link') ?? '';
    final child  = el.getElement('child')?.getAttribute('link') ?? '';
    final origin = UrdfOrigin.fromElement(el.getElement('origin'));

    // URDF default axis is (1, 0, 0)
    final axis = _parseVec3(el.getElement('axis')?.getAttribute('xyz') ?? '1 0 0');

    final limitEl = el.getElement('limit');
    var lower = double.tryParse(limitEl?.getAttribute('lower') ?? '');
    var upper = double.tryParse(limitEl?.getAttribute('upper') ?? '');
    // Continuous joints (and malformed limits) get a full turn
    if (type == 'continuous' || lower == null || upper == null || upper <= lower) {
      lower = type == 'prismatic' ? -0.5 : -3.14159;
      upper = type == 'prismatic' ? 0.5 : 3.14159;
    }

    return UrdfJoint(
      name: name, type: type, parent: parent, child: child, origin: origin,
      axisX: axis[0], axisY: axis[1], axisZ: axis[2],
      limitLower: lower, limitUpper: upper,
    );
  }
}

List<double> _parseVec3(String? s, {double fallback = 0}) {
  if (s == null) return [fallback, fallback, fallback];
  final parts = s.trim().split(RegExp(r'\s+'));
  return [
    for (var i = 0; i < 3; i++) double.tryParse(parts.elementAtOrNull(i) ?? '') ?? fallback,
  ];
}

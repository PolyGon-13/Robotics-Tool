import 'package:xml/xml.dart';

class UrdfGeometry {
  final String type; // 'box' | 'cylinder' | 'sphere' | 'mesh'
  final double sx, sy, sz; // box size
  final double radius;     // cylinder/sphere
  final double length;     // cylinder
  final String meshFile;

  const UrdfGeometry({
    required this.type,
    this.sx = 0, this.sy = 0, this.sz = 0,
    this.radius = 0,
    this.length = 0,
    this.meshFile = '',
  });
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

  static List<double> _parseVec3(String? s) {
    if (s == null) return [0, 0, 0];
    final parts = s.trim().split(RegExp(r'\s+'));
    return [
      double.tryParse(parts.elementAtOrNull(0) ?? '') ?? 0,
      double.tryParse(parts.elementAtOrNull(1) ?? '') ?? 0,
      double.tryParse(parts.elementAtOrNull(2) ?? '') ?? 0,
    ];
  }
}

class UrdfVisual {
  final UrdfOrigin origin;
  final UrdfGeometry geometry;
  final String materialColor; // hex or empty

  const UrdfVisual({
    required this.origin,
    required this.geometry,
    this.materialColor = '',
  });
}

class UrdfLink {
  final String name;
  final List<UrdfVisual> visuals;

  const UrdfLink({required this.name, required this.visuals});
}

class UrdfJoint {
  final String name;
  final String type; // fixed | revolute | prismatic | continuous | floating
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
    this.axisX = 0, this.axisY = 0, this.axisZ = 1,
    this.limitLower = -3.14159,
    this.limitUpper =  3.14159,
  });
}

class UrdfRobot {
  final String name;
  final List<UrdfLink> links;
  final List<UrdfJoint> joints;

  const UrdfRobot({
    required this.name,
    required this.links,
    required this.joints,
  });
}

class UrdfParserService {
  static UrdfRobot parse(String xmlText) {
    final doc = XmlDocument.parse(xmlText);
    final robot = doc.getElement('robot');
    final robotName = robot?.getAttribute('name') ?? 'robot';

    final links = <UrdfLink>[];
    final joints = <UrdfJoint>[];

    for (final linkEl in robot?.findElements('link') ?? <XmlElement>[]) {
      links.add(_parseLink(linkEl));
    }
    for (final jointEl in robot?.findElements('joint') ?? <XmlElement>[]) {
      joints.add(_parseJoint(jointEl));
    }

    return UrdfRobot(name: robotName, links: links, joints: joints);
  }

  static UrdfLink _parseLink(XmlElement el) {
    final name = el.getAttribute('name') ?? 'link';
    final visuals = <UrdfVisual>[];

    for (final visEl in el.findElements('visual')) {
      final origin = UrdfOrigin.fromElement(visEl.getElement('origin'));
      final geomEl = visEl.getElement('geometry');
      if (geomEl == null) continue;

      final geometry = _parseGeometry(geomEl);
      String matColor = '';
      final matEl = visEl.getElement('material');
      if (matEl != null) {
        final colorEl = matEl.getElement('color');
        matColor = colorEl?.getAttribute('rgba') ?? '';
      }

      visuals.add(UrdfVisual(
        origin: origin,
        geometry: geometry,
        materialColor: matColor,
      ));
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
      return UrdfGeometry(
        type: 'mesh',
        meshFile: meshEl.getAttribute('filename') ?? '',
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

    final axisEl = el.getElement('axis');
    final axis = _parseVec3(axisEl?.getAttribute('xyz') ?? '0 0 1');

    final limitEl = el.getElement('limit');
    final limitLower = double.tryParse(limitEl?.getAttribute('lower') ?? '') ?? -3.14159;
    final limitUpper = double.tryParse(limitEl?.getAttribute('upper') ?? '') ??  3.14159;

    return UrdfJoint(
      name: name, type: type, parent: parent, child: child, origin: origin,
      axisX: axis[0], axisY: axis[1], axisZ: axis[2],
      limitLower: limitLower, limitUpper: limitUpper,
    );
  }

  static List<double> _parseVec3(String? s) {
    if (s == null) return [0, 0, 0];
    final parts = s.trim().split(RegExp(r'\s+'));
    return [
      double.tryParse(parts.elementAtOrNull(0) ?? '') ?? 0,
      double.tryParse(parts.elementAtOrNull(1) ?? '') ?? 0,
      double.tryParse(parts.elementAtOrNull(2) ?? '') ?? 0,
    ];
  }
}

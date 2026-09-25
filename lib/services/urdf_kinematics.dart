import 'dart:math' as math;

import 'urdf_parser_service.dart';

/// Row-major 4x4 transforms stored as 16 doubles.
typedef Mat4 = List<double>;

const Mat4 identityMat4 = [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1];

Mat4 mat4Mul(Mat4 a, Mat4 b) {
  final r = List<double>.filled(16, 0);
  for (var i = 0; i < 4; i++) {
    for (var j = 0; j < 4; j++) {
      r[i * 4 + j] = a[i * 4] * b[j] + a[i * 4 + 1] * b[4 + j] +
          a[i * 4 + 2] * b[8 + j] + a[i * 4 + 3] * b[12 + j];
    }
  }
  return r;
}

/// URDF origin: translation, then fixed-axis roll/pitch/yaw
/// (R = Rz(yaw) · Ry(pitch) · Rx(roll)).
Mat4 originMat4(UrdfOrigin o) {
  final cr = math.cos(o.roll), sr = math.sin(o.roll);
  final cp = math.cos(o.pitch), sp = math.sin(o.pitch);
  final cy = math.cos(o.yaw), sy = math.sin(o.yaw);
  return [
    cy * cp, cy * sp * sr - sy * cr, cy * sp * cr + sy * sr, o.x,
    sy * cp, sy * sp * sr + cy * cr, sy * sp * cr - cy * sr, o.y,
    -sp, cp * sr, cp * cr, o.z,
    0, 0, 0, 1,
  ];
}

Mat4 axisAngleMat4(double x, double y, double z, double a) {
  final l = math.sqrt(x * x + y * y + z * z);
  if (l == 0 || a == 0) return identityMat4;
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

Mat4 scaleMat4(double x, double y, double z) => [x, 0, 0, 0, 0, y, 0, 0, 0, 0, z, 0, 0, 0, 0, 1];

/// World transform of every link for the given joint positions
/// (rad for revolute/continuous, m for prismatic). Links that are not
/// reachable from a root (broken trees) are placed at the origin.
Map<String, Mat4> linkTransforms(UrdfRobot robot, Map<String, double> jointValues) {
  final byParent = <String, List<UrdfJoint>>{};
  for (final j in robot.joints) {
    byParent.putIfAbsent(j.parent, () => []).add(j);
  }
  final children = robot.joints.map((j) => j.child).toSet();
  final out = <String, Mat4>{};

  void walk(String link, Mat4 world) {
    if (out.containsKey(link)) return; // cycle guard
    out[link] = world;
    for (final j in byParent[link] ?? const <UrdfJoint>[]) {
      final v = jointValues[j.name] ?? 0;
      var t = mat4Mul(world, originMat4(j.origin));
      if (j.type == 'revolute' || j.type == 'continuous') {
        t = mat4Mul(t, axisAngleMat4(j.axisX, j.axisY, j.axisZ, v));
      } else if (j.type == 'prismatic') {
        final l = math.sqrt(j.axisX * j.axisX + j.axisY * j.axisY + j.axisZ * j.axisZ);
        if (l > 0) {
          t = mat4Mul(t, [1, 0, 0, j.axisX / l * v, 0, 1, 0, j.axisY / l * v, 0, 0, 1, j.axisZ / l * v, 0, 0, 0, 1]);
        }
      }
      walk(j.child, t);
    }
  }

  for (final l in robot.links) {
    if (!children.contains(l.name)) walk(l.name, identityMat4);
  }
  for (final l in robot.links) {
    out.putIfAbsent(l.name, () => identityMat4);
  }
  return out;
}

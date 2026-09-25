import 'dart:math' as math;

import 'ros_msg.dart';

/// One valid LaserScan return in the sensor frame (x forward, y left).
class ScanPoint {
  final double angle; // rad, 0 = forward, positive = counter-clockwise (left)
  final double range; // m
  const ScanPoint(this.angle, this.range);

  double get x => range * math.cos(angle);
  double get y => range * math.sin(angle);
}

class ScanSummary {
  final List<ScanPoint> points;
  final int total;
  final double angleMin, angleMax, rangeMin, rangeMax;

  const ScanSummary({
    required this.points,
    required this.total,
    required this.angleMin,
    required this.angleMax,
    required this.rangeMin,
    required this.rangeMax,
  });

  ScanPoint? get closest => points.isEmpty
      ? null
      : points.reduce((a, b) => a.range <= b.range ? a : b);

  /// Closest return inside [from, to) degrees (normalized to -180..180).
  double? minInSector(double fromDeg, double toDeg) {
    double? best;
    for (final p in points) {
      final d = normalizeDeg(p.angle * 180 / math.pi);
      final inside = fromDeg <= toDeg
          ? d >= fromDeg && d < toDeg
          : d >= fromDeg || d < toDeg; // wraps across ±180
      if (inside && (best == null || p.range < best)) best = p.range;
    }
    return best;
  }

  double? get front => minInSector(-45, 45);
  double? get left => minInSector(45, 135);
  double? get back => minInSector(135, -135);
  double? get right => minInSector(-135, -45);

  /// Radius (m) that frames almost all returns, ignoring a few far outliers.
  double autoViewRange() {
    if (points.isEmpty) return math.max(1, math.min(rangeMax, 10));
    final rs = points.map((p) => p.range).toList()..sort();
    final p98 = rs[((rs.length - 1) * 0.98).round()];
    return math.max(1, p98 * 1.1);
  }
}

double normalizeDeg(double d) {
  var a = (d + 180) % 360;
  if (a < 0) a += 360;
  return a - 180;
}

/// Parses a sensor_msgs/LaserScan. Returns outside [range_min, range_max],
/// and `null` (inf/NaN from rosbridge) are dropped.
ScanSummary parseScan(Map<String, dynamic> msg) {
  final ranges = doubleList(msg['ranges']);
  final angleMin = numAt(msg, 'angle_min', -math.pi);
  final angleMax = numAt(msg, 'angle_max', math.pi);
  var inc = numAt(msg, 'angle_increment', 0);
  if (inc == 0 && ranges.length > 1) {
    inc = (angleMax - angleMin) / (ranges.length - 1);
  }
  final rMin = numAt(msg, 'range_min', 0);
  final rMax = numAt(msg, 'range_max', double.infinity);

  final pts = <ScanPoint>[];
  for (var i = 0; i < ranges.length; i++) {
    final r = ranges[i];
    if (r == null || r < rMin || r > rMax || r <= 0) continue;
    pts.add(ScanPoint(angleMin + i * inc, r));
  }
  return ScanSummary(
    points: pts,
    total: ranges.length,
    angleMin: angleMin,
    angleMax: angleMax,
    rangeMin: rMin,
    rangeMax: rMax.isFinite ? rMax : 0,
  );
}

/// "ahead", "behind", "35° left", "120° right".
String describeDirection(double angleRad) {
  final d = normalizeDeg(angleRad * 180 / math.pi).round();
  if (d.abs() <= 5) return 'ahead';
  if (d.abs() >= 175) return 'behind';
  return '${d.abs()}° ${d > 0 ? 'left' : 'right'}';
}

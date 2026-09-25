import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:robotics_tool/utils/scan_geometry.dart';

Map<String, dynamic> scan(List<dynamic> ranges,
        {double amin = -math.pi, double? inc, double rmin = 0.1, double rmax = 10}) =>
    {
      'angle_min': amin,
      'angle_max': amin + (inc ?? 2 * math.pi / ranges.length) * (ranges.length - 1),
      'angle_increment': inc ?? 2 * math.pi / ranges.length,
      'range_min': rmin,
      'range_max': rmax,
      'ranges': ranges,
    };

void main() {
  test('drops null (inf/NaN from rosbridge) and out-of-limit returns', () {
    final s = parseScan(scan([1.0, null, 0.05, 20.0, 2.0]));
    expect(s.total, 5);
    expect(s.points.map((p) => p.range), [1.0, 2.0]);
  });

  test('angles follow angle_min + i * increment', () {
    final s = parseScan(scan([1, 1, 1, 1], amin: 0, inc: math.pi / 2));
    expect(s.points.map((p) => p.angle), [0, math.pi / 2, math.pi, 3 * math.pi / 2]);
  });

  test('point coordinates: x forward, y left', () {
    const p = ScanPoint(math.pi / 2, 2);
    expect(p.x, closeTo(0, 1e-9));
    expect(p.y, closeTo(2, 1e-9));
  });

  test('closest obstacle and sector minimums', () {
    // 4 beams: front, left, back, right
    final s = parseScan(scan([3.0, 1.5, 4.0, 0.8], amin: 0, inc: math.pi / 2));
    expect(s.closest!.range, 0.8);
    expect(describeDirection(s.closest!.angle), '90° right');
    expect(s.front, 3.0);
    expect(s.left, 1.5);
    expect(s.back, 4.0);
    expect(s.right, 0.8);
  });

  test('empty sectors are null', () {
    final s = parseScan(scan([1.0], amin: 0, inc: 0.1));
    expect(s.front, 1.0);
    expect(s.back, isNull);
  });

  test('describeDirection', () {
    expect(describeDirection(0.02), 'ahead');
    expect(describeDirection(math.pi), 'behind');
    expect(describeDirection(-math.pi + 0.01), 'behind');
    expect(describeDirection(math.pi / 6), '30° left');
    expect(describeDirection(2 * math.pi - math.pi / 4), '45° right');
  });

  test('autoViewRange ignores a few far outliers', () {
    final ranges = [...List.filled(99, 2.0), 9.5];
    final s = parseScan(scan(ranges));
    expect(s.autoViewRange(), lessThan(3));
    expect(parseScan(scan([])).autoViewRange(), greaterThanOrEqualTo(1));
  });

  test('missing angle_increment is derived from the angle span', () {
    final s = parseScan({
      'angle_min': 0.0,
      'angle_max': 1.0,
      'ranges': [1, 1, 1],
    });
    expect(s.points.last.angle, closeTo(1.0, 1e-9));
  });
}

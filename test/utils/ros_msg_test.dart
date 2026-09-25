import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:robotics_tool/utils/ros_msg.dart';

void main() {
  group('asDouble', () {
    test('numbers', () {
      expect(asDouble(3), 3.0);
      expect(asDouble(2.5), 2.5);
    });
    test('null and junk become null', () {
      expect(asDouble(null), isNull);
      expect(asDouble({}), isNull);
      expect(asDouble('abc'), isNull);
    });
    test('special float strings', () {
      expect(asDouble('inf'), double.infinity);
      expect(asDouble('-Infinity'), double.negativeInfinity);
      expect(asDouble('NaN')!.isNaN, isTrue);
      expect(asDouble(' 1.5 '), 1.5);
    });
  });

  test('doubleList maps null / non-finite entries to null', () {
    // rosbridge sends inf / NaN LaserScan ranges as null
    expect(doubleList([1, null, 2.5, 'inf', 'x']), [1.0, null, 2.5, null, null]);
    expect(doubleList(null), isEmpty);
  });

  group('field / numAt', () {
    final msg = {
      'pose': {
        'pose': {
          'position': {'x': 1, 'y': null},
        },
      },
      'list': [10, 20],
    };
    test('dotted paths and list indices', () {
      expect(field(msg, 'pose.pose.position.x'), 1);
      expect(field(msg, 'list.1'), 20);
      expect(field(msg, 'list.5'), isNull);
      expect(field(msg, 'missing.deep.path'), isNull);
    });
    test('numAt falls back for missing or null values', () {
      expect(numAt(msg, 'pose.pose.position.x'), 1.0);
      expect(numAt(msg, 'pose.pose.position.y', -1), -1.0);
      expect(numAt(msg, 'nope', 7), 7.0);
    });
  });

  test('baseType normalizes ROS2 names', () {
    expect(baseType('sensor_msgs/msg/LaserScan'), 'sensor_msgs/LaserScan');
    expect(baseType('sensor_msgs/LaserScan'), 'sensor_msgs/LaserScan');
  });

  group('quatToEuler', () {
    test('identity', () {
      final e = quatToEuler(0, 0, 0, 1);
      expect(e.roll, closeTo(0, 1e-9));
      expect(e.pitch, closeTo(0, 1e-9));
      expect(e.yaw, closeTo(0, 1e-9));
    });
    test('pure yaw of 90 degrees', () {
      final e = quatToEuler(0, 0, math.sin(math.pi / 4), math.cos(math.pi / 4));
      expect(e.yaw, closeTo(math.pi / 2, 1e-9));
      expect(e.roll, closeTo(0, 1e-9));
    });
    test('pure roll of 30 degrees', () {
      const r = math.pi / 6;
      final e = quatToEuler(math.sin(r / 2), 0, 0, math.cos(r / 2));
      expect(e.roll, closeTo(r, 1e-9));
      expect(e.yaw, closeTo(0, 1e-9));
    });
    test('unnormalized and zero quaternions do not blow up', () {
      expect(quatToEuler(0, 0, 0, 2).yaw, closeTo(0, 1e-9));
      expect(quatToEuler(0, 0, 0, 0).yaw, 0);
    });
  });
}

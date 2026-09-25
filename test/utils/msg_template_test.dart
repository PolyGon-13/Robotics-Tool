import 'package:flutter_test/flutter_test.dart';
import 'package:robotics_tool/utils/msg_template.dart';

void main() {
  // Shape of rosapi/message_details for geometry_msgs/TwistStamped
  final typedefs = [
    {
      'type': 'geometry_msgs/TwistStamped',
      'fieldnames': ['header', 'twist'],
      'fieldtypes': ['std_msgs/Header', 'geometry_msgs/Twist'],
      'fieldarraylen': [-1, -1],
    },
    {
      'type': 'std_msgs/Header',
      'fieldnames': ['stamp', 'frame_id'],
      'fieldtypes': ['builtin_interfaces/Time', 'string'],
      'fieldarraylen': [-1, -1],
    },
    {
      'type': 'builtin_interfaces/Time',
      'fieldnames': ['sec', 'nanosec'],
      'fieldtypes': ['int32', 'uint32'],
      'fieldarraylen': [-1, -1],
    },
    {
      'type': 'geometry_msgs/msg/Twist', // ROS2 style name also accepted
      'fieldnames': ['linear', 'angular'],
      'fieldtypes': ['geometry_msgs/Vector3', 'geometry_msgs/Vector3'],
      'fieldarraylen': [-1, -1],
    },
    {
      'type': 'geometry_msgs/Vector3',
      'fieldnames': ['x', 'y', 'z'],
      'fieldtypes': ['float64', 'float64', 'float64'],
      'fieldarraylen': [-1, -1, -1],
    },
  ];

  test('nested template with defaults', () {
    final t = templateFromTypedefs('geometry_msgs/msg/TwistStamped', typedefs);
    expect(t, {
      'header': {'stamp': {'sec': 0, 'nanosec': 0}, 'frame_id': ''},
      'twist': {
        'linear': {'x': 0.0, 'y': 0.0, 'z': 0.0},
        'angular': {'x': 0.0, 'y': 0.0, 'z': 0.0},
      },
    });
  });

  test('arrays: variable length is empty, fixed length is filled', () {
    final t = templateFromTypedefs('pkg/Arr', [
      {
        'type': 'pkg/Arr',
        'fieldnames': ['names', 'covariance', 'ok'],
        'fieldtypes': ['string', 'float64', 'bool'],
        'fieldarraylen': [0, 3, -1],
      },
    ]);
    expect(t, {'names': [], 'covariance': [0.0, 0.0, 0.0], 'ok': false});
  });

  test('unknown type returns null; unknown nested type becomes {}', () {
    expect(templateFromTypedefs('pkg/Missing', typedefs), isNull);
    final t = templateFromTypedefs('pkg/A', [
      {'type': 'pkg/A', 'fieldnames': ['b'], 'fieldtypes': ['pkg/B'], 'fieldarraylen': [-1]},
    ]);
    expect(t, {'b': {}});
  });

  test('quaternions default to identity (w = 1)', () {
    final t = templateFromTypedefs('geometry_msgs/Pose', [
      {'type': 'geometry_msgs/Pose', 'fieldnames': ['orientation'],
       'fieldtypes': ['geometry_msgs/Quaternion'], 'fieldarraylen': [-1]},
      {'type': 'geometry_msgs/Quaternion', 'fieldnames': ['x', 'y', 'z', 'w'],
       'fieldtypes': ['float64', 'float64', 'float64', 'float64'], 'fieldarraylen': [-1, -1, -1, -1]},
    ]);
    expect(t, {'orientation': {'x': 0.0, 'y': 0.0, 'z': 0.0, 'w': 1.0}});
  });

  test('self-referencing typedefs terminate', () {
    final t = templateFromTypedefs('pkg/Loop', [
      {'type': 'pkg/Loop', 'fieldnames': ['next'], 'fieldtypes': ['pkg/Loop'], 'fieldarraylen': [-1]},
    ]);
    expect(t, isNotNull);
  });
}

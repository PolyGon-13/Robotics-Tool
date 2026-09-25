import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'dart:async';
import 'dart:convert';

import 'package:robotics_tool/widgets/visualizations/visualizer_registry.dart';
import 'package:robotics_tool/widgets/visualizations/viz_common.dart';

Map<String, dynamic> quat(double yaw) => {'x': 0.0, 'y': 0.0, 'z': math.sin(yaw / 2), 'w': math.cos(yaw / 2)};

/// One realistic message per visualized type (as rosbridge would send it).
final fixtures = <String, Map<String, dynamic>>{
  'sensor_msgs/msg/LaserScan': {
    'angle_min': -math.pi,
    'angle_max': math.pi,
    'angle_increment': math.pi / 180,
    'range_min': 0.1,
    'range_max': 8.0,
    'ranges': [for (var i = 0; i < 360; i++) i % 7 == 0 ? null : 1 + (i % 50) / 20],
  },
  'nav_msgs/msg/Odometry': {
    'header': {'frame_id': 'odom'},
    'child_frame_id': 'base_link',
    'pose': {
      'pose': {
        'position': {'x': 1.2, 'y': -0.4, 'z': 0},
        'orientation': quat(0.7),
      },
    },
    'twist': {
      'twist': {
        'linear': {'x': 0.3, 'y': 0, 'z': 0},
        'angular': {'x': 0, 'y': 0, 'z': -0.2},
      },
    },
  },
  'geometry_msgs/msg/Twist': {
    'linear': {'x': 0.5, 'y': 0.0, 'z': 0.0},
    'angular': {'x': 0.0, 'y': 0.0, 'z': 0.8},
  },
  'geometry_msgs/msg/TwistStamped': {
    'header': {'frame_id': 'base_link'},
    'twist': {
      'linear': {'x': -0.2, 'y': 0.1, 'z': 0.0},
      'angular': {'x': 0.0, 'y': 0.0, 'z': -0.3},
    },
  },
  'sensor_msgs/msg/Imu': {
    'orientation': quat(1.0),
    'orientation_covariance': [0.0, 0, 0, 0, 0, 0, 0, 0, 0],
    'angular_velocity': {'x': 0.01, 'y': 0.0, 'z': 0.3},
    'linear_acceleration': {'x': 0.1, 'y': 0.0, 'z': 9.81},
  },
  'sensor_msgs/msg/JointState': {
    'name': ['shoulder', 'elbow', 'wrist_with_a_really_long_joint_name'],
    'position': [0.5, -1.2, null],
    'velocity': [0.1, 0.0, 0.2],
    'effort': [],
  },
  'sensor_msgs/msg/BatteryState': {
    'voltage': 12.1,
    'current': -1.5,
    'temperature': null,
    'percentage': 0.18,
    'power_supply_status': 2,
    'power_supply_health': 1,
    'present': true,
    'cell_voltage': [4.03, 4.02, 4.05],
  },
  'sensor_msgs/msg/Range': {
    'radiation_type': 0,
    'field_of_view': 0.5,
    'min_range': 0.02,
    'max_range': 4.0,
    'range': 0.25,
  },
  'sensor_msgs/msg/Temperature': {'temperature': 36.6, 'variance': 0.0},
  'geometry_msgs/msg/PoseStamped': {
    'header': {'frame_id': 'map'},
    'pose': {
      'position': {'x': 2.0, 'y': -1.0, 'z': 0.0},
      'orientation': quat(math.pi / 2),
    },
  },
  'geometry_msgs/msg/PoseWithCovarianceStamped': {
    'pose': {
      'pose': {
        'position': {'x': 1.0, 'y': 1.0, 'z': 0.0},
        'orientation': quat(0),
      },
      'covariance': List.filled(36, 0.0),
    },
  },
  'geometry_msgs/msg/Vector3': {'x': 1.0, 'y': 2.0, 'z': 3.0},
  'geometry_msgs/msg/Pose2D': {'x': 1.0, 'y': 2.0, 'theta': 0.5},
  'geometry_msgs/msg/Quaternion': quat(0.3),
  'std_msgs/msg/Float32': {'data': 12.3},
  'std_msgs/msg/Int64': {'data': 42},
  'std_msgs/msg/Float64MultiArray': {
    'layout': {'dim': [], 'data_offset': 0},
    'data': [1.0, null, 3.5, 4, 5, 6, 7, 8, 9, 10],
  },
  'tf2_msgs/msg/TFMessage': {
    'transforms': [
      {
        'header': {'frame_id': 'odom'},
        'child_frame_id': 'base_link',
        'transform': {
          'translation': {'x': 1.0, 'y': 0.0, 'z': 0.0},
          'rotation': quat(0.5),
        },
      },
      {
        'header': {'frame_id': 'base_link'},
        'child_frame_id': 'laser',
        'transform': {
          'translation': {'x': 0.1, 'y': 0.0, 'z': 0.2},
          'rotation': quat(0),
        },
      },
      // cycle must not hang
      {
        'header': {'frame_id': 'a'},
        'child_frame_id': 'b',
        'transform': {},
      },
      {
        'header': {'frame_id': 'b'},
        'child_frame_id': 'a',
        'transform': {},
      },
    ],
  },
  'std_msgs/msg/String': {'data': 'NAVIGATING'},
  'std_msgs/msg/Bool': {'data': true},
};

Future<void> pumpViz(
  WidgetTester tester,
  String type,
  Map<String, dynamic> msg, {
  Brightness brightness = Brightness.light,
}) {
  return tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(colorSchemeSeed: Colors.blue, brightness: brightness),
      home: Scaffold(body: buildVisualizer(type, '/test', msg)),
    ),
  );
}

void main() {
  testWidgets('every fixture type has a visualizer', (tester) async {
    for (final type in fixtures.keys) {
      expect(hasVisualizer(type), isTrue, reason: type);
    }
    expect(hasVisualizer('sensor_msgs/LaserScan'), isTrue, reason: 'ROS1-style name');
    expect(hasVisualizer('my_pkg/msg/Custom'), isFalse);
  });

  for (final entry in fixtures.entries) {
    for (final width in [360.0, 412.0]) {
      testWidgets('${entry.key} renders, updates and survives bad input at ${width.round()} dp', (tester) async {
        tester.view.physicalSize = Size(width, 860);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        await pumpViz(tester, entry.key, entry.value);
        await tester.pump();
        expect(tester.takeException(), isNull);

        // A second, different message instance updates in place
        await pumpViz(tester, entry.key, Map.of(entry.value));
        await tester.pump(const Duration(milliseconds: 100));
        expect(tester.takeException(), isNull);

        // Empty / malformed message must not throw
        await pumpViz(tester, entry.key, <String, dynamic>{});
        await tester.pump();
        expect(tester.takeException(), isNull);

        await pumpViz(tester, entry.key, entry.value, brightness: Brightness.dark);
        await tester.pump();
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('LaserScan shows closest obstacle and sides', (tester) async {
    tester.view.physicalSize = const Size(412, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpViz(tester, 'sensor_msgs/msg/LaserScan', {
      'angle_min': 0.0,
      'angle_increment': math.pi / 2,
      'angle_max': 3 * math.pi / 2,
      'range_min': 0.1,
      'range_max': 10.0,
      'ranges': [3.0, 1.5, null, 0.4],
    });
    await tester.pump();
    expect(find.text('Closest obstacle'), findsOneWidget);
    expect(find.text('90° right'), findsOneWidget);
    expect(find.text('Front'), findsOneWidget);
  });

  testWidgets('TF shows the frame tree', (tester) async {
    await pumpViz(tester, 'tf2_msgs/msg/TFMessage', fixtures['tf2_msgs/msg/TFMessage']!);
    expect(find.text('Frames (4)'), findsOneWidget);
    expect(find.text('odom'), findsOneWidget); // root without its own transform
    expect(find.text('laser'), findsOneWidget);
  });

  testWidgets('Bool shows TRUE/FALSE and logs changes', (tester) async {
    await pumpViz(tester, 'std_msgs/msg/Bool', {'data': false});
    expect(find.text('FALSE'), findsOneWidget);
    await pumpViz(tester, 'std_msgs/msg/Bool', {'data': true});
    await tester.pump();
    expect(find.text('TRUE'), findsOneWidget);
    expect(find.text('Changes (2)'), findsOneWidget);
  });

  testWidgets('Battery shows percentage and status', (tester) async {
    tester.view.physicalSize = const Size(412, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpViz(tester, 'sensor_msgs/msg/BatteryState', fixtures['sensor_msgs/msg/BatteryState']!);
    expect(find.textContaining('18 %'), findsOneWidget);
    expect(find.text('Discharging'), findsOneWidget);
  });

  testWidgets('UInt8MultiArray data sent as base64 is shown as numbers', (tester) async {
    await pumpViz(tester, 'std_msgs/msg/UInt8MultiArray', {
      'layout': {'dim': [], 'data_offset': 0},
      'data': base64Encode([7, 200, 3]),
    });
    expect(find.text('Values (3)'), findsOneWidget);
    expect(find.text('200'), findsWidgets);
  });

  testWidgets('Range: null (inf from rosbridge) reads "Out of range"', (tester) async {
    await pumpViz(tester, 'sensor_msgs/msg/Range', {
      'min_range': 0.02,
      'max_range': 4.0,
      'range': null,
      'field_of_view': 0.5,
    });
    expect(find.text('Out of range'), findsOneWidget);
  });

  testWidgets('Battery percentage given as 0-100 is not multiplied again', (tester) async {
    tester.view.physicalSize = const Size(360, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpViz(tester, 'sensor_msgs/msg/BatteryState', {
      'percentage': 85.0,
      'power_supply_status': 2,
      'power_supply_health': 7,
    });
    expect(find.textContaining('85 %'), findsOneWidget);
    expect(tester.takeException(), isNull, reason: 'long health text fits at 360 dp');
  });

  testWidgets('JointState without names falls back to indices', (tester) async {
    await pumpViz(tester, 'sensor_msgs/msg/JointState', {
      'name': [],
      'position': [0.1, 0.2],
    });
    expect(find.text('joint[1]'), findsWidgets);
  });

  testWidgets('LaserScan zoom works for short-range sensors', (tester) async {
    tester.view.physicalSize = const Size(412, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpViz(tester, 'sensor_msgs/msg/LaserScan', {
      'angle_min': 0.5,
      'angle_max': -0.5,
      'angle_increment': -0.1,
      'range_min': 0.01,
      'range_max': 0.12,
      'ranges': List.filled(11, 0.08),
    });
    await tester.tap(find.byTooltip('Zoom in'));
    await tester.tap(find.byTooltip('Zoom out'));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('57.3°'), findsOneWidget, reason: 'clockwise scan: positive field of view');
  });

  testWidgets('MsgFeed delivers every message even without a rebuild each', (tester) async {
    final feed = StreamController<Map<String, dynamic>>.broadcast(sync: true);
    addTearDown(feed.close);
    Widget app(Map<String, dynamic> msg) => MaterialApp(
      home: Scaffold(
        body: MsgFeed(stream: feed.stream, child: buildVisualizer('std_msgs/msg/String', '/s', msg)),
      ),
    );
    await tester.pumpWidget(app({'data': 'a'}));
    Map<String, dynamic> last = {};
    for (final v in ['b', 'c', 'd', 'e']) {
      last = {'data': v};
      feed.add(last); // four messages within one frame
    }
    await tester.pumpWidget(app(last));
    expect(find.text('Changes (5)'), findsOneWidget);
  });
}

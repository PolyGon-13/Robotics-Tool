import 'package:flutter/material.dart';

import '../../utils/ros_msg.dart';
import 'battery_widget.dart';
import 'compressed_image_widget.dart';
import 'image_widget.dart';
import 'imu_widget.dart';
import 'joint_state_widget.dart';
import 'laser_scan_widget.dart';
import 'odometry_widget.dart';
import 'pose_widget.dart';
import 'range_widget.dart';
import 'scalar_chart_widget.dart';
import 'text_widget.dart';
import 'tf_widget.dart';
import 'twist_widget.dart';

typedef VisualizerBuilder = Widget Function(
    String topic, Map<String, dynamic> msg);

const _numberTypes = [
  'Float32', 'Float64', 'Int8', 'Int16', 'Int32', 'Int64',
  'UInt8', 'UInt16', 'UInt32', 'UInt64', 'Byte', 'Char',
];

/// Message type (normalized to `pkg/Type`) → visualization.
final Map<String, VisualizerBuilder> _visualizers = {
  'sensor_msgs/LaserScan': (t, m) => LaserScanWidget(topic: t, msg: m),
  'nav_msgs/Odometry': (t, m) => OdometryWidget(topic: t, msg: m),
  'sensor_msgs/Imu': (t, m) => ImuWidget(topic: t, msg: m),
  'sensor_msgs/JointState': (t, m) => JointStateWidget(topic: t, msg: m),
  'sensor_msgs/BatteryState': (t, m) => BatteryWidget(topic: t, msg: m),
  'sensor_msgs/Range': (t, m) => RangeWidget(topic: t, msg: m),
  'sensor_msgs/Image': (t, m) => ImageWidget(msg: m),
  'sensor_msgs/CompressedImage': (t, m) => CompressedImageWidget(msg: m),
  'sensor_msgs/Temperature': (t, m) =>
      ScalarChartWidget(topic: t, msg: m, path: 'temperature', unit: '°C'),
  'sensor_msgs/RelativeHumidity': (t, m) =>
      ScalarChartWidget(topic: t, msg: m, path: 'relative_humidity'),
  'sensor_msgs/FluidPressure': (t, m) =>
      ScalarChartWidget(topic: t, msg: m, path: 'fluid_pressure', unit: 'Pa'),
  'sensor_msgs/Illuminance': (t, m) =>
      ScalarChartWidget(topic: t, msg: m, path: 'illuminance', unit: 'lx'),
  for (final ty in ['Twist', 'TwistStamped'])
    'geometry_msgs/$ty': (t, m) => TwistWidget(topic: t, msg: m),
  for (final ty in [
    'Pose', 'PoseStamped', 'PoseWithCovariance', 'PoseWithCovarianceStamped',
    'Point', 'PointStamped', 'Quaternion', 'QuaternionStamped', 'Pose2D',
  ])
    'geometry_msgs/$ty': (t, m) => PoseWidget(topic: t, msg: m),
  for (final ty in ['Vector3', 'Vector3Stamped'])
    'geometry_msgs/$ty': (t, m) => PoseWidget(topic: t, msg: m, isVector: true),
  for (final ty in _numberTypes) ...{
    'std_msgs/$ty': (t, m) => ScalarChartWidget(topic: t, msg: m),
    'std_msgs/${ty}MultiArray': (t, m) => ScalarChartWidget(topic: t, msg: m),
  },
  'tf2_msgs/TFMessage': (t, m) => TfWidget(topic: t, msg: m),
  'std_msgs/String': (t, m) => TextValueWidget(topic: t, msg: m),
  'std_msgs/Bool': (t, m) => TextValueWidget(topic: t, msg: m),
};

bool hasVisualizer(String type) => _visualizers.containsKey(baseType(type));

Widget buildVisualizer(String type, String topic, Map<String, dynamic> msg) =>
    _visualizers[baseType(type)]!(topic, msg);

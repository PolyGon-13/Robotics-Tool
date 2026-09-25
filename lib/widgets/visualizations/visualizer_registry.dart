import 'package:flutter/material.dart';

import '../../utils/ros_msg.dart';
import 'compressed_image_widget.dart';
import 'image_widget.dart';
import 'laser_scan_widget.dart';
import 'odometry_widget.dart';
import 'scalar_chart_widget.dart';
import 'twist_widget.dart';

typedef VisualizerBuilder = Widget Function(
    String topic, Map<String, dynamic> msg);

/// Message type (normalized to `pkg/Type`) → visualization.
final Map<String, VisualizerBuilder> _visualizers = {
  'sensor_msgs/LaserScan': (t, m) => LaserScanWidget(msg: m),
  'nav_msgs/Odometry': (t, m) => OdometryWidget(topic: t, latestMsg: m),
  'geometry_msgs/Twist': (t, m) => TwistWidget(topic: t, latestMsg: m),
  'sensor_msgs/CompressedImage': (t, m) => CompressedImageWidget(msg: m),
  'sensor_msgs/Image': (t, m) => ImageWidget(msg: m),
  for (final s in scalarTypes)
    s: (t, m) => ScalarChartWidget(topic: t, latestMsg: m),
};

const scalarTypes = {
  'std_msgs/Float64', 'std_msgs/Float32',
  'std_msgs/Int8', 'std_msgs/Int16', 'std_msgs/Int32', 'std_msgs/Int64',
  'std_msgs/UInt8', 'std_msgs/UInt16', 'std_msgs/UInt32', 'std_msgs/UInt64',
};

bool hasVisualizer(String type) => _visualizers.containsKey(baseType(type));

Widget buildVisualizer(String type, String topic, Map<String, dynamic> msg) =>
    _visualizers[baseType(type)]!(topic, msg);

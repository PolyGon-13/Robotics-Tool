import 'package:flutter/material.dart';

import '../utils/ros_msg.dart';

/// Icon that hints at what a message type is (and how it is visualized).
IconData topicIcon(String type) {
  final t = baseType(type);
  final name = t.contains('/') ? t.substring(t.lastIndexOf('/') + 1) : t;
  return switch (name) {
    'LaserScan' || 'PointCloud2' || 'PointCloud' => Icons.radar,
    'Odometry' || 'Path' => Icons.route,
    'Twist' || 'TwistStamped' => Icons.open_with,
    'Imu' => Icons.screen_rotation_alt,
    'JointState' => Icons.precision_manufacturing,
    'BatteryState' => Icons.battery_charging_full,
    'Range' => Icons.sensors,
    'Image' || 'CompressedImage' => Icons.photo_camera_outlined,
    'CameraInfo' => Icons.camera_alt_outlined,
    'TFMessage' => Icons.account_tree_outlined,
    'Pose' || 'PoseStamped' || 'PoseWithCovarianceStamped' || 'Pose2D' => Icons.place_outlined,
    'Point' || 'PointStamped' || 'Vector3' || 'Vector3Stamped' => Icons.north_east,
    'String' => Icons.text_fields,
    'Bool' => Icons.toggle_on_outlined,
    'Temperature' => Icons.thermostat,
    'OccupancyGrid' => Icons.map_outlined,
    'Log' => Icons.receipt_long_outlined,
    _ when t.startsWith('std_msgs/') => Icons.show_chart,
    _ => Icons.data_object,
  };
}

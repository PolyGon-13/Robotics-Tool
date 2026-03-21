import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/connection_provider.dart';
import '../widgets/raw_json_tree_widget.dart';
import '../widgets/visualizations/compressed_image_widget.dart';
import '../widgets/visualizations/image_widget.dart';
import '../widgets/visualizations/laser_scan_widget.dart';
import '../widgets/visualizations/odometry_widget.dart';
import '../widgets/visualizations/scalar_chart_widget.dart';
import '../widgets/visualizations/twist_widget.dart';

class VisualizationScreen extends StatefulWidget {
  final String topic;
  final String type;

  const VisualizationScreen({
    super.key,
    required this.topic,
    required this.type,
  });

  @override
  State<VisualizationScreen> createState() => _VisualizationScreenState();
}

class _VisualizationScreenState extends State<VisualizationScreen> {
  StreamSubscription? _sub;
  Map<String, dynamic>? _latestMsg;
  bool _paused = false;
  int _msgCount = 0;
  DateTime? _firstMsgTime;
  double _hz = 0;

  @override
  void initState() {
    super.initState();
    _startSubscription();
  }

  void _startSubscription() {
    final service = context.read<ConnectionProvider>().service;
    final stream = service.subscribe(widget.topic, widget.type);
    _sub = stream.listen((msg) {
      if (_paused) return;
      _msgCount++;
      final now = DateTime.now();
      _firstMsgTime ??= now;
      final elapsed = now.difference(_firstMsgTime!).inMilliseconds / 1000.0;
      if (elapsed > 0) _hz = _msgCount / elapsed;
      setState(() => _latestMsg = msg);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    context.read<ConnectionProvider>().service.unsubscribe(widget.topic);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.topic, style: const TextStyle(fontSize: 14)),
            Text(widget.type,
                style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
        actions: [
          Text('${_hz.toStringAsFixed(1)} Hz',
              style: const TextStyle(fontSize: 12)),
          const SizedBox(width: 4),
          IconButton(
            icon: Icon(_paused ? Icons.play_arrow : Icons.pause),
            onPressed: () => setState(() => _paused = !_paused),
          ),
        ],
      ),
      body: _buildVisualization(),
    );
  }

  Widget _buildVisualization() {
    if (_latestMsg == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final t = widget.type;

    if (t == 'sensor_msgs/LaserScan' || t == 'sensor_msgs/msg/LaserScan') {
      return LaserScanWidget(msg: _latestMsg!);
    } else if (t == 'nav_msgs/Odometry' || t == 'nav_msgs/msg/Odometry') {
      return OdometryWidget(topic: widget.topic, latestMsg: _latestMsg!);
    } else if (t == 'geometry_msgs/Twist' || t == 'geometry_msgs/msg/Twist') {
      return TwistWidget(topic: widget.topic, latestMsg: _latestMsg!);
    } else if (_isScalar(t)) {
      return ScalarChartWidget(topic: widget.topic, latestMsg: _latestMsg!);
    } else if (t == 'sensor_msgs/CompressedImage' ||
               t == 'sensor_msgs/msg/CompressedImage') {
      return CompressedImageWidget(msg: _latestMsg!);
    } else if (t == 'sensor_msgs/Image' || t == 'sensor_msgs/msg/Image') {
      return ImageWidget(msg: _latestMsg!);
    } else {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(8),
        child: RawJsonTreeWidget(data: _latestMsg!),
      );
    }
  }

  static bool _isScalar(String type) {
    const scalars = {
      'std_msgs/Float64', 'std_msgs/Float32',
      'std_msgs/Int32',   'std_msgs/Int64',
      'std_msgs/Int16',   'std_msgs/Int8',
      'std_msgs/UInt64',  'std_msgs/UInt32',
      'std_msgs/Float64MultiArray',
      'std_msgs/msg/Float64', 'std_msgs/msg/Float32',
      'std_msgs/msg/Int32',
    };
    return scalars.contains(type);
  }
}

import 'dart:math';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

class OdometryWidget extends StatefulWidget {
  final String topic;
  final Map<String, dynamic> latestMsg;

  const OdometryWidget({
    super.key,
    required this.topic,
    required this.latestMsg,
  });

  @override
  State<OdometryWidget> createState() => _OdometryWidgetState();
}

class _OdometryWidgetState extends State<OdometryWidget> {
  static const int _maxPoints = 200;
  final List<FlSpot> _trajectory = [];
  final List<FlSpot> _linearVel = [];
  final List<FlSpot> _angularVel = [];
  int _t = 0;

  @override
  void didUpdateWidget(OdometryWidget old) {
    super.didUpdateWidget(old);
    _processMsg(widget.latestMsg);
  }

  void _processMsg(Map<String, dynamic> msg) {
    final pose = (msg['pose'] as Map?)?.cast<String, dynamic>() ?? {};
    final poseInner = (pose['pose'] as Map?)?.cast<String, dynamic>() ?? {};
    final pos = (poseInner['position'] as Map?)?.cast<String, dynamic>() ?? {};
    final ori = (poseInner['orientation'] as Map?)?.cast<String, dynamic>() ?? {};

    final x = (pos['x'] as num?)?.toDouble() ?? 0;
    final y = (pos['y'] as num?)?.toDouble() ?? 0;
    final qx = (ori['x'] as num?)?.toDouble() ?? 0;
    final qy = (ori['y'] as num?)?.toDouble() ?? 0;
    final qz = (ori['z'] as num?)?.toDouble() ?? 0;
    final qw = (ori['w'] as num?)?.toDouble() ?? 1;
    // theta computed for potential future use; suppress unused warning
    atan2(2 * (qw * qz + qx * qy), 1 - 2 * (qy * qy + qz * qz));

    final twist = (msg['twist'] as Map?)?.cast<String, dynamic>() ?? {};
    final twistInner = (twist['twist'] as Map?)?.cast<String, dynamic>() ?? {};
    final linear = (twistInner['linear'] as Map?)?.cast<String, dynamic>() ?? {};
    final angular = (twistInner['angular'] as Map?)?.cast<String, dynamic>() ?? {};
    final lx = (linear['x'] as num?)?.toDouble() ?? 0;
    final az = (angular['z'] as num?)?.toDouble() ?? 0;

    final t = _t.toDouble();
    _t++;

    _trajectory.add(FlSpot(x, y));
    _linearVel.add(FlSpot(t, lx));
    _angularVel.add(FlSpot(t, az));

    if (_trajectory.length > _maxPoints) _trajectory.removeAt(0);
    if (_linearVel.length > 100) _linearVel.removeAt(0);
    if (_angularVel.length > 100) _angularVel.removeAt(0);

    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          _PoseDisplay(msg: widget.latestMsg),
          const SizedBox(height: 12),
          _ChartCard(
            title: 'XY Trajectory',
            child: _trajectory.length < 2
                ? const Center(child: Text('Collecting…'))
                : LineChart(_trajectoryData()),
          ),
          const SizedBox(height: 12),
          _ChartCard(
            title: 'Velocity',
            child: _linearVel.length < 2
                ? const Center(child: Text('Collecting…'))
                : LineChart(_velocityData()),
          ),
        ],
      ),
    );
  }

  LineChartData _trajectoryData() {
    return LineChartData(
      lineBarsData: [
        LineChartBarData(
          spots: _trajectory,
          isCurved: true,
          color: Colors.blue,
          dotData: FlDotData(show: false),
          barWidth: 2,
        ),
      ],
      titlesData: FlTitlesData(
        leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 40)),
        bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 28)),
        topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
      ),
      gridData: FlGridData(show: true),
      borderData: FlBorderData(show: true),
    );
  }

  LineChartData _velocityData() {
    return LineChartData(
      lineBarsData: [
        LineChartBarData(
          spots: _linearVel,
          color: Colors.green,
          dotData: FlDotData(show: false),
          barWidth: 2,
        ),
        LineChartBarData(
          spots: _angularVel,
          color: Colors.orange,
          dotData: FlDotData(show: false),
          barWidth: 2,
          dashArray: [5, 3],
        ),
      ],
      titlesData: FlTitlesData(
        leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 40)),
        bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
      ),
      gridData: FlGridData(show: true),
      borderData: FlBorderData(show: true),
    );
  }
}

class _PoseDisplay extends StatelessWidget {
  final Map<String, dynamic> msg;

  const _PoseDisplay({required this.msg});

  @override
  Widget build(BuildContext context) {
    final pose = (msg['pose'] as Map?)?.cast<String, dynamic>() ?? {};
    final poseInner = (pose['pose'] as Map?)?.cast<String, dynamic>() ?? {};
    final pos = (poseInner['position'] as Map?)?.cast<String, dynamic>() ?? {};
    final ori = (poseInner['orientation'] as Map?)?.cast<String, dynamic>() ?? {};

    final x = (pos['x'] as num?)?.toDouble() ?? 0;
    final y = (pos['y'] as num?)?.toDouble() ?? 0;
    final qz = (ori['z'] as num?)?.toDouble() ?? 0;
    final qw = (ori['w'] as num?)?.toDouble() ?? 1;
    final theta = atan2(2 * qz * qw, 1 - 2 * qz * qz);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _Stat('X', x.toStringAsFixed(3)),
            _Stat('Y', y.toStringAsFixed(3)),
            _Stat('θ', '${(theta * 180 / pi).toStringAsFixed(1)}°'),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;

  const _Stat(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        Text(value,
            style: const TextStyle(
                fontSize: 18, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
      ],
    );
  }
}

class _ChartCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _ChartCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            SizedBox(height: 180, child: child),
          ],
        ),
      ),
    );
  }
}

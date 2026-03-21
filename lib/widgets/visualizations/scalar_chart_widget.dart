import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

class ScalarChartWidget extends StatefulWidget {
  final String topic;
  final Map<String, dynamic> latestMsg;

  const ScalarChartWidget({
    super.key,
    required this.topic,
    required this.latestMsg,
  });

  @override
  State<ScalarChartWidget> createState() => _ScalarChartWidgetState();
}

class _ScalarChartWidgetState extends State<ScalarChartWidget> {
  static const int _maxPoints = 100;
  final List<FlSpot> _points = [];
  int _t = 0;
  double _min = double.infinity;
  double _max = double.negativeInfinity;
  double _current = 0;

  @override
  void didUpdateWidget(ScalarChartWidget old) {
    super.didUpdateWidget(old);
    _addPoint(widget.latestMsg);
  }

  void _addPoint(Map<String, dynamic> msg) {
    final raw = msg['data'];
    double? v;
    if (raw is num) {
      v = raw.toDouble();
    } else if (raw is List && raw.isNotEmpty && raw.first is num) {
      v = (raw.first as num).toDouble();
    }
    if (v == null) return;

    _current = v;
    if (v < _min) _min = v;
    if (v > _max) _max = v;

    _points.add(FlSpot(_t.toDouble(), v));
    _t++;
    if (_points.length > _maxPoints) _points.removeAt(0);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _Stat('Current', _current.toStringAsFixed(4)),
              _Stat('Min', _min.isFinite ? _min.toStringAsFixed(4) : '—'),
              _Stat('Max', _max.isFinite ? _max.toStringAsFixed(4) : '—'),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _points.length < 2
                ? const Center(child: Text('Collecting data…'))
                : LineChart(
                    LineChartData(
                      lineBarsData: [
                        LineChartBarData(
                          spots: _points,
                          isCurved: false,
                          color: Colors.blue,
                          dotData: FlDotData(show: false),
                          barWidth: 2,
                          belowBarData: BarAreaData(
                            show: true,
                            color: Colors.blue.withValues(alpha: 0.1),
                          ),
                        ),
                      ],
                      titlesData: FlTitlesData(
                        leftTitles: AxisTitles(
                            sideTitles: SideTitles(
                                showTitles: true, reservedSize: 50)),
                        bottomTitles: AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                        topTitles: AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                        rightTitles: AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                      ),
                      gridData: FlGridData(show: true),
                      borderData: FlBorderData(show: true),
                    ),
                  ),
          ),
        ],
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
                fontSize: 16,
                fontWeight: FontWeight.bold,
                fontFamily: 'monospace')),
      ],
    );
  }
}

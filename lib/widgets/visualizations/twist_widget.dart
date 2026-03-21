import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

class TwistWidget extends StatefulWidget {
  final String topic;
  final Map<String, dynamic> latestMsg;

  const TwistWidget({
    super.key,
    required this.topic,
    required this.latestMsg,
  });

  @override
  State<TwistWidget> createState() => _TwistWidgetState();
}

class _TwistWidgetState extends State<TwistWidget> {
  static const int _maxPoints = 100;
  final Map<String, List<FlSpot>> _history = {
    'lx': [], 'ly': [], 'lz': [],
    'ax': [], 'ay': [], 'az': [],
  };
  int _t = 0;

  @override
  void didUpdateWidget(TwistWidget old) {
    super.didUpdateWidget(old);
    _update(widget.latestMsg);
  }

  void _update(Map<String, dynamic> msg) {
    final linear = (msg['linear'] as Map?)?.cast<String, dynamic>() ?? {};
    final angular = (msg['angular'] as Map?)?.cast<String, dynamic>() ?? {};

    final vals = {
      'lx': (linear['x'] as num?)?.toDouble() ?? 0,
      'ly': (linear['y'] as num?)?.toDouble() ?? 0,
      'lz': (linear['z'] as num?)?.toDouble() ?? 0,
      'ax': (angular['x'] as num?)?.toDouble() ?? 0,
      'ay': (angular['y'] as num?)?.toDouble() ?? 0,
      'az': (angular['z'] as num?)?.toDouble() ?? 0,
    };

    final t = _t.toDouble();
    _t++;

    for (final k in vals.keys) {
      _history[k]!.add(FlSpot(t, vals[k]!));
      if (_history[k]!.length > _maxPoints) _history[k]!.removeAt(0);
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final linear = (widget.latestMsg['linear'] as Map?)?.cast<String, dynamic>() ?? {};
    final angular = (widget.latestMsg['angular'] as Map?)?.cast<String, dynamic>() ?? {};

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          _Section(
            title: 'Linear',
            values: {
              'X': (linear['x'] as num?)?.toDouble() ?? 0,
              'Y': (linear['y'] as num?)?.toDouble() ?? 0,
              'Z': (linear['z'] as num?)?.toDouble() ?? 0,
            },
            histories: {
              'X': _history['lx']!,
              'Y': _history['ly']!,
              'Z': _history['lz']!,
            },
            colors: [Colors.red, Colors.green, Colors.blue],
          ),
          const SizedBox(height: 12),
          _Section(
            title: 'Angular',
            values: {
              'X': (angular['x'] as num?)?.toDouble() ?? 0,
              'Y': (angular['y'] as num?)?.toDouble() ?? 0,
              'Z': (angular['z'] as num?)?.toDouble() ?? 0,
            },
            histories: {
              'X': _history['ax']!,
              'Y': _history['ay']!,
              'Z': _history['az']!,
            },
            colors: [Colors.orange, Colors.purple, Colors.teal],
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final Map<String, double> values;
  final Map<String, List<FlSpot>> histories;
  final List<Color> colors;

  const _Section({
    required this.title,
    required this.values,
    required this.histories,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    final keys = values.keys.toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Row(
              children: List.generate(3, (i) {
                final k = keys[i];
                final v = values[k]!;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: _GaugeBar(
                        label: k, value: v, color: colors[i]),
                  ),
                );
              }),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 120,
              child: LineChart(
                LineChartData(
                  lineBarsData: List.generate(3, (i) {
                    final k = keys[i];
                    final pts = histories[k]!;
                    return LineChartBarData(
                      spots: pts.isEmpty ? [const FlSpot(0, 0)] : pts,
                      color: colors[i],
                      dotData: FlDotData(show: false),
                      barWidth: 1.5,
                    );
                  }),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 36)),
                    bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  gridData: FlGridData(show: true),
                  borderData: FlBorderData(show: true),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GaugeBar extends StatelessWidget {
  final String label;
  final double value;
  final Color color;

  const _GaugeBar({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        Text(
          value.toStringAsFixed(2),
          style: TextStyle(
              fontFamily: 'monospace',
              fontWeight: FontWeight.bold,
              color: color),
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: ((value + 2) / 4).clamp(0.0, 1.0),
            color: color,
            backgroundColor: color.withValues(alpha: 0.2),
            minHeight: 8,
          ),
        ),
      ],
    );
  }
}

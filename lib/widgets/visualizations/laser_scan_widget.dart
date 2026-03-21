import 'dart:math';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

class LaserScanWidget extends StatelessWidget {
  final Map<String, dynamic> msg;

  const LaserScanWidget({super.key, required this.msg});

  @override
  Widget build(BuildContext context) {
    final ranges = (msg['ranges'] as List<dynamic>? ?? [])
        .map((e) => (e as num).toDouble())
        .toList();
    final rangeMax = (msg['range_max'] as num?)?.toDouble() ?? 10.0;
    final angleMin = (msg['angle_min'] as num?)?.toDouble() ?? -pi;
    final angleMax = (msg['angle_max'] as num?)?.toDouble() ?? pi;

    if (ranges.isEmpty) {
      return const Center(child: Text('No laser data'));
    }

    // Downsample to max 36 points for radar chart
    const maxPoints = 36;
    final step = (ranges.length / maxPoints).ceil().clamp(1, ranges.length);
    final sampled = <double>[];
    for (var i = 0; i < ranges.length; i += step) {
      final v = ranges[i];
      sampled.add(v.isFinite ? v.clamp(0, rangeMax) : rangeMax);
    }

    final dataEntries = sampled.map((v) => RadarEntry(value: v)).toList();

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Text(
            'LaserScan  ${ranges.length} pts  '
            'angle: ${angleMin.toStringAsFixed(2)}…${angleMax.toStringAsFixed(2)} rad  '
            'max: ${rangeMax.toStringAsFixed(1)} m',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          Expanded(
            child: RadarChart(
              RadarChartData(
                dataSets: [
                  RadarDataSet(
                    dataEntries: dataEntries,
                    fillColor: Colors.blue.withValues(alpha: 0.3),
                    borderColor: Colors.blue,
                    borderWidth: 1.5,
                    entryRadius: 0,
                  ),
                ],
                radarBackgroundColor: Colors.transparent,
                borderData: FlBorderData(show: false),
                radarBorderData:
                    const BorderSide(color: Colors.grey, width: 0.5),
                tickCount: 4,
                ticksTextStyle: const TextStyle(fontSize: 9),
                tickBorderData:
                    const BorderSide(color: Colors.grey, width: 0.5),
                getTitle: (index, angle) {
                  if (sampled.isEmpty) return RadarChartTitle(text: '');
                  final fraction = index / sampled.length;
                  final actualAngle = angleMin + fraction * (angleMax - angleMin);
                  if (index % (sampled.length ~/ 4).clamp(1, sampled.length) == 0) {
                    return RadarChartTitle(
                        text: '${(actualAngle * 180 / pi).toStringAsFixed(0)}°');
                  }
                  return RadarChartTitle(text: '');
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../utils/ros_msg.dart';
import '../../utils/time_series.dart';
import '../charts/time_series_chart.dart';
import 'viz_common.dart';

/// std_msgs numbers (`data: 1.5`), *MultiArray (`data: [..]`) and sensor
/// messages with one value field (Temperature, FluidPressure, ...).
class ScalarChartWidget extends MsgViz {
  /// Dotted path of the value inside the message.
  final String path;
  final String unit;

  const ScalarChartWidget({
    super.key,
    required super.topic,
    required super.msg,
    this.path = 'data',
    this.unit = '',
  });

  @override
  State<ScalarChartWidget> createState() => _ScalarChartWidgetState();
}

class _ScalarChartWidgetState extends MsgVizState<ScalarChartWidget> {
  static const _maxArraySeries = 8;
  final List<TimeSeries> _series = [];
  List<double?> _current = const [];
  double _min = double.infinity, _max = double.negativeInfinity;
  double _sum = 0;
  int _n = 0;
  int _arrayLength = 0;

  bool get _isArray => field(widget.msg, widget.path) is List;

  @override
  void onMessage(Map<String, dynamic> msg) {
    final raw = field(msg, widget.path);
    _current = raw is List ? doubleList(raw) : [asDouble(raw)];
    _arrayLength = raw is List ? raw.length : 1;
    final shown = math.min(_current.length, _maxArraySeries);
    while (_series.length < shown) {
      _series.add(TimeSeries(maxAge: 60));
    }
    for (var i = 0; i < shown; i++) {
      final v = _current[i];
      if (v == null) continue;
      _series[i].add(v);
      if (i == 0 || !_isArray) {
        _min = math.min(_min, v);
        _max = math.max(_max, v);
        _sum += v;
        _n++;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final v = _current.isEmpty ? null : _current.first;
    final mag = v == null ? 0.0 : v.abs();
    final chart = TimeSeriesChart(
      height: 220,
      unit: widget.unit,
      window: 30,
      // Keep ~1% of the value as the smallest span so noise is not magnified
      minSpan: math.max(mag * 0.01, 1e-6),
      series: [
        for (var i = 0; i < _series.length; i++)
          ChartSeries(_isArray ? '[$i]' : widget.path, AxisColors.at(_isArray ? i : 2), _series[i]),
      ],
    );

    if (_isArray) {
      return VizPage(children: [
        VizCard(
          title: 'Values ($_arrayLength)',
          child: Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              for (var i = 0; i < _current.length && i < 32; i++)
                SizedBox(
                  width: 90,
                  child: StatTile(
                    label: '[$i]',
                    value: _current[i] == null ? '—' : fmtNum(_current[i]!),
                    valueSize: 16,
                  ),
                ),
            ],
          ),
        ),
        VizCard(
          title: _arrayLength > _maxArraySeries
              ? 'History (first $_maxArraySeries)'
              : 'History',
          child: chart,
        ),
      ]);
    }

    return VizPage(children: [
      VizCard(
        child: StatTile(
          label: 'Current value',
          value: v == null ? '—' : fmtNum(v, sig: 6),
          unit: widget.unit,
          valueSize: 40,
        ),
      ),
      VizCard(
        child: StatRow([
          StatTile(label: 'Min', value: _n == 0 ? '—' : fmtNum(_min), valueSize: 16),
          StatTile(label: 'Max', value: _n == 0 ? '—' : fmtNum(_max), valueSize: 16),
          StatTile(label: 'Average', value: _n == 0 ? '—' : fmtNum(_sum / _n), valueSize: 16),
        ]),
      ),
      VizCard(title: 'Last 30 s', child: chart),
    ]);
  }
}

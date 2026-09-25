import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../utils/ros_msg.dart';
import '../../utils/time_series.dart';
import '../charts/time_series_chart.dart';
import 'viz_common.dart';

class _Joint {
  final String name;
  double? pos, vel, eff;
  double lo = double.infinity, hi = double.negativeInfinity;
  final posHist = TimeSeries(), velHist = TimeSeries();
  _Joint(this.name);
}

/// sensor_msgs/JointState: one row per joint, chart for the selected one.
class JointStateWidget extends MsgViz {
  const JointStateWidget({super.key, required super.topic, required super.msg});

  @override
  State<JointStateWidget> createState() => _JointStateWidgetState();
}

class _JointStateWidgetState extends MsgVizState<JointStateWidget> {
  final Map<String, _Joint> _joints = {};
  String? _selected;
  bool _degrees = true;

  @override
  void onMessage(Map<String, dynamic> msg) {
    final names = asList(msg['name']).map((e) => e.toString()).toList();
    final pos = doubleList(msg['position']);
    final vel = doubleList(msg['velocity']);
    final eff = doubleList(msg['effort']);
    for (var i = 0; i < names.length; i++) {
      final j = _joints.putIfAbsent(names[i], () => _Joint(names[i]));
      j.pos = i < pos.length ? pos[i] : null;
      j.vel = i < vel.length ? vel[i] : null;
      j.eff = i < eff.length ? eff[i] : null;
      if (j.pos != null) {
        j.lo = math.min(j.lo, j.pos!);
        j.hi = math.max(j.hi, j.pos!);
        j.posHist.add(j.pos!);
      }
      if (j.vel != null) j.velHist.add(j.vel!);
    }
    _selected ??= names.isEmpty ? null : names.first;
  }

  String _angle(double? rad) {
    if (rad == null) return '—';
    return _degrees ? '${radToDeg(rad).toStringAsFixed(1)}°' : fmtNum(rad);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sel = _joints[_selected];
    final hasEffort = _joints.values.any((j) => j.eff != null);

    return VizPage(children: [
      VizCard(
        title: 'Joints (${_joints.length})',
        trailing: SegmentedButton<bool>(
          showSelectedIcon: false,
          style: const ButtonStyle(visualDensity: VisualDensity.compact),
          segments: const [
            ButtonSegment(value: true, label: Text('deg')),
            ButtonSegment(value: false, label: Text('rad')),
          ],
          selected: {_degrees},
          onSelectionChanged: (s) => setState(() => _degrees = s.first),
        ),
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
        child: Column(
          children: [
            _header(context, hasEffort),
            for (final j in _joints.values) _row(context, j, hasEffort, cs),
          ],
        ),
      ),
      if (sel != null)
        VizCard(
          title: sel.name,
          child: Column(
            children: [
              TimeSeriesChart(
                title: 'Position (rad)',
                unit: 'rad',
                minSpan: 0.05,
                series: [ChartSeries('position', AxisColors.z, sel.posHist)],
              ),
              const SizedBox(height: 12),
              TimeSeriesChart(
                title: 'Velocity (rad/s)',
                unit: 'rad/s',
                minSpan: 0.1,
                includeZero: true,
                series: [ChartSeries('velocity', AxisColors.at(3), sel.velHist)],
              ),
            ],
          ),
        ),
    ]);
  }

  Widget _header(BuildContext context, bool hasEffort) {
    final style = TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(children: [
        Expanded(flex: 5, child: Text('Joint', style: style)),
        Expanded(flex: 3, child: Text('Position', style: style, textAlign: TextAlign.right)),
        Expanded(flex: 3, child: Text(_degrees ? 'Vel °/s' : 'Vel rad/s', style: style, textAlign: TextAlign.right)),
        if (hasEffort) Expanded(flex: 3, child: Text('Effort', style: style, textAlign: TextAlign.right)),
      ]),
    );
  }

  Widget _row(BuildContext context, _Joint j, bool hasEffort, ColorScheme cs) {
    const numStyle = TextStyle(fontFeatures: [FontFeature.tabularFigures()], fontWeight: FontWeight.w600);
    final selected = j.name == _selected;
    final span = j.hi - j.lo;
    final frac = (j.pos == null || span <= 1e-9) ? null : (j.pos! - j.lo) / span;
    final vel = j.vel == null ? '—' : _degrees ? radToDeg(j.vel!).toStringAsFixed(1) : fmtNum(j.vel!);

    return InkWell(
      onTap: () => setState(() => _selected = j.name),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
        decoration: BoxDecoration(
          color: selected ? cs.primary.withValues(alpha: 0.10) : null,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            Row(children: [
              Expanded(
                flex: 5,
                child: Text(j.name, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontWeight: selected ? FontWeight.w700 : FontWeight.w500)),
              ),
              Expanded(flex: 3, child: Text(_angle(j.pos), style: numStyle, textAlign: TextAlign.right)),
              Expanded(flex: 3, child: Text(vel, style: numStyle, textAlign: TextAlign.right)),
              if (hasEffort)
                Expanded(
                  flex: 3,
                  child: Text(j.eff == null ? '—' : fmtNum(j.eff!, sig: 3),
                      style: numStyle, textAlign: TextAlign.right),
                ),
            ]),
            const SizedBox(height: 4),
            // Where the joint is within the range it has moved through so far
            SizedBox(
              height: 4,
              child: frac == null
                  ? const SizedBox.shrink()
                  : LinearProgressIndicator(
                      value: frac,
                      borderRadius: BorderRadius.circular(2),
                      backgroundColor: cs.outlineVariant.withValues(alpha: 0.5),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

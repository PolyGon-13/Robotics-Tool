import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../utils/ros_msg.dart';
import '../../utils/time_series.dart';
import '../charts/time_series_chart.dart';
import 'viz_common.dart';

/// geometry_msgs/Twist and TwistStamped.
class TwistWidget extends MsgViz {
  const TwistWidget({super.key, required super.topic, required super.msg});

  @override
  State<TwistWidget> createState() => _TwistWidgetState();
}

class _TwistWidgetState extends MsgVizState<TwistWidget> {
  static const _axes = ['x', 'y', 'z'];
  final _lin = [TimeSeries(), TimeSeries(), TimeSeries()];
  final _ang = [TimeSeries(), TimeSeries(), TimeSeries()];
  // Components that were ever non-zero; ground robots usually only use
  // linear.x and angular.z, so the rest stay hidden.
  final _linUsed = [true, false, false];
  final _angUsed = [false, false, true];
  var _l = [0.0, 0.0, 0.0], _a = [0.0, 0.0, 0.0];
  double _peakLinear = 0.5, _peakAngular = 1.0;

  @override
  void onMessage(Map<String, dynamic> msg) {
    final twist = msg.containsKey('twist') ? msg['twist'] : msg; // TwistStamped
    _l = [for (final k in _axes) numAt(twist, 'linear.$k')];
    _a = [for (final k in _axes) numAt(twist, 'angular.$k')];
    for (var i = 0; i < 3; i++) {
      _lin[i].add(_l[i]);
      _ang[i].add(_a[i]);
      if (_l[i].abs() > 1e-6) _linUsed[i] = true;
      if (_a[i].abs() > 1e-6) _angUsed[i] = true;
    }
    // Scale follows recent peaks and slowly relaxes, so one spike does not
    // shrink the arrow for the rest of the session
    _peakLinear = math.max(0.5, math.max(_peakLinear * 0.995, math.sqrt(_l[0] * _l[0] + _l[1] * _l[1])));
    _peakAngular = math.max(1.0, math.max(_peakAngular * 0.995, _a[2].abs()));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return VizPage(children: [
      VizCard(
        title: 'Command',
        child: Row(
          children: [
            SizedBox(
              width: 140,
              height: 140,
              child: CustomPaint(
                painter: _TwistPainter(
                  vx: _l[0], vy: _l[1], wz: _a[2],
                  peakLinear: _peakLinear, peakAngular: _peakAngular,
                  colors: cs,
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  StatTile.num('Forward', _l[0], unit: 'm/s', color: AxisColors.x),
                  if (_linUsed[1]) ...[
                    const SizedBox(height: 8),
                    StatTile.num('Sideways', _l[1], unit: 'm/s', color: AxisColors.y),
                  ],
                  const SizedBox(height: 8),
                  StatTile(
                    label: 'Turn (${_a[2] > 0 ? 'left' : _a[2] < 0 ? 'right' : '—'})',
                    value: fmtFixed(radToDeg(_a[2]), 1),
                    unit: '°/s',
                    color: AxisColors.z,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      VizCard(
        title: 'Linear velocity',
        child: TimeSeriesChart(
          unit: 'm/s',
          minSpan: 0.1,
          includeZero: true,
          series: [
            for (var i = 0; i < 3; i++)
              if (_linUsed[i]) ChartSeries(_axes[i], AxisColors.at(i), _lin[i]),
          ],
        ),
      ),
      VizCard(
        title: 'Angular velocity',
        child: TimeSeriesChart(
          unit: 'rad/s',
          minSpan: 0.1,
          includeZero: true,
          series: [
            for (var i = 0; i < 3; i++)
              if (_angUsed[i]) ChartSeries(_axes[i], AxisColors.at(i), _ang[i]),
          ],
        ),
      ),
    ]);
  }
}

/// Robot seen from above (forward = up): arrow for linear velocity, arc for
/// rotation. Lengths are relative to the largest value seen so far.
class _TwistPainter extends CustomPainter {
  final double vx, vy, wz, peakLinear, peakAngular;
  final ColorScheme colors;

  _TwistPainter({
    required this.vx,
    required this.vy,
    required this.wz,
    required this.peakLinear,
    required this.peakAngular,
    required this.colors,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2 - 6;

    canvas.drawCircle(c, r, Paint()
      ..style = PaintingStyle.stroke
      ..color = colors.outlineVariant);
    // Robot body
    final body = RRect.fromRectAndRadius(
        Rect.fromCenter(center: c, width: 30, height: 38), const Radius.circular(8));
    canvas.drawRRect(body, Paint()..color = colors.surfaceContainerHighest);
    canvas.drawRRect(body, Paint()
      ..style = PaintingStyle.stroke
      ..color = colors.outline);
    canvas.drawCircle(c + const Offset(0, -12), 3, Paint()..color = colors.primary);

    // Rotation arc: CCW (left turn) for positive wz
    if (wz.abs() > 1e-4) {
      final sweep = (wz / peakAngular).clamp(-1.0, 1.0) * math.pi * 0.9;
      final rect = Rect.fromCircle(center: c, radius: r - 8);
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round
        ..color = AxisColors.z;
      canvas.drawArc(rect, -math.pi / 2, -sweep, false, paint);
      final end = -math.pi / 2 - sweep;
      final tip = c + Offset(math.cos(end), math.sin(end)) * (r - 8);
      canvas.drawCircle(tip, 5, Paint()..color = AxisColors.z);
    }

    // Linear velocity arrow (x forward = up, y left = left)
    final len = math.sqrt(vx * vx + vy * vy);
    if (len > 1e-4) {
      final k = (len / peakLinear).clamp(0.0, 1.0) * (r - 14) / len;
      final tip = c + Offset(-vy * k, -vx * k);
      final paint = Paint()
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round
        ..color = AxisColors.x;
      canvas.drawLine(c, tip, paint);
      final dir = (tip - c) / (tip - c).distance;
      final side = Offset(-dir.dy, dir.dx);
      final head = Path()
        ..moveTo(tip.dx + dir.dx * 8, tip.dy + dir.dy * 8)
        ..lineTo(tip.dx + side.dx * 7, tip.dy + side.dy * 7)
        ..lineTo(tip.dx - side.dx * 7, tip.dy - side.dy * 7)
        ..close();
      canvas.drawPath(head, Paint()..color = AxisColors.x);
    }
  }

  @override
  bool shouldRepaint(covariant _TwistPainter old) => true;
}

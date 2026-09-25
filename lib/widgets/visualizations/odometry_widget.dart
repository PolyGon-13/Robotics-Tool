import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../utils/ros_msg.dart';
import '../../utils/time_series.dart';
import '../charts/time_series_chart.dart';
import 'viz_common.dart';

class OdometryWidget extends MsgViz {
  const OdometryWidget({super.key, required super.topic, required super.msg});

  @override
  State<OdometryWidget> createState() => _OdometryWidgetState();
}

class _OdometryWidgetState extends MsgVizState<OdometryWidget> {
  static const _maxTrail = 3000;
  final List<Offset> _trail = [];
  double _distance = 0;
  double _x = 0, _y = 0, _yaw = 0, _vx = 0, _vy = 0, _wz = 0;
  String _frames = '';

  final _linX = TimeSeries(), _linY = TimeSeries(), _angZ = TimeSeries();

  @override
  void onMessage(Map<String, dynamic> msg) {
    _x = numAt(msg, 'pose.pose.position.x');
    _y = numAt(msg, 'pose.pose.position.y');
    _yaw = quatMsgToEuler(field(msg, 'pose.pose.orientation')).yaw;
    _vx = numAt(msg, 'twist.twist.linear.x');
    _vy = numAt(msg, 'twist.twist.linear.y');
    _wz = numAt(msg, 'twist.twist.angular.z');
    final parent = field(msg, 'header.frame_id')?.toString() ?? '';
    final child = msg['child_frame_id']?.toString() ?? '';
    _frames = parent.isEmpty && child.isEmpty ? '' : '$parent -> $child';

    final p = Offset(_x, _y);
    if (_trail.isEmpty || (p - _trail.last).distance >= 0.005) {
      if (_trail.isNotEmpty) _distance += (p - _trail.last).distance;
      _trail.add(p);
      if (_trail.length > _maxTrail) _trail.removeAt(0);
    }
    _linX.add(_vx);
    _linY.add(_vy);
    _angZ.add(_wz);
  }

  @override
  Widget build(BuildContext context) {
    // Differential-drive robots never move sideways; only show y when it moves
    final vy = _linY.range();
    final showVy = vy != null && (vy.$1.abs() > 1e-3 || vy.$2.abs() > 1e-3);
    return VizPage(children: [
      VizCard(
        title: 'Pose',
        trailing: _frames.isEmpty
            ? null
            : Text(_frames, style: Theme.of(context).textTheme.bodySmall),
        child: StatRow([
          StatTile.num('X', _x, unit: 'm'),
          StatTile.num('Y', _y, unit: 'm'),
          StatTile(label: 'Heading', value: '${radToDeg(_yaw).toStringAsFixed(1)}°'),
        ]),
      ),
      VizCard(
        title: 'Trajectory',
        trailing: TextButton.icon(
          onPressed: () => setState(() {
            _trail
              ..clear()
              ..add(Offset(_x, _y));
            _distance = 0;
          }),
          icon: const Icon(Icons.restart_alt, size: 18),
          label: const Text('Clear'),
        ),
        child: Column(
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: CustomPaint(
                painter: _TrajectoryPainter(
                  trail: _trail,
                  pose: Offset(_x, _y),
                  yaw: _yaw,
                  colors: Theme.of(context).colorScheme,
                ),
              ),
            ),
            const SizedBox(height: 8),
            StatRow([
              StatTile.num('Distance travelled', _distance, unit: 'm', valueSize: 16),
              StatTile(label: 'Trail points', value: '${_trail.length}', valueSize: 16),
            ]),
          ],
        ),
      ),
      VizCard(
        title: 'Velocity',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            StatRow([
              StatTile.num('Forward', _vx, unit: 'm/s'),
              if (showVy) StatTile.num('Sideways', _vy, unit: 'm/s'),
              StatTile(
                  label: 'Turn rate',
                  value: radToDeg(_wz).toStringAsFixed(1),
                  unit: '°/s'),
            ]),
            const SizedBox(height: 12),
            TimeSeriesChart(
              title: 'Linear (m/s)',
              unit: 'm/s',
              minSpan: 0.1,
              includeZero: true,
              series: [
                ChartSeries('x', AxisColors.x, _linX),
                if (showVy) ChartSeries('y', AxisColors.y, _linY),
              ],
            ),
            const SizedBox(height: 12),
            TimeSeriesChart(
              title: 'Angular z (rad/s)',
              unit: 'rad/s',
              minSpan: 0.1,
              includeZero: true,
              series: [ChartSeries('z', AxisColors.z, _angZ)],
            ),
          ],
        ),
      ),
    ]);
  }
}

/// Equal-aspect XY plot of the path with the current pose as an arrow.
class _TrajectoryPainter extends CustomPainter {
  final List<Offset> trail;
  final Offset pose;
  final double yaw;
  final ColorScheme colors;

  _TrajectoryPainter({
    required this.trail,
    required this.pose,
    required this.yaw,
    required this.colors,
  });

  @override
  void paint(Canvas canvas, Size size) {
    var minX = pose.dx, maxX = pose.dx, minY = pose.dy, maxY = pose.dy;
    for (final p in trail) {
      minX = math.min(minX, p.dx);
      maxX = math.max(maxX, p.dx);
      minY = math.min(minY, p.dy);
      maxY = math.max(maxY, p.dy);
    }
    // At least 2 m across so a robot standing still is not zoomed to noise
    final extent = math.max(2.0, math.max(maxX - minX, maxY - minY) * 1.2);
    final cx = (minX + maxX) / 2, cy = (minY + maxY) / 2;
    const margin = 28.0;
    final scale = (size.shortestSide - margin * 2) / extent;
    final center = size.center(Offset.zero);
    // Map frame: x right, y up (REP 103 top-down view)
    Offset toScreen(Offset p) =>
        Offset(center.dx + (p.dx - cx) * scale, center.dy - (p.dy - cy) * scale);

    final grid = Paint()
      ..color = colors.outlineVariant.withValues(alpha: 0.7)
      ..strokeWidth = 0.8;
    final step = niceStep(extent / 5);
    final half = extent / 2 + step;
    final label = colors.onSurfaceVariant;
    for (var gx = ((cx - half) / step).floor() * step; gx <= cx + half; gx += step) {
      final x = toScreen(Offset(gx, 0)).dx;
      if (x < margin - 1 || x > size.width - margin + 1) continue;
      canvas.drawLine(Offset(x, margin), Offset(x, size.height - margin), grid);
      _text(canvas, fmtTick(gx, step), Offset(x, size.height - margin + 4), label, center: true);
    }
    for (var gy = ((cy - half) / step).floor() * step; gy <= cy + half; gy += step) {
      final y = toScreen(Offset(0, gy)).dy;
      if (y < margin - 1 || y > size.height - margin + 1) continue;
      canvas.drawLine(Offset(margin, y), Offset(size.width - margin, y), grid);
      _text(canvas, fmtTick(gy, step), Offset(2, y - 6), label);
    }
    _text(canvas, 'x (m)', Offset(size.width - margin - 24, size.height - 14), label);
    _text(canvas, 'y (m)', Offset(margin + 2, 4), label);

    if (trail.length > 1) {
      final path = Path()..moveTo(toScreen(trail.first).dx, toScreen(trail.first).dy);
      for (final p in trail.skip(1)) {
        final s = toScreen(p);
        path.lineTo(s.dx, s.dy);
      }
      canvas.drawPath(path, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeJoin = StrokeJoin.round
        ..color = colors.primary.withValues(alpha: 0.75));
      final start = toScreen(trail.first);
      canvas.drawCircle(start, 5, Paint()..color = colors.outline);
    }

    // Current pose arrow; screen y is flipped so heading rotates clockwise-negative
    final p = toScreen(pose);
    canvas.save();
    canvas.translate(p.dx, p.dy);
    canvas.rotate(-yaw);
    final arrow = Path()
      ..moveTo(14, 0)
      ..lineTo(-8, -8)
      ..lineTo(-4, 0)
      ..lineTo(-8, 8)
      ..close();
    canvas.drawPath(arrow, Paint()..color = const Color(0xFFE53935));
    canvas.restore();
  }

  void _text(Canvas canvas, String t, Offset at, Color color, {bool center = false}) {
    final tp = TextPainter(
      text: TextSpan(text: t, style: TextStyle(color: color, fontSize: 10)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center ? at - Offset(tp.width / 2, 0) : at);
  }

  @override
  bool shouldRepaint(covariant _TrajectoryPainter old) => true;
}

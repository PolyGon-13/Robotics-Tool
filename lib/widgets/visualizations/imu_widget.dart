import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../utils/ros_msg.dart';
import '../../utils/time_series.dart';
import '../charts/time_series_chart.dart';
import 'viz_common.dart';

/// sensor_msgs/Imu: attitude, gyro and accelerometer.
class ImuWidget extends MsgViz {
  const ImuWidget({super.key, required super.topic, required super.msg});

  @override
  State<ImuWidget> createState() => _ImuWidgetState();
}

class _ImuWidgetState extends MsgVizState<ImuWidget> {
  static const _axes = ['x', 'y', 'z'];
  final _gyro = [TimeSeries(), TimeSeries(), TimeSeries()];
  final _acc = [TimeSeries(), TimeSeries(), TimeSeries()];
  Euler _rpy = const Euler(0, 0, 0);
  bool _hasOrientation = true;
  double _accNorm = 0;

  @override
  void onMessage(Map<String, dynamic> msg) {
    // REP 145: orientation_covariance[0] == -1 means "no orientation"
    _hasOrientation = asDouble(field(msg, 'orientation_covariance.0')) != -1;
    _rpy = quatMsgToEuler(msg['orientation']);
    final a = [for (final k in _axes) numAt(msg, 'linear_acceleration.$k')];
    for (var i = 0; i < 3; i++) {
      _gyro[i].add(numAt(msg, 'angular_velocity.${_axes[i]}'));
      _acc[i].add(a[i]);
    }
    _accNorm = math.sqrt(a[0] * a[0] + a[1] * a[1] + a[2] * a[2]);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return VizPage(children: [
      if (_hasOrientation)
        VizCard(
          title: 'Orientation',
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: CustomPaint(
                        painter: _HorizonPainter(roll: _rpy.roll, pitch: _rpy.pitch, colors: cs),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: CustomPaint(painter: _CompassPainter(yaw: _rpy.yaw, colors: cs)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              StatRow([
                _deg('Roll', _rpy.roll, AxisColors.x),
                _deg('Pitch', _rpy.pitch, AxisColors.y),
                _deg('Yaw', _rpy.yaw, AxisColors.z),
              ]),
            ],
          ),
        )
      else
        const VizCard(
          title: 'Orientation',
          child: Text('This IMU does not report orientation '
              '(orientation_covariance[0] = -1).'),
        ),
      VizCard(
        title: 'Angular velocity',
        child: TimeSeriesChart(
          unit: 'rad/s',
          minSpan: 0.1,
          includeZero: true,
          series: [
            for (var i = 0; i < 3; i++) ChartSeries(_axes[i], AxisColors.at(i), _gyro[i]),
          ],
        ),
      ),
      VizCard(
        title: 'Linear acceleration',
        trailing: Text('|a| = ${fmtNum(_accNorm, sig: 3)} m/s²',
            style: Theme.of(context).textTheme.bodySmall),
        child: TimeSeriesChart(
          unit: 'm/s²',
          minSpan: 1,
          series: [
            for (var i = 0; i < 3; i++) ChartSeries(_axes[i], AxisColors.at(i), _acc[i]),
          ],
        ),
      ),
    ]);
  }

  Widget _deg(String label, double rad, Color color) => StatTile(
      label: label, value: '${fmtFixed(radToDeg(rad), 1)}°', color: color);
}

/// Artificial horizon: sky/ground split rotated by roll, shifted by pitch.
class _HorizonPainter extends CustomPainter {
  final double roll, pitch;
  final ColorScheme colors;
  _HorizonPainter({required this.roll, required this.pitch, required this.colors});

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2 - 2;
    canvas.save();
    canvas.clipPath(Path()..addOval(Rect.fromCircle(center: c, radius: r)));
    canvas.translate(c.dx, c.dy);
    canvas.rotate(-roll);
    // 45° of pitch moves the horizon by one radius. REP 103: positive pitch
    // is nose down, so the horizon moves up (more ground visible).
    final shift = (-pitch / (math.pi / 4)).clamp(-1.5, 1.5) * r;
    canvas.drawRect(Rect.fromLTRB(-2 * r, -2 * r, 2 * r, shift),
        Paint()..color = const Color(0xFF64B5F6));
    canvas.drawRect(Rect.fromLTRB(-2 * r, shift, 2 * r, 2 * r),
        Paint()..color = const Color(0xFFA1887F));
    canvas.drawLine(Offset(-2 * r, shift), Offset(2 * r, shift),
        Paint()..color = Colors.white..strokeWidth = 2);
    canvas.restore();
    // Fixed aircraft symbol
    final sym = Paint()
      ..color = Colors.black87
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(c + Offset(-r * 0.5, 0), c + Offset(-r * 0.15, 0), sym);
    canvas.drawLine(c + Offset(r * 0.15, 0), c + Offset(r * 0.5, 0), sym);
    canvas.drawCircle(c, 3, sym);
    canvas.drawCircle(c, r, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = colors.outline);
  }

  @override
  bool shouldRepaint(covariant _HorizonPainter old) =>
      old.roll != roll || old.pitch != pitch || old.colors != colors;
}

/// Heading dial: yaw 0 (+x) at the top, positive yaw turns counter-clockwise.
class _CompassPainter extends CustomPainter {
  final double yaw;
  final ColorScheme colors;
  _CompassPainter({required this.yaw, required this.colors});

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2 - 2;
    canvas.drawCircle(c, r, Paint()..color = colors.surfaceContainerHighest);
    canvas.drawCircle(c, r, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = colors.outline);
    final tick = Paint()
      ..color = colors.onSurfaceVariant
      ..strokeWidth = 1.5;
    for (var d = 0; d < 360; d += 30) {
      final a = -math.pi / 2 - d * math.pi / 180;
      final dir = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(c + dir * (r - (d % 90 == 0 ? 12 : 6)), c + dir * r, tick);
    }
    for (final (label, d) in [('0°', 0), ('90°', 90), ('180°', 180), ('-90°', 270)]) {
      final a = -math.pi / 2 - d * math.pi / 180;
      final tp = TextPainter(
        text: TextSpan(text: label, style: TextStyle(fontSize: 10, color: colors.onSurfaceVariant)),
        textDirection: TextDirection.ltr,
      )..layout();
      final p = c + Offset(math.cos(a), math.sin(a)) * (r - 22);
      tp.paint(canvas, p - Offset(tp.width / 2, tp.height / 2));
    }
    final a = -math.pi / 2 - yaw;
    final dir = Offset(math.cos(a), math.sin(a));
    canvas.drawLine(c, c + dir * (r - 16), Paint()
      ..color = AxisColors.z
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round);
    canvas.drawCircle(c, 4, Paint()..color = AxisColors.z);
  }

  @override
  bool shouldRepaint(covariant _CompassPainter old) => old.yaw != yaw || old.colors != colors;
}

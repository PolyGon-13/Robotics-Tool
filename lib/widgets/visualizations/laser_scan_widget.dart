import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../utils/scan_geometry.dart';
import '../../utils/time_series.dart';
import 'viz_common.dart';

/// Top-down view of a LaserScan: robot in the center, forward is up.
class LaserScanWidget extends MsgViz {
  const LaserScanWidget({super.key, required super.topic, required super.msg});

  @override
  State<LaserScanWidget> createState() => _LaserScanWidgetState();
}

class _LaserScanWidgetState extends MsgVizState<LaserScanWidget> {
  late ScanSummary _scan;
  double? _manualRange; // null = auto zoom
  double _pinchStart = 1;

  @override
  void onMessage(Map<String, dynamic> msg) => _scan = parseScan(msg);

  double get _viewRange => _manualRange ?? _scan.autoViewRange();

  void _zoom(double factor) => setState(() {
        final max = _scan.rangeMax > 0 ? _scan.rangeMax * 1.2 : 100.0;
        _manualRange = (_viewRange * factor).clamp(0.25, max);
      });

  @override
  Widget build(BuildContext context) {
    final closest = _scan.closest;
    final cs = Theme.of(context).colorScheme;

    return VizPage(children: [
      VizCard(
        padding: const EdgeInsets.all(8),
        child: Column(
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: GestureDetector(
                onScaleStart: (_) => _pinchStart = _viewRange,
                onScaleUpdate: (d) {
                  if (d.pointerCount < 2) return;
                  setState(() => _manualRange = (_pinchStart / d.scale).clamp(0.25, 100.0));
                },
                onDoubleTap: () => setState(() => _manualRange = null),
                child: CustomPaint(
                  painter: _ScanPainter(
                    scan: _scan,
                    viewRange: _viewRange,
                    closest: closest,
                    colors: cs,
                  ),
                ),
              ),
            ),
            Row(
              children: [
                Text(
                  'View ±${fmtNum(_viewRange, sig: 2)} m'
                  '${_manualRange == null ? ' (auto)' : ''}',
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Zoom out',
                  icon: const Icon(Icons.zoom_out),
                  onPressed: () => _zoom(1.5),
                ),
                IconButton(
                  tooltip: 'Zoom in',
                  icon: const Icon(Icons.zoom_in),
                  onPressed: () => _zoom(1 / 1.5),
                ),
                IconButton(
                  tooltip: 'Auto zoom',
                  icon: Icon(Icons.fit_screen,
                      color: _manualRange == null ? cs.primary : null),
                  onPressed: () => setState(() => _manualRange = null),
                ),
              ],
            ),
          ],
        ),
      ),
      VizCard(
        title: 'Closest obstacle',
        child: StatRow([
          StatTile(
            label: 'Distance',
            value: closest == null ? '—' : fmtNum(closest.range, sig: 3),
            unit: 'm',
            color: closest == null ? null : _distanceColor(closest.range),
            valueSize: 28,
          ),
          StatTile(
            label: 'Direction',
            value: closest == null ? '—' : describeDirection(closest.angle),
            valueSize: 22,
          ),
        ]),
      ),
      VizCard(
        title: 'Nearest by side',
        child: StatRow([
          _sector('Front', _scan.front),
          _sector('Left', _scan.left),
          _sector('Right', _scan.right),
          _sector('Back', _scan.back),
        ]),
      ),
      VizCard(
        title: 'Scan',
        child: StatRow([
          StatTile(
              label: 'Valid returns',
              value: '${_scan.points.length}/${_scan.total}',
              valueSize: 16),
          StatTile(
              label: 'Field of view',
              value: '${fmtNum((_scan.angleMax - _scan.angleMin) * 180 / math.pi, sig: 3)}°',
              valueSize: 16),
          StatTile(
              label: 'Range limits',
              value: '${fmtNum(_scan.rangeMin, sig: 2)}–${fmtNum(_scan.rangeMax, sig: 3)}',
              unit: 'm',
              valueSize: 16),
        ]),
      ),
    ]);
  }

  Widget _sector(String label, double? d) => StatTile(
        label: label,
        value: d == null ? '—' : fmtNum(d, sig: 3),
        unit: d == null ? '' : 'm',
        color: d == null ? null : _distanceColor(d),
        valueSize: 18,
      );
}

/// Red when close enough to matter, orange when getting close.
Color? _distanceColor(double m) {
  if (m < 0.5) return const Color(0xFFD32F2F);
  if (m < 1.0) return const Color(0xFFEF6C00);
  return null;
}

class _ScanPainter extends CustomPainter {
  final ScanSummary scan;
  final double viewRange;
  final ScanPoint? closest;
  final ColorScheme colors;

  _ScanPainter({
    required this.scan,
    required this.viewRange,
    required this.closest,
    required this.colors,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - 14;
    final s = radius / viewRange;
    // Sensor frame (x forward, y left) → screen (forward = up)
    Offset toScreen(double x, double y) => Offset(c.dx - y * s, c.dy - x * s);

    canvas.save();
    canvas.clipRect(Offset.zero & size);

    // Field of view wedge (e.g. 270° lidars)
    final fov = scan.angleMax - scan.angleMin;
    if (fov > 0 && fov < 2 * math.pi - 1e-3) {
      final rect = Rect.fromCircle(center: c, radius: radius);
      // screen angle of sensor angle a: forward (a=0) is -90°, CCW sensor = CCW on screen
      canvas.drawArc(rect, -math.pi / 2 - scan.angleMax, fov, true,
          Paint()..color = colors.primary.withValues(alpha: 0.05));
    }

    // Range rings
    final step = niceStep(viewRange / 4);
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = colors.outlineVariant;
    for (var r = step; r <= viewRange + 1e-9; r += step) {
      canvas.drawCircle(c, r * s, ringPaint);
      _text(canvas, '${fmtTick(r, step)} m',
          c + Offset(4, -r * s + 2), colors.onSurfaceVariant, 10);
    }
    final axis = Paint()
      ..color = colors.outlineVariant
      ..strokeWidth = 1;
    canvas.drawLine(Offset(c.dx, c.dy - radius), Offset(c.dx, c.dy + radius), axis);
    canvas.drawLine(Offset(c.dx - radius, c.dy), Offset(c.dx + radius, c.dy), axis);
    _text(canvas, 'FRONT', Offset(c.dx, 2), colors.primary, 11, center: true, bold: true);
    _text(canvas, 'L', Offset(4, c.dy - 7), colors.onSurfaceVariant, 11, bold: true);
    _text(canvas, 'R', Offset(size.width - 12, c.dy - 7), colors.onSurfaceVariant, 11, bold: true);

    // Returns, colored by distance (near = red, far = blue)
    final dot = Paint();
    final dotR = math.max(1.6, math.min(3.0, size.shortestSide / 160));
    for (final p in scan.points) {
      if (p.range > viewRange * 1.5) continue;
      final hue = (p.range / viewRange).clamp(0.0, 1.0) * 220;
      dot.color = HSVColor.fromAHSV(1, hue, 0.85, 0.9).toColor();
      canvas.drawCircle(toScreen(p.x, p.y), dotR, dot);
    }

    // Closest obstacle
    final cl = closest;
    if (cl != null && cl.range <= viewRange * 1.5) {
      final pt = toScreen(cl.x, cl.y);
      canvas.drawLine(c, pt, Paint()
        ..color = const Color(0xFFD32F2F).withValues(alpha: 0.7)
        ..strokeWidth = 1.5);
      canvas.drawCircle(pt, 7, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = const Color(0xFFD32F2F));
    }

    // Robot marker pointing forward
    final robot = Path()
      ..moveTo(c.dx, c.dy - 11)
      ..lineTo(c.dx - 7, c.dy + 7)
      ..lineTo(c.dx, c.dy + 3)
      ..lineTo(c.dx + 7, c.dy + 7)
      ..close();
    canvas.drawPath(robot, Paint()..color = colors.primary);
    canvas.restore();
  }

  void _text(Canvas canvas, String text, Offset at, Color color, double size,
      {bool center = false, bool bold = false}) {
    final tp = TextPainter(
      text: TextSpan(
          text: text,
          style: TextStyle(
              color: color,
              fontSize: size,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w400)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center ? at - Offset(tp.width / 2, 0) : at);
  }

  @override
  bool shouldRepaint(covariant _ScanPainter old) =>
      old.scan != scan || old.viewRange != viewRange || old.colors != colors;
}

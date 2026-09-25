import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../utils/time_series.dart';

/// Axis colors follow the RViz convention: x = red, y = green, z = blue.
class AxisColors {
  static const x = Color(0xFFE53935);
  static const y = Color(0xFF43A047);
  static const z = Color(0xFF1E88E5);
  static const extra = [
    Color(0xFFFB8C00), Color(0xFF8E24AA), Color(0xFF00897B),
    Color(0xFF6D4C41), Color(0xFFD81B60),
  ];
  static const xyz = [x, y, z];

  static Color at(int i) => i < 3 ? xyz[i] : extra[(i - 3) % extra.length];
}

class ChartSeries {
  final String label;
  final Color color;
  final TimeSeries data;
  final bool dashed;

  const ChartSeries(this.label, this.color, this.data, {this.dashed = false});
}

/// Live line chart over the last [window] seconds with a legend showing each
/// series' current value.
class TimeSeriesChart extends StatelessWidget {
  final List<ChartSeries> series;
  final String unit;
  final double window;

  /// Smallest y span shown, so sensor noise is not blown up to full height.
  final double minSpan;
  final bool includeZero;
  final double height;
  final String? title;

  const TimeSeriesChart({
    super.key,
    required this.series,
    this.unit = '',
    this.window = 20,
    this.minSpan = 0,
    this.includeZero = false,
    this.height = 160,
    this.title,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(title!, style: theme.textTheme.titleSmall),
          ),
        Wrap(
          spacing: 12,
          runSpacing: 2,
          children: [for (final s in series) _LegendItem(series: s, unit: unit)],
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: height,
          width: double.infinity,
          child: CustomPaint(
            painter: _ChartPainter(
              series: series,
              window: window,
              minSpan: minSpan,
              includeZero: includeZero,
              now: nowSeconds(),
              axisColor: theme.colorScheme.outlineVariant,
              labelColor: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

class _LegendItem extends StatelessWidget {
  final ChartSeries series;
  final String unit;

  const _LegendItem({required this.series, required this.unit});

  @override
  Widget build(BuildContext context) {
    final last = series.data.last;
    final value = last == null ? '—' : fmtNum(last.v);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10, height: 10,
          decoration: BoxDecoration(color: series.color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(series.label, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(width: 4),
        Text(
          unit.isEmpty ? value : '$value $unit',
          style: const TextStyle(
            fontFeatures: [FontFeature.tabularFigures()],
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ],
    );
  }
}

class _ChartPainter extends CustomPainter {
  final List<ChartSeries> series;
  final double window;
  final double minSpan;
  final bool includeZero;
  final double now;
  final Color axisColor;
  final Color labelColor;

  _ChartPainter({
    required this.series,
    required this.window,
    required this.minSpan,
    required this.includeZero,
    required this.now,
    required this.axisColor,
    required this.labelColor,
  });

  TextPainter _label(String text) => TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(color: labelColor, fontSize: 11,
              fontFeatures: const [FontFeature.tabularFigures()]),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

  @override
  void paint(Canvas canvas, Size size) {
    final t0 = now - window;
    double lo = double.infinity, hi = double.negativeInfinity;
    for (final s in series) {
      final r = s.data.range(since: t0);
      if (r == null) continue;
      lo = math.min(lo, r.$1);
      hi = math.max(hi, r.$2);
    }
    if (!lo.isFinite) {
      final tp = _label('No data yet');
      tp.paint(canvas, Offset((size.width - tp.width) / 2, (size.height - tp.height) / 2));
      return;
    }
    if (includeZero) {
      lo = math.min(lo, 0);
      hi = math.max(hi, 0);
    }
    final scale = NiceScale.of(lo, hi, maxTicks: 5, minSpan: minSpan);

    // Y labels decide the left margin, so they never wrap or overlap.
    final yLabels = [for (final v in scale.ticks) (v, _label(fmtTick(v, scale.step)))];
    final left = yLabels.map((e) => e.$2.width).reduce(math.max) + 6;
    const bottom = 16.0, top = 4.0, right = 8.0;
    final plot = Rect.fromLTRB(left, top, size.width - right, size.height - bottom);

    double sx(double t) => plot.left + (t - t0) / window * plot.width;
    double sy(double v) =>
        plot.bottom - (v - scale.min) / (scale.max - scale.min) * plot.height;

    final grid = Paint()
      ..color = axisColor.withValues(alpha: 0.6)
      ..strokeWidth = 0.7;
    for (final (v, tp) in yLabels) {
      final y = sy(v);
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y),
          v.abs() < scale.step * 1e-6 ? (Paint()..color = labelColor.withValues(alpha: 0.6)..strokeWidth = 1) : grid);
      tp.paint(canvas, Offset(left - 6 - tp.width, y - tp.height / 2));
    }

    // Time axis: seconds ago
    final tStep = niceStep(window / 4);
    for (var ago = 0.0; ago <= window + 1e-6; ago += tStep) {
      final x = sx(now - ago);
      canvas.drawLine(Offset(x, plot.top), Offset(x, plot.bottom), grid);
      final tp = _label(ago == 0 ? 'now' : '-${fmtTick(ago, tStep)}s');
      final lx = (x - tp.width / 2).clamp(plot.left, size.width - tp.width);
      tp.paint(canvas, Offset(lx, plot.bottom + 3));
    }

    canvas.save();
    canvas.clipRect(plot.inflate(1));
    for (final s in series) {
      final pts = s.data.samples.where((p) => p.t >= t0 - 1).toList();
      if (pts.isEmpty) continue;
      final path = Path()..moveTo(sx(pts.first.t), sy(pts.first.v));
      for (final p in pts.skip(1)) {
        path.lineTo(sx(p.t), sy(p.v));
      }
      final paint = Paint()
        ..color = s.color
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round;
      canvas.drawPath(s.dashed ? _dash(path) : path, paint);
      canvas.drawCircle(Offset(sx(pts.last.t), sy(pts.last.v)), 3, Paint()..color = s.color);
    }
    canvas.restore();
  }

  Path _dash(Path src) {
    final out = Path();
    for (final m in src.computeMetrics()) {
      for (var d = 0.0; d < m.length; d += 9) {
        out.addPath(m.extractPath(d, math.min(d + 5, m.length)), Offset.zero);
      }
    }
    return out;
  }

  @override
  bool shouldRepaint(covariant _ChartPainter old) => true;
}

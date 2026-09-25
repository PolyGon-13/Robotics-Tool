import 'package:flutter/material.dart';

import '../../utils/ros_msg.dart';
import '../../utils/time_series.dart';
import '../charts/time_series_chart.dart';
import 'viz_common.dart';

/// sensor_msgs/Range (ultrasonic / IR distance sensors).
class RangeWidget extends MsgViz {
  const RangeWidget({super.key, required super.topic, required super.msg});

  @override
  State<RangeWidget> createState() => _RangeWidgetState();
}

class _RangeWidgetState extends MsgVizState<RangeWidget> {
  final _hist = TimeSeries();

  @override
  void onMessage(Map<String, dynamic> msg) {
    final r = asDouble(msg['range']);
    if (r != null && r.isFinite) _hist.add(r);
  }

  @override
  Widget build(BuildContext context) {
    final msg = widget.msg;
    final r = asDouble(msg['range']);
    final lo = numAt(msg, 'min_range', 0);
    final hi = numAt(msg, 'max_range', 0);
    final type = asInt(msg['radiation_type']) == 1 ? 'Infrared' : 'Ultrasound';
    // REP 117: +inf = nothing detected, -inf = object closer than min_range
    final String text;
    Color? color;
    if (r == null || r.isNaN) {
      text = 'No reading';
    } else if (r == double.infinity || (hi > 0 && r > hi)) {
      text = 'Clear';
    } else if (r == double.negativeInfinity || r < lo) {
      text = 'Too close';
      color = const Color(0xFFD32F2F);
    } else {
      text = fmtNum(r, sig: 3);
      if (r < 0.3) color = const Color(0xFFD32F2F);
    }
    final frac = (r != null && r.isFinite && hi > lo) ? ((r - lo) / (hi - lo)).clamp(0.0, 1.0) : null;

    return VizPage(children: [
      VizCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            StatTile(
              label: 'Distance',
              value: text,
              unit: r != null && r.isFinite ? 'm' : '',
              color: color,
              valueSize: 44,
            ),
            const SizedBox(height: 10),
            if (frac != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(value: frac, minHeight: 12),
              ),
            const SizedBox(height: 6),
            Text(
              '$type · range ${fmtNum(lo)}–${fmtNum(hi)} m · '
              'field of view ${radToDeg(numAt(msg, 'field_of_view')).toStringAsFixed(0)}°',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      VizCard(
        title: 'Last 20 s',
        child: TimeSeriesChart(
          unit: 'm',
          minSpan: 0.1,
          includeZero: true,
          series: [ChartSeries('range', AxisColors.z, _hist)],
        ),
      ),
    ]);
  }
}

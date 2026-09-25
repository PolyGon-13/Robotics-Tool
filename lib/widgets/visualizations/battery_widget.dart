import 'package:flutter/material.dart';

import '../../utils/ros_msg.dart';
import '../../utils/time_series.dart';
import '../charts/time_series_chart.dart';
import 'viz_common.dart';

/// sensor_msgs/BatteryState.
class BatteryWidget extends MsgViz {
  const BatteryWidget({super.key, required super.topic, required super.msg});

  @override
  State<BatteryWidget> createState() => _BatteryWidgetState();
}

class _BatteryWidgetState extends MsgVizState<BatteryWidget> {
  final _voltage = TimeSeries(maxAge: 120);

  @override
  void onMessage(Map<String, dynamic> msg) {
    final v = asDouble(msg['voltage']);
    if (v != null && v.isFinite) _voltage.add(v);
  }

  static const _status = {
    1: ('Charging', Icons.bolt, Color(0xFF2E7D32)),
    2: ('Discharging', Icons.battery_std, Color(0xFF1565C0)),
    3: ('Not charging', Icons.power_off, Color(0xFF6D4C41)),
    4: ('Full', Icons.battery_full, Color(0xFF2E7D32)),
  };
  static const _health = {
    1: 'Good', 2: 'Overheat', 3: 'Dead', 4: 'Overvoltage', 5: 'Failure',
    6: 'Cold', 7: 'Watchdog timer expired', 8: 'Safety timer expired',
  };

  double? _finite(String key) {
    final v = asDouble(widget.msg[key]);
    return v != null && v.isFinite ? v : null;
  }

  @override
  Widget build(BuildContext context) {
    final msg = widget.msg;
    var pct = _finite('percentage');
    // REP: 0..1, but some drivers publish 0..100
    if (pct != null && pct > 1.0 && pct <= 100) pct /= 100;
    final status = _status[asInt(msg['power_supply_status'])];
    final healthCode = asInt(msg['power_supply_health']) ?? 0;
    final health = _health[healthCode];
    final cells = doubleList(msg['cell_voltage']);
    final current = _finite('current');
    final color = pct == null
        ? Theme.of(context).colorScheme.outline
        : pct < 0.2
            ? const Color(0xFFD32F2F)
            : pct < 0.4
                ? const Color(0xFFEF6C00)
                : const Color(0xFF2E7D32);

    return VizPage(children: [
      VizCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 8,
              children: [
                StatTile(
                  label: 'Charge',
                  value: pct == null ? '—' : (pct * 100).toStringAsFixed(0),
                  unit: pct == null ? '' : '%',
                  color: color,
                  valueSize: 44,
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (status != null) StatusPill(status.$1, status.$3, icon: status.$2),
                    if (health != null) ...[
                      const SizedBox(height: 6),
                      StatusPill(
                        'Health: $health',
                        healthCode == 1 ? const Color(0xFF2E7D32) : const Color(0xFFD32F2F),
                      ),
                    ],
                    if (msg['present'] == false) ...[
                      const SizedBox(height: 6),
                      const StatusPill('Not present', Color(0xFFD32F2F)),
                    ],
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: pct?.clamp(0.0, 1.0) ?? 0,
                minHeight: 14,
                color: color,
                backgroundColor: color.withValues(alpha: 0.15),
              ),
            ),
          ],
        ),
      ),
      VizCard(
        child: StatRow([
          StatTile(label: 'Voltage', value: _fmt(_finite('voltage')), unit: 'V'),
          StatTile(
            label: current == null ? 'Current' : current < 0 ? 'Current (out)' : 'Current (in)',
            value: _fmt(current),
            unit: 'A',
          ),
          StatTile(label: 'Temperature', value: _fmt(_finite('temperature')), unit: '°C'),
        ]),
      ),
      if (cells.isNotEmpty)
        VizCard(
          title: 'Cells (${cells.length})',
          child: Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              for (var i = 0; i < cells.length; i++)
                SizedBox(
                  width: 70,
                  child: StatTile(label: '#${i + 1}', value: _fmt(cells[i]), unit: 'V', valueSize: 16),
                ),
            ],
          ),
        ),
      VizCard(
        title: 'Voltage (last 2 min)',
        child: TimeSeriesChart(
          window: 120,
          unit: 'V',
          minSpan: 0.5,
          series: [ChartSeries('voltage', AxisColors.at(3), _voltage)],
        ),
      ),
    ]);
  }

  static String _fmt(double? v) => v == null ? '—' : fmtNum(v, sig: 3);
}

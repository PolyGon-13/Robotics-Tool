import 'package:flutter/material.dart';

import '../../utils/time_series.dart';

/// Base for visualizers that keep history across messages.
///
/// [onMessage] runs once per received message (first one in initState),
/// never on plain rebuilds such as the screen's periodic status refresh.
abstract class MsgViz extends StatefulWidget {
  final String topic;
  final Map<String, dynamic> msg;

  const MsgViz({super.key, required this.topic, required this.msg});
}

abstract class MsgVizState<T extends MsgViz> extends State<T> {
  void onMessage(Map<String, dynamic> msg);

  @override
  void initState() {
    super.initState();
    onMessage(widget.msg);
  }

  @override
  void didUpdateWidget(T oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.msg, widget.msg)) onMessage(widget.msg);
  }
}

/// Scrollable page of cards used by every visualizer.
class VizPage extends StatelessWidget {
  final List<Widget> children;
  const VizPage({super.key, required this.children});

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        children: [
          for (final c in children)
            Padding(padding: const EdgeInsets.only(bottom: 12), child: c),
        ],
      );
}

class VizCard extends StatelessWidget {
  final String? title;
  final Widget? trailing;
  final Widget child;
  final EdgeInsets padding;

  const VizCard({
    super.key,
    this.title,
    this.trailing,
    required this.child,
    this.padding = const EdgeInsets.all(14),
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: cs.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(title!,
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700, color: cs.primary)),
                    ),
                    ?trailing,
                  ],
                ),
              ),
            child,
          ],
        ),
      ),
    );
  }
}

/// Big readable number with a small label and unit.
class StatTile extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  final Color? color;
  final double valueSize;

  const StatTile({
    super.key,
    required this.label,
    required this.value,
    this.unit = '',
    this.color,
    this.valueSize = 22,
  });

  factory StatTile.num(String label, double v,
          {String unit = '', Color? color, double valueSize = 22}) =>
      StatTile(label: label, value: fmtNum(v), unit: unit, color: color, valueSize: valueSize);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label,
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            maxLines: 1, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text.rich(
            TextSpan(children: [
              TextSpan(
                text: value,
                style: TextStyle(
                  fontSize: valueSize,
                  fontWeight: FontWeight.w700,
                  color: color ?? cs.onSurface,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              if (unit.isNotEmpty)
                TextSpan(
                  text: ' $unit',
                  style: TextStyle(fontSize: valueSize * 0.55, color: cs.onSurfaceVariant),
                ),
            ]),
            maxLines: 1,
          ),
        ),
      ],
    );
  }
}

/// Evenly spaced row of [StatTile]s.
class StatRow extends StatelessWidget {
  final List<Widget> tiles;
  const StatRow(this.tiles, {super.key});

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < tiles.length; i++) ...[
            if (i > 0) const SizedBox(width: 12),
            Expanded(child: tiles[i]),
          ],
        ],
      );
}

/// Small colored pill (status labels such as "Charging").
class StatusPill extends StatelessWidget {
  final String text;
  final Color color;
  final IconData? icon;

  const StatusPill(this.text, this.color, {super.key, this.icon});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 4),
            ],
            Text(text,
                style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12)),
          ],
        ),
      );
}

import 'package:flutter/material.dart';

import 'viz_common.dart';

/// std_msgs/String and std_msgs/Bool: current value plus a log of changes.
class TextValueWidget extends MsgViz {
  const TextValueWidget({super.key, required super.topic, required super.msg});

  @override
  State<TextValueWidget> createState() => _TextValueWidgetState();
}

class _TextValueWidgetState extends MsgVizState<TextValueWidget> {
  static const _maxLog = 100;
  final List<(DateTime, Object?)> _changes = [];

  @override
  void onMessage(Map<String, dynamic> msg) {
    final v = msg['data'];
    if (_changes.isEmpty || _changes.first.$2 != v) {
      _changes.insert(0, (DateTime.now(), v));
      if (_changes.length > _maxLog) _changes.removeLast();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final v = widget.msg['data'];

    final Widget current;
    if (v is bool) {
      final color = v ? const Color(0xFF2E7D32) : cs.outline;
      current = Row(
        children: [
          Icon(v ? Icons.check_circle : Icons.radio_button_unchecked, size: 48, color: color),
          const SizedBox(width: 16),
          Text(v ? 'TRUE' : 'FALSE',
              style: TextStyle(fontSize: 36, fontWeight: FontWeight.w800, color: color)),
        ],
      );
    } else {
      final s = v?.toString() ?? '';
      current = SelectableText(
        s.isEmpty ? '(empty string)' : s,
        style: TextStyle(
          fontSize: s.length > 60 ? 16 : 28,
          fontWeight: FontWeight.w700,
          color: s.isEmpty ? cs.outline : cs.onSurface,
        ),
      );
    }

    return VizPage(children: [
      VizCard(title: 'Current value', child: current),
      VizCard(
        title: 'Changes (${_changes.length})',
        child: Column(
          children: [
            for (final (t, value) in _changes)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_time(t),
                        style: TextStyle(
                            fontSize: 12,
                            color: cs.onSurfaceVariant,
                            fontFeatures: const [FontFeature.tabularFigures()])),
                    const SizedBox(width: 12),
                    Expanded(child: Text('$value')),
                  ],
                ),
              ),
          ],
        ),
      ),
    ]);
  }

  static String _time(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:'
      '${t.second.toString().padLeft(2, '0')}';
}

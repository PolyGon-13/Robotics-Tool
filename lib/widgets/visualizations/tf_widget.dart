import 'package:flutter/material.dart';

import '../../utils/ros_msg.dart';
import '../../utils/time_series.dart';
import 'viz_common.dart';

class _Frame {
  String parent;
  double x = 0, y = 0, z = 0, yaw = 0;
  DateTime seen;
  _Frame(this.parent, this.seen);
}

/// tf2_msgs/TFMessage (/tf, /tf_static): frame tree with the latest
/// transform of each frame and how long ago it was updated.
class TfWidget extends MsgViz {
  const TfWidget({super.key, required super.topic, required super.msg});

  @override
  State<TfWidget> createState() => _TfWidgetState();
}

class _TfWidgetState extends MsgVizState<TfWidget> {
  final Map<String, _Frame> _frames = {};

  bool get _static => widget.topic.contains('static');

  @override
  void onMessage(Map<String, dynamic> msg) {
    final now = DateTime.now();
    for (final t in asList(msg['transforms'])) {
      final child = field(t, 'child_frame_id')?.toString() ?? '';
      if (child.isEmpty) continue;
      final parent = field(t, 'header.frame_id')?.toString() ?? '';
      final f = _frames.putIfAbsent(child, () => _Frame(parent, now))
        ..parent = parent
        ..seen = now
        ..x = numAt(t, 'transform.translation.x')
        ..y = numAt(t, 'transform.translation.y')
        ..z = numAt(t, 'transform.translation.z');
      f.yaw = quatMsgToEuler(field(t, 'transform.rotation')).yaw;
    }
  }

  /// Frames in tree order with their depth.
  List<(String, int)> _ordered() {
    final children = <String, List<String>>{};
    for (final e in _frames.entries) {
      children.putIfAbsent(e.value.parent, () => []).add(e.key);
    }
    for (final l in children.values) {
      l.sort();
    }
    final roots = children.keys.where((p) => !_frames.containsKey(p)).toList()..sort();
    final out = <(String, int)>[];
    final seen = <String>{};
    void walk(String name, int depth) {
      if (!seen.add(name)) return; // guard against cycles
      out.add((name, depth));
      for (final c in children[name] ?? const <String>[]) {
        walk(c, depth + 1);
      }
    }
    for (final r in roots) {
      walk(r, 0);
    }
    // Cycles without a root
    for (final f in _frames.keys) {
      if (!seen.contains(f)) walk(f, 0);
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final rows = _ordered();
    return VizPage(children: [
      VizCard(
        title: 'Frames (${_frames.length})',
        trailing: _static ? const StatusPill('static', Colors.blueGrey) : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (name, depth) in rows) _row(context, name, depth, now, cs),
          ],
        ),
      ),
    ]);
  }

  Widget _row(BuildContext context, String name, int depth, DateTime now, ColorScheme cs) {
    final f = _frames[name];
    final age = f == null ? null : now.difference(f.seen).inMilliseconds / 1000;
    final stale = !_static && age != null && age > 2;
    return Padding(
      padding: EdgeInsets.only(left: depth * 16.0, top: 5, bottom: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(f == null ? Icons.public : Icons.subdirectory_arrow_right,
              size: 16, color: cs.onSurfaceVariant),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
                if (f != null)
                  Text(
                    'x ${fmtNum(f.x, sig: 3)}  y ${fmtNum(f.y, sig: 3)}  z ${fmtNum(f.z, sig: 3)} m'
                    '  ·  yaw ${radToDeg(f.yaw).toStringAsFixed(1)}°',
                    style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurfaceVariant,
                        fontFeatures: const [FontFeature.tabularFigures()]),
                  ),
              ],
            ),
          ),
          if (age != null && !_static)
            Text(
              '${age.toStringAsFixed(1)} s',
              style: TextStyle(
                fontSize: 12,
                fontWeight: stale ? FontWeight.w700 : FontWeight.w400,
                color: stale ? Colors.orange.shade800 : cs.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }
}

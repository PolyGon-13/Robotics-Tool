import 'package:flutter/material.dart';

import '../../utils/ros_msg.dart';
import '../../utils/time_series.dart';
import '../charts/time_series_chart.dart';
import 'viz_common.dart';

/// Pose / Point / Vector3 family, with or without header and covariance:
/// Pose, PoseStamped, PoseWithCovariance(Stamped), Point(Stamped),
/// Vector3(Stamped), Quaternion(Stamped), Pose2D.
class PoseWidget extends MsgViz {
  /// Vector3 values are not positions: no "m" unit.
  final bool isVector;

  const PoseWidget({
    super.key,
    required super.topic,
    required super.msg,
    this.isVector = false,
  });

  @override
  State<PoseWidget> createState() => _PoseWidgetState();
}

class _PoseWidgetState extends MsgVizState<PoseWidget> {
  static const _axes = ['x', 'y', 'z'];
  final _hist = [TimeSeries(), TimeSeries(), TimeSeries()];
  List<double>? _xyz;
  Euler? _rpy;
  double? _theta; // Pose2D

  /// First sub-map that looks like a position / orientation.
  static Map<String, dynamic>? _find(Map<String, dynamic> msg, List<String> paths,
      bool Function(Map<String, dynamic>) test) {
    for (final p in paths) {
      final v = p.isEmpty ? msg : asMap(field(msg, p));
      if (v.isNotEmpty && test(v)) return v;
    }
    return null;
  }

  @override
  void onMessage(Map<String, dynamic> msg) {
    bool hasXyz(Map<String, dynamic> m) => m.containsKey('x') && m.containsKey('y');
    final pos = _find(msg,
        ['pose.pose.position', 'pose.position', 'position', 'point', 'vector', ''], hasXyz);
    final ori = _find(msg,
        ['pose.pose.orientation', 'pose.orientation', 'orientation', 'quaternion', ''],
        (m) => m.containsKey('w'));

    _theta = msg.containsKey('theta') ? asDouble(msg['theta']) : null;
    _xyz = (pos == null || pos.containsKey('w'))
        ? null
        : [for (final k in _axes) numAt(pos, k)];
    _rpy = ori == null ? null : quatMsgToEuler(ori);

    if (_xyz != null) {
      for (var i = 0; i < 3; i++) {
        _hist[i].add(_xyz![i]);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final frame = field(widget.msg, 'header.frame_id')?.toString() ?? '';
    final isVector = widget.isVector;
    final unit = isVector ? '' : 'm';
    return VizPage(children: [
      if (_xyz != null)
        VizCard(
          title: isVector ? 'Vector' : 'Position',
          trailing: frame.isEmpty ? null : Text('frame: $frame', style: Theme.of(context).textTheme.bodySmall),
          child: StatRow([
            for (var i = 0; i < 3; i++)
              StatTile.num(_axes[i].toUpperCase(), _xyz![i], unit: unit, color: AxisColors.at(i)),
          ]),
        ),
      if (_theta != null)
        VizCard(
          title: 'Heading',
          child: StatTile(label: 'theta', value: '${fmtFixed(radToDeg(_theta!), 1)}°'),
        ),
      if (_rpy != null)
        VizCard(
          title: 'Orientation',
          child: StatRow([
            StatTile(label: 'Roll', value: '${fmtFixed(radToDeg(_rpy!.roll), 1)}°', color: AxisColors.x),
            StatTile(label: 'Pitch', value: '${fmtFixed(radToDeg(_rpy!.pitch), 1)}°', color: AxisColors.y),
            StatTile(label: 'Yaw', value: '${fmtFixed(radToDeg(_rpy!.yaw), 1)}°', color: AxisColors.z),
          ]),
        ),
      if (_xyz != null)
        VizCard(
          title: 'History',
          child: TimeSeriesChart(
            unit: unit,
            minSpan: 0.1,
            series: [
              for (var i = 0; i < 3; i++) ChartSeries(_axes[i], AxisColors.at(i), _hist[i]),
            ],
          ),
        ),
    ]);
  }
}

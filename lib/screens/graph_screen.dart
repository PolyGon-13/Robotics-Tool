import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/ros_node.dart';
import '../models/ros_topic.dart';
import '../providers/connection_provider.dart';
import '../providers/topic_provider.dart';
import '../widgets/settings_button.dart';
import '../widgets/topic_action_bottom_sheet.dart';

// ── Data ──────────────────────────────────────────────────────────────────────

class _LNode {
  final String name;
  double x = 0, y = 0, w = 0, h = 0;
  int rank = 0;

  _LNode(this.name);

  Rect get rect => Rect.fromLTWH(x, y, w, h);
  Offset get center => Offset(x + w / 2, y + h / 2);
}

class _LEdge {
  final _LNode from;
  final _LNode to;
  final List<String> topics;

  // Precomputed by _computeEdgePaths()
  Path curvePath = Path();
  Offset arrowTip = Offset.zero;
  Offset arrowDir = Offset.zero; // unit vector pointing INTO arrowTip
  Offset labelCenter = Offset.zero;

  _LEdge({required this.from, required this.to, required this.topics});
}

// ── Screen ────────────────────────────────────────────────────────────────────

class GraphScreen extends StatefulWidget {
  const GraphScreen({super.key});

  @override
  State<GraphScreen> createState() => _GraphScreenState();
}

class _GraphScreenState extends State<GraphScreen> {
  List<RosNode> _rosNodes = [];
  List<RosTopic> _rosTopics = [];
  bool _loading = false;
  String? _error;

  List<_LNode> _lNodes = [];
  List<_LEdge> _lEdges = [];
  Size _graphSize = Size.zero;

  // Column geometry – populated by _assignPositions, consumed by _computeEdgePaths
  final Map<int, double> _colX = {};     // rank → left edge of that column
  final Map<int, double> _colRight = {}; // rank → right edge of that column
  double _routeTopY = 0;                 // y above all nodes (backward edge arc)

  final TransformationController _tc = TransformationController();
  bool _needFit = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadGraph());
  }

  @override
  void dispose() {
    _tc.dispose();
    super.dispose();
  }

  // ── Load ─────────────────────────────────────────────────────────────────

  Future<void> _loadGraph() async {
    if (!mounted) return;
    final service = context.read<ConnectionProvider>().service;
    setState(() {
      _loading = true;
      _error = null;
      _needFit = false;
    });

    try {
      final topicsResult = await service.getTopics();
      // Filter out system-wide topics that every node publishes or that are
      // purely for logging/infrastructure (they clutter the graph).
      const systemTopics = {'/parameter_events', '/rosout', '/rosout_agg'};
      final topicNames = topicsResult.topics
          .where((t) => !systemTopics.contains(t))
          .toList();

      final pubsByTopic = <String, List<String>>{};
      final subsByTopic = <String, List<String>>{};
      await Future.wait(topicNames.map((t) async {
        try {
          pubsByTopic[t] = await service.getPublishers(t);
        } catch (_) {
          pubsByTopic[t] = [];
        }
        try {
          subsByTopic[t] = await service.getSubscribers(t);
        } catch (_) {
          subsByTopic[t] = [];
        }
      }));

      final nodePublishes = <String, Set<String>>{};
      final nodeSubscribes = <String, Set<String>>{};
      for (final t in topicNames) {
        for (final n in pubsByTopic[t] ?? []) {
          nodePublishes.putIfAbsent(n, () => {}).add(t);
        }
        for (final n in subsByTopic[t] ?? []) {
          nodeSubscribes.putIfAbsent(n, () => {}).add(t);
        }
      }

      List<String> allNames = [];
      try {
        allNames = await service.getNodes();
      } catch (_) {}
      for (final n in {...nodePublishes.keys, ...nodeSubscribes.keys}) {
        if (!allNames.contains(n)) allNames.add(n);
      }

      final rosNodes = allNames
          .map((name) => RosNode(
                name: name,
                publishers: (nodePublishes[name] ?? {}).toList(),
                subscribers: (nodeSubscribes[name] ?? {}).toList(),
              ))
          .toList();

      final rosTopics = <RosTopic>[];
      for (var i = 0; i < topicNames.length; i++) {
        rosTopics.add(RosTopic(
          name: topicNames[i],
          type: i < topicsResult.types.length
              ? topicsResult.types[i]
              : 'unknown',
        ));
      }

      if (!mounted) return;
      setState(() {
        _rosNodes = rosNodes;
        _rosTopics = rosTopics;
        _buildLayout();
        _needFit = true;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  // ── Layout ────────────────────────────────────────────────────────────────

  void _buildLayout() {
    final nodeMap = <String, _LNode>{};
    for (final n in _rosNodes) {
      nodeMap[n.name] = _LNode(n.name);
    }

    // Build edges (publisher→subscriber, grouped by pair)
    final edgeTopics = <String, List<String>>{};
    for (final n in _rosNodes) {
      for (final pub in n.publishers) {
        for (final other in _rosNodes) {
          if (other.name == n.name) continue;
          if (other.subscribers.contains(pub)) {
            edgeTopics
                .putIfAbsent('${n.name}\x00${other.name}', () => [])
                .add(pub);
          }
        }
      }
    }

    final edges = <_LEdge>[];
    for (final entry in edgeTopics.entries) {
      final parts = entry.key.split('\x00');
      final from = nodeMap[parts[0]];
      final to = nodeMap[parts[1]];
      if (from != null && to != null) {
        edges.add(_LEdge(from: from, to: to, topics: entry.value));
      }
    }

    final nodes = nodeMap.values.toList();

    // Measure node text
    for (final n in nodes) {
      final tp = TextPainter(
        text: TextSpan(
            text: n.name, style: const TextStyle(fontSize: 11, height: 1.2)),
        textDirection: TextDirection.ltr,
      )..layout();
      n.w = tp.width + 24;
      n.h = tp.height + 16;
    }

    _assignRanks(nodes, edges);
    _assignPositions(nodes, edges); // also fills _colX / _colRight / _routeTopY
    _computeEdgePaths(edges, nodes);

    _lNodes = nodes;
    _lEdges = edges;
  }

  void _assignRanks(List<_LNode> nodes, List<_LEdge> edges) {
    final out = <_LNode, List<_LNode>>{for (final n in nodes) n: []};
    final inDeg = <_LNode, int>{for (final n in nodes) n: 0};
    for (final e in edges) {
      out[e.from]!.add(e.to);
      inDeg[e.to] = (inDeg[e.to] ?? 0) + 1;
    }

    final queue = <_LNode>[];
    for (final n in nodes) {
      if ((inDeg[n] ?? 0) == 0) {
        n.rank = 0;
        queue.add(n);
      }
    }
    if (queue.isEmpty && nodes.isNotEmpty) {
      nodes.first.rank = 0;
      queue.add(nodes.first);
    }

    final visited = <_LNode>{...queue};
    for (int i = 0; i < queue.length; i++) {
      final cur = queue[i];
      for (final next in out[cur]!) {
        final r = cur.rank + 1;
        if (!visited.contains(next)) {
          next.rank = r;
          visited.add(next);
          queue.add(next);
        } else if (r > next.rank) {
          next.rank = r;
        }
      }
    }
  }

  void _assignPositions(List<_LNode> nodes, List<_LEdge> edges) {
    final layers = <int, List<_LNode>>{};
    for (final n in nodes) {
      layers.putIfAbsent(n.rank, () => []).add(n);
    }

    // Barycenter sort to reduce crossings
    for (final entry in layers.entries) {
      entry.value.sort((a, b) {
        double bary(_LNode n) {
          final ns = edges
              .where((e) => e.to == n || e.from == n)
              .map((e) => (e.to == n ? e.from : e.to).rank.toDouble());
          if (ns.isEmpty) return 0;
          return ns.reduce((x, y) => x + y) / ns.length;
        }
        return bary(a).compareTo(bary(b));
      });
    }

    const colGap = 140.0;
    const rowGap = 30.0;
    const margin = 60.0;

    final colWidths = <int, double>{};
    for (final entry in layers.entries) {
      colWidths[entry.key] = entry.value.fold(0.0, (m, n) => max(m, n.w));
    }

    _colX.clear();
    _colRight.clear();
    double xCursor = margin;
    final maxRank = layers.isEmpty ? 0 : layers.keys.reduce(max);
    for (int r = 0; r <= maxRank; r++) {
      _colX[r] = xCursor;
      _colRight[r] = xCursor + (colWidths[r] ?? 0);
      xCursor += (colWidths[r] ?? 0) + colGap;
    }

    double maxColH = 0;
    for (final entry in layers.entries) {
      final h = entry.value.fold(0.0, (s, n) => s + n.h) +
          rowGap * max(0, entry.value.length - 1);
      maxColH = max(maxColH, h);
    }

    for (final entry in layers.entries) {
      final rNodes = entry.value;
      final colH = rNodes.fold(0.0, (s, n) => s + n.h) +
          rowGap * max(0, rNodes.length - 1);
      double y = margin + (maxColH - colH) / 2;
      for (final n in rNodes) {
        n.x = _colX[n.rank]!;
        n.y = y;
        y += n.h + rowGap;
      }
    }

    _routeTopY = margin / 2; // arc space above all nodes
    _graphSize = Size(xCursor + margin, maxColH + margin * 2);
  }

  // ── Edge path computation ─────────────────────────────────────────────────
  //
  // Strategy:
  //   Forward (toRank > fromRank):
  //     1. Exit source right-center.
  //     2. Go horizontal to the GAP between fromRank col and fromRank+1 col.
  //     3. Descend/rise vertically in the gap to endY.
  //     4. Go horizontal through each subsequent inter-column gap at endY,
  //        adding a short vertical detour if a node blocks the horizontal.
  //     5. Enter target left-center.
  //   Backward (toRank < fromRank):
  //     Bezier arc that routes ABOVE all nodes.
  //   Same-rank:
  //     Small Bezier arc curving right-of-column.

  void _computeEdgePaths(List<_LEdge> edges, List<_LNode> nodes) {
    final pairs = <String>{};
    for (final e in edges) {
      pairs.add('${e.from.name}\x00${e.to.name}');
    }

    // Assign bidirectional offset index per pair
    final pairIdx = <String, int>{};
    for (final e in edges) {
      final fwd = '${e.from.name}\x00${e.to.name}';
      final rev = '${e.to.name}\x00${e.from.name}';
      if (pairs.contains(rev)) {
        pairIdx[fwd] = 1;
        pairIdx[rev] = -1;
      }
    }

    for (final e in edges) {
      final key = '${e.from.name}\x00${e.to.name}';
      final bidir = pairIdx[key] ?? 0;
      _computeOnePath(e, bidir * 10.0, nodes);
    }
  }

  void _computeOnePath(_LEdge e, double yOff, List<_LNode> allNodes) {
    final fr = e.from.rank;
    final tr = e.to.rank;

    if (tr > fr) {
      _forwardPath(e, yOff, allNodes);
    } else if (tr < fr) {
      _backwardPath(e, yOff);
    } else {
      _sameRankPath(e, yOff);
    }
  }

  /// Orthogonal routing: exit right → descend in gap → horizontal with detours
  void _forwardPath(_LEdge e, double yOff, List<_LNode> allNodes) {
    final startX = e.from.x + e.from.w;
    final startY = e.from.y + e.from.h / 2 + yOff;
    final endX = e.to.x;
    final endY = e.to.y + e.to.h / 2 + yOff;

    // Gap corridor between fromRank and fromRank+1
    final gap1X = (_colRight[e.from.rank]! +
            (_colX[e.from.rank + 1] ?? _colRight[e.from.rank]! + 70)) /
        2;

    final waypoints = <Offset>[Offset(startX, startY)];

    if ((startY - endY).abs() < 2) {
      // Same Y: straight horizontal
      waypoints.add(Offset(endX, endY));
    } else {
      // Horizontal to gap, then vertical descent
      waypoints.add(Offset(gap1X, startY));
      waypoints.add(Offset(gap1X, endY));

      // Now route horizontally at endY through intermediate columns
      for (int r = e.from.rank + 1; r < e.to.rank; r++) {
        // Find any node in rank r that blocks the horizontal at endY
        final blocking = allNodes
            .where((n) =>
                n.rank == r &&
                endY + yOff.sign * 1 > n.y - 4 &&
                endY + yOff.sign * 1 < n.y + n.h + 4)
            .toList();

        if (blocking.isNotEmpty) {
          blocking.sort((a, b) => a.y.compareTo(b.y));
          final topNode = blocking.first;
          final botNode = blocking.last;

          // Detour above top node or below bottom node
          final aboveY = topNode.y - 10;
          final belowY = botNode.y + botNode.h + 10;
          final safeY =
              (endY - aboveY).abs() <= (belowY - endY).abs() ? aboveY : belowY;

          waypoints.add(Offset(_colX[r]!, endY));
          waypoints.add(Offset(_colX[r]!, safeY));
          waypoints.add(Offset(_colRight[r]!, safeY));
          waypoints.add(Offset(_colRight[r]!, endY));
        }

        final nextGapX = r + 1 < e.to.rank
            ? (_colRight[r]! + _colX[r + 1]!) / 2
            : endX;
        waypoints.add(Offset(nextGapX, endY));
      }

      // Ensure we reach endX
      if (waypoints.last.dx != endX) {
        waypoints.add(Offset(endX, endY));
      }
    }

    e.curvePath = _waypointsToPath(waypoints, 10.0);
    e.arrowTip = waypoints.last;

    // Arrow direction: last two distinct waypoints
    final pre = waypoints.length >= 2 ? waypoints[waypoints.length - 2] : waypoints.first;
    final diff = waypoints.last - pre;
    final dlen = diff.distance;
    e.arrowDir = dlen > 0 ? diff / dlen : const Offset(1, 0);

    // Label: midpoint of the vertical gap segment (or overall midpoint)
    e.labelCenter = Offset(gap1X, (startY + endY) / 2);
  }

  /// Bezier arc above all nodes for backward edges.
  void _backwardPath(_LEdge e, double yOff) {
    final startX = e.from.x + e.from.w / 2;
    final startYTop = e.from.y + yOff;
    final endX = e.to.x + e.to.w / 2;
    final endYTop = e.to.y + yOff;

    final arcY = _routeTopY + yOff.abs();
    final cp1 = Offset(startX, arcY);
    final cp2 = Offset(endX, arcY);

    e.curvePath = Path()
      ..moveTo(startX, startYTop)
      ..cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, endX, endYTop);

    e.arrowTip = Offset(endX, endYTop);
    // Tangent direction at t=1: 3*(P3 - P2) for cubic Bezier
    final tangent = Offset(endX - cp2.dx, endYTop - cp2.dy);
    final tlen = tangent.distance;
    e.arrowDir = tlen > 0 ? tangent / tlen : const Offset(0, 1);

    e.labelCenter = Offset((startX + endX) / 2, arcY + 8);
  }

  /// Small arc curving right for same-rank connections.
  void _sameRankPath(_LEdge e, double yOff) {
    final cx = e.from.x + e.from.w;
    final startY = e.from.y + e.from.h / 2 + yOff;
    final endY = e.to.y + e.to.h / 2 + yOff;
    final pullX = 40.0;

    final cp1 = Offset(cx + pullX, startY);
    final cp2 = Offset(cx + pullX, endY);
    final endPt = Offset(e.to.x, endY);

    e.curvePath = Path()
      ..moveTo(cx, startY)
      ..cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, endPt.dx, endPt.dy);

    e.arrowTip = endPt;
    final tangent = Offset(endPt.dx - cp2.dx, endPt.dy - cp2.dy);
    final tlen = tangent.distance;
    e.arrowDir = tlen > 0 ? tangent / tlen : const Offset(-1, 0);
    e.labelCenter = Offset(cx + pullX + 8, (startY + endY) / 2);
  }

  // ── Waypoints → smooth Path with rounded corners ─────────────────────────

  static Path _waypointsToPath(List<Offset> pts, double cornerRadius) {
    if (pts.length == 1) return Path()..moveTo(pts[0].dx, pts[0].dy);
    final path = Path()..moveTo(pts[0].dx, pts[0].dy);

    for (int i = 1; i < pts.length; i++) {
      final prev = pts[i - 1];
      final curr = pts[i];
      final next = i < pts.length - 1 ? pts[i + 1] : null;

      if (next == null) {
        path.lineTo(curr.dx, curr.dy);
      } else {
        final d1 = (curr - prev).distance;
        final d2 = (next - curr).distance;
        final r = min(cornerRadius, min(d1 / 2, d2 / 2));

        if (r < 1) {
          path.lineTo(curr.dx, curr.dy);
        } else {
          final t1 = r / d1;
          final t2 = r / d2;
          final p1 = Offset(
            curr.dx - (curr.dx - prev.dx) * t1,
            curr.dy - (curr.dy - prev.dy) * t1,
          );
          final p2 = Offset(
            curr.dx + (next.dx - curr.dx) * t2,
            curr.dy + (next.dy - curr.dy) * t2,
          );
          path.lineTo(p1.dx, p1.dy);
          path.quadraticBezierTo(curr.dx, curr.dy, p2.dx, p2.dy);
        }
      }
    }

    return path;
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final highlighted = context.watch<TopicProvider>().highlightedTopic;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Node Graph'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _loadGraph,
            icon: _loading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
          const SettingsButton(),
        ],
      ),
      body: _buildBody(highlighted),
    );
  }

  Widget _buildBody(String? highlighted) {
    if (_loading && _lNodes.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline,
                size: 48, color: Theme.of(context).colorScheme.error),
            const SizedBox(height: 8),
            Text(_error!),
            const SizedBox(height: 16),
            FilledButton(onPressed: _loadGraph, child: const Text('Retry')),
          ],
        ),
      );
    }
    if (_lNodes.isEmpty) {
      return const Center(child: Text('No nodes found'));
    }

    final cs = Theme.of(context).colorScheme;

    return LayoutBuilder(builder: (context, constraints) {
      if (_needFit && _graphSize.width > 0) {
        _needFit = false;
        final sx = constraints.maxWidth / _graphSize.width;
        final sy = constraints.maxHeight / _graphSize.height;
        final scale = min(sx, sy).clamp(0.05, 1.0);
        final dx = (constraints.maxWidth - _graphSize.width * scale) / 2;
        final dy = (constraints.maxHeight - _graphSize.height * scale) / 2;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _tc.value = Matrix4.identity()
            ..translateByDouble(dx, dy, 0, 1)
            ..scaleByDouble(scale, scale, 1, 1);
        });
      }

      return InteractiveViewer(
        transformationController: _tc,
        constrained: false,
        boundaryMargin: const EdgeInsets.all(600),
        minScale: 0.05,
        maxScale: 8,
        child: RepaintBoundary(
          child: GestureDetector(
            onTapUp: (d) => _handleTap(d.localPosition),
            child: CustomPaint(
              size: _graphSize,
              painter: _GraphPainter(
                nodes: _lNodes,
                edges: _lEdges,
                highlighted: highlighted,
                colorScheme: cs,
              ),
            ),
          ),
        ),
      );
    });
  }

  void _handleTap(Offset pos) {
    for (final n in _lNodes) {
      if (!n.rect.inflate(4).contains(pos)) continue;
      final rosNode = _rosNodes.firstWhere(
        (r) => r.name == n.name,
        orElse: () => RosNode(name: n.name, publishers: [], subscribers: []),
      );
      final topicNames = {...rosNode.publishers, ...rosNode.subscribers}.toList();
      if (topicNames.isEmpty) return;
      if (topicNames.length == 1) {
        _openTopic(topicNames.first);
      } else {
        _showTopicPicker(topicNames);
      }
      return;
    }
  }

  void _openTopic(String name) {
    final topic = _rosTopics.firstWhere(
      (t) => t.name == name,
      orElse: () => RosTopic(name: name, type: 'unknown'),
    );
    showModalBottomSheet(
      context: context,
      builder: (_) => TopicActionBottomSheet(topic: topic),
    );
  }

  void _showTopicPicker(List<String> names) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child:
                    Text('Select topic', style: Theme.of(ctx).textTheme.titleMedium),
              ),
              const Divider(height: 1),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: names.length,
                  itemBuilder: (_, i) => ListTile(
                    title: Text(names[i],
                        style: TextStyle(fontSize: 13, color: cs.onSurface)),
                    onTap: () {
                      Navigator.pop(ctx);
                      _openTopic(names[i]);
                    },
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ── CustomPainter ─────────────────────────────────────────────────────────────

class _GraphPainter extends CustomPainter {
  final List<_LNode> nodes;
  final List<_LEdge> edges;
  final String? highlighted;
  final ColorScheme colorScheme;

  const _GraphPainter({
    required this.nodes,
    required this.edges,
    required this.highlighted,
    required this.colorScheme,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Draw edges first (behind nodes)
    for (final e in edges) {
      _paintEdge(canvas, e);
    }
    // Draw nodes on top
    for (final n in nodes) {
      _paintNode(canvas, n);
    }
  }

  void _paintEdge(Canvas canvas, _LEdge e) {
    final edgeColor = colorScheme.outline.withValues(alpha: 0.65);
    final linePaint = Paint()
      ..color = edgeColor
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(e.curvePath, linePaint);

    // Arrowhead
    final angle = atan2(e.arrowDir.dy, e.arrowDir.dx);
    const sz = 7.0;
    final arrowPath = Path()
      ..moveTo(e.arrowTip.dx, e.arrowTip.dy)
      ..lineTo(e.arrowTip.dx - sz * cos(angle - pi / 6),
          e.arrowTip.dy - sz * sin(angle - pi / 6))
      ..lineTo(e.arrowTip.dx - sz * cos(angle + pi / 6),
          e.arrowTip.dy - sz * sin(angle + pi / 6))
      ..close();
    canvas.drawPath(arrowPath, Paint()..color = edgeColor);

    // Topic label
    final label = e.topics.join('\n');
    final lp = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(color: colorScheme.secondary, fontSize: 9, height: 1.3),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 180);

    final lc = e.labelCenter;
    final bgRect = Rect.fromCenter(
      center: lc,
      width: lp.width + 10,
      height: lp.height + 6,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(bgRect, const Radius.circular(4)),
      Paint()..color = colorScheme.surface.withValues(alpha: 0.9),
    );
    lp.paint(
        canvas, Offset(lc.dx - lp.width / 2, lc.dy - lp.height / 2));
  }

  void _paintNode(Canvas canvas, _LNode n) {
    final isHl = highlighted != null &&
        (n.name == highlighted ||
            edges.any((e) =>
                (e.from == n || e.to == n) && e.topics.contains(highlighted)));

    final bg =
        isHl ? colorScheme.errorContainer : colorScheme.primaryContainer;
    final fg =
        isHl ? colorScheme.onErrorContainer : colorScheme.onPrimaryContainer;

    final rr = RRect.fromRectAndRadius(n.rect, const Radius.circular(3));
    canvas.drawRRect(rr, Paint()..color = bg);
    canvas.drawRRect(
      rr,
      Paint()
        ..color = fg.withValues(alpha: 0.5)
        ..strokeWidth = 1.2
        ..style = PaintingStyle.stroke,
    );

    final tp = TextPainter(
      text: TextSpan(
          text: n.name,
          style: TextStyle(color: fg, fontSize: 11, height: 1.2)),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: n.w - 6);

    tp.paint(
      canvas,
      Offset(n.x + (n.w - tp.width) / 2, n.y + (n.h - tp.height) / 2),
    );
  }

  @override
  bool shouldRepaint(covariant _GraphPainter old) =>
      !identical(old.nodes, nodes) ||
      !identical(old.edges, edges) ||
      old.highlighted != highlighted ||
      old.colorScheme != colorScheme;
}

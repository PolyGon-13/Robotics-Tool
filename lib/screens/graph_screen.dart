import 'package:flutter/material.dart';
import 'package:graphview/GraphView.dart';
import 'package:provider/provider.dart';

import '../models/ros_node.dart';
import '../models/ros_topic.dart';
import '../providers/connection_provider.dart';
import '../providers/topic_provider.dart';
import '../widgets/topic_action_bottom_sheet.dart';
import 'settings_screen.dart';

class GraphScreen extends StatefulWidget {
  const GraphScreen({super.key});

  @override
  State<GraphScreen> createState() => _GraphScreenState();
}

class _GraphScreenState extends State<GraphScreen> {
  Graph _graph = Graph()..isTree = false;
  final FruchtermanReingoldAlgorithm _algorithm =
      FruchtermanReingoldAlgorithm(FruchtermanReingoldConfiguration());

  List<RosNode> _nodes = [];
  List<RosTopic> _topics = [];
  bool _loading = false;
  String? _error;

  // UniqueKey: GraphView 위젯 트리를 매 로드마다 강제 재빌드
  Key _graphKey = UniqueKey();

  // name → graphview Node
  final Map<String, Node> _nodeMap = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadGraph());
  }

  // ─── 데이터 로딩 ─────────────────────────────────────────────────────────
  Future<void> _loadGraph() async {
    if (!mounted) return;
    final service = context.read<ConnectionProvider>().service;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // Step 1: 전체 토픽 목록 조회
      final topicsResult = await service.getTopics();
      final topicNames = topicsResult.topics;

      // Step 2: 토픽별 publishers/subscribers 병렬 조회
      final Map<String, List<String>> pubsByTopic = {};
      final Map<String, List<String>> subsByTopic = {};

      await Future.wait(
        topicNames.map((topic) async {
          try {
            pubsByTopic[topic] = await service.getPublishers(topic);
          } catch (_) {
            pubsByTopic[topic] = [];
          }
          try {
            subsByTopic[topic] = await service.getSubscribers(topic);
          } catch (_) {
            subsByTopic[topic] = [];
          }
        }),
      );

      // Step 3: 역방향 매핑 — 노드가 어떤 토픽을 pub/sub하는지 집계
      final Map<String, Set<String>> nodePublishes = {};
      final Map<String, Set<String>> nodeSubscribes = {};

      for (final topic in topicNames) {
        for (final nodeName in pubsByTopic[topic] ?? []) {
          nodePublishes.putIfAbsent(nodeName, () => {}).add(topic);
        }
        for (final nodeName in subsByTopic[topic] ?? []) {
          nodeSubscribes.putIfAbsent(nodeName, () => {}).add(topic);
        }
      }

      // Step 4: 전체 노드 목록
      List<String> allNodeNames = [];
      try {
        allNodeNames = await service.getNodes();
      } catch (_) {}

      for (final name in {...nodePublishes.keys, ...nodeSubscribes.keys}) {
        if (!allNodeNames.contains(name)) allNodeNames.add(name);
      }

      // Step 5: RosNode 객체 구성
      final rosNodes = allNodeNames
          .map((name) => RosNode(
                name: name,
                publishers: (nodePublishes[name] ?? {}).toList(),
                subscribers: (nodeSubscribes[name] ?? {}).toList(),
              ))
          .toList();

      // Step 6: RosTopic 객체 구성
      final rosTopics = <RosTopic>[];
      for (var i = 0; i < topicNames.length; i++) {
        rosTopics.add(RosTopic(
          name: topicNames[i],
          type: i < topicsResult.types.length ? topicsResult.types[i] : 'unknown',
        ));
      }

      if (!mounted) return;
      setState(() {
        _nodes = rosNodes;
        _topics = rosTopics;
        _buildGraph();
        _graphKey = UniqueKey(); // GraphView 위젯 강제 재생성
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

  void _buildGraph() {
    // 매번 새 Graph 인스턴스 생성 (clear() 재사용 시 렌더 오염 버그 방지)
    final newGraph = Graph()..isTree = false;
    final newNodeMap = <String, Node>{};

    for (final n in _nodes) {
      final gNode = Node.Id(n.name);
      newNodeMap[n.name] = gNode;
      newGraph.addNode(gNode);
    }

    final Set<String> addedTopics = {};

    for (final n in _nodes) {
      for (final pub in n.publishers) {
        if (!addedTopics.contains(pub)) {
          final gNode = Node.Id('topic:$pub');
          newNodeMap['topic:$pub'] = gNode;
          newGraph.addNode(gNode);
          addedTopics.add(pub);
        }
        if (newNodeMap.containsKey(n.name) && newNodeMap.containsKey('topic:$pub')) {
          newGraph.addEdge(
            newNodeMap[n.name]!,
            newNodeMap['topic:$pub']!,
            paint: Paint()..color = Colors.blue..strokeWidth = 1.5,
          );
        }
      }

      for (final sub in n.subscribers) {
        if (!addedTopics.contains(sub)) {
          final gNode = Node.Id('topic:$sub');
          newNodeMap['topic:$sub'] = gNode;
          newGraph.addNode(gNode);
          addedTopics.add(sub);
        }
        if (newNodeMap.containsKey('topic:$sub') && newNodeMap.containsKey(n.name)) {
          newGraph.addEdge(
            newNodeMap['topic:$sub']!,
            newNodeMap[n.name]!,
            paint: Paint()..color = Colors.green..strokeWidth = 1.5,
          );
        }
      }
    }

    _graph = newGraph;
    _nodeMap
      ..clear()
      ..addAll(newNodeMap);
  }

  // ─── Build ────────────────────────────────────────────────────────────────

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
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Settings',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: _buildBody(highlighted),
    );
  }

  Widget _buildBody(String? highlighted) {
    if (_loading && _nodes.isEmpty) {
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
    if (_graph.nodes.isEmpty) {
      return const Center(child: Text('No nodes found'));
    }

    return InteractiveViewer(
      key: _graphKey,
      constrained: false,
      boundaryMargin: const EdgeInsets.all(200),
      minScale: 0.1,
      maxScale: 5,
      child: GraphView(
        key: _graphKey,
        graph: _graph,
        algorithm: _algorithm,
        builder: (node) {
          final id = node.key?.value as String? ?? '';
          final isTopic = id.startsWith('topic:');
          final label = isTopic ? id.substring(6) : id;
          final isHighlighted = highlighted != null && label == highlighted;

          if (isTopic) {
            return _TopicNodeWidget(
              label: label,
              highlighted: isHighlighted,
              onTap: () {
                final t = _topics.firstWhere(
                  (t) => t.name == label,
                  orElse: () => RosTopic(name: label, type: 'unknown'),
                );
                showModalBottomSheet(
                  context: context,
                  builder: (_) => TopicActionBottomSheet(topic: t),
                );
              },
            );
          } else {
            return _RosNodeWidget(label: label, highlighted: isHighlighted);
          }
        },
      ),
    );
  }
}

// ─── 노드 위젯 ──────────────────────────────────────────────────────────────

class _RosNodeWidget extends StatelessWidget {
  final String label;
  final bool highlighted;

  const _RosNodeWidget({required this.label, required this.highlighted});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bg = highlighted ? cs.errorContainer : cs.primaryContainer;
    final fg = highlighted ? cs.onErrorContainer : cs.onPrimaryContainer;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: highlighted ? 0.25 : 0.12),
            blurRadius: highlighted ? 8 : 4,
          ),
        ],
      ),
      child: Text(
        label.length > 20 ? '${label.substring(0, 17)}…' : label,
        style: TextStyle(color: fg, fontSize: 11),
        textAlign: TextAlign.center,
      ),
    );
  }
}

class _TopicNodeWidget extends StatelessWidget {
  final String label;
  final bool highlighted;
  final VoidCallback onTap;

  const _TopicNodeWidget({
    required this.label,
    required this.highlighted,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bg = highlighted ? cs.errorContainer : cs.tertiaryContainer;
    final fg = highlighted ? cs.onErrorContainer : cs.onTertiaryContainer;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(6),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: highlighted ? 0.25 : 0.12),
              blurRadius: highlighted ? 8 : 4,
            ),
          ],
        ),
        child: Text(
          label.length > 25 ? '${label.substring(0, 22)}…' : label,
          style: TextStyle(color: fg, fontSize: 10),
        ),
      ),
    );
  }
}

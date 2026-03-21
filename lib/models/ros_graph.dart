import 'ros_node.dart';
import 'ros_topic.dart';

class RosGraph {
  final List<RosNode> nodes;
  final List<RosTopic> topics;

  const RosGraph({
    this.nodes = const [],
    this.topics = const [],
  });

  RosGraph copyWith({
    List<RosNode>? nodes,
    List<RosTopic>? topics,
  }) =>
      RosGraph(
        nodes: nodes ?? this.nodes,
        topics: topics ?? this.topics,
      );

  bool get isEmpty => nodes.isEmpty && topics.isEmpty;
}

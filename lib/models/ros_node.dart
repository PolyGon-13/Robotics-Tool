class RosNode {
  final String name;
  final List<String> publishers;
  final List<String> subscribers;

  const RosNode({
    required this.name,
    this.publishers = const [],
    this.subscribers = const [],
  });

  RosNode copyWith({
    List<String>? publishers,
    List<String>? subscribers,
  }) =>
      RosNode(
        name: name,
        publishers: publishers ?? this.publishers,
        subscribers: subscribers ?? this.subscribers,
      );

  @override
  bool operator ==(Object other) => other is RosNode && other.name == name;

  @override
  int get hashCode => name.hashCode;
}

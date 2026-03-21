class RosMessage {
  final String topic;
  final Map<String, dynamic> data;
  final DateTime receivedAt;

  const RosMessage({
    required this.topic,
    required this.data,
    required this.receivedAt,
  });

  factory RosMessage.now({
    required String topic,
    required Map<String, dynamic> data,
  }) =>
      RosMessage(
        topic: topic,
        data: data,
        receivedAt: DateTime.now(),
      );
}

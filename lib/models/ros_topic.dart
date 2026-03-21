class RosTopic {
  final String name;
  final String type;

  const RosTopic({
    required this.name,
    required this.type,
  });

  String get namespace {
    final parts = name.split('/');
    return parts.length > 2 ? parts.sublist(0, parts.length - 1).join('/') : '/';
  }

  String get msgFamily {
    if (type.startsWith('sensor_msgs')) return 'sensor_msgs';
    if (type.startsWith('nav_msgs')) return 'nav_msgs';
    if (type.startsWith('geometry_msgs')) return 'geometry_msgs';
    if (type.startsWith('std_msgs')) return 'std_msgs';
    return 'other';
  }

  @override
  bool operator ==(Object other) =>
      other is RosTopic && other.name == name && other.type == type;

  @override
  int get hashCode => Object.hash(name, type);
}

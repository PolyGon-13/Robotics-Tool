import 'package:flutter_test/flutter_test.dart';
import 'package:robotics_tool/models/ros_topic.dart';
import 'package:robotics_tool/providers/topic_provider.dart';
import 'package:robotics_tool/services/rosbridge_service.dart';

/// RosbridgeService stand-in that answers getTopics() from a list.
class FakeService extends RosbridgeService {
  List<RosTopic> topics;
  Object? error;
  int calls = 0;
  FakeService(this.topics);

  @override
  Future<({List<String> topics, List<String> types})> getTopics() async {
    calls++;
    if (error != null) throw error!;
    return (
      topics: topics.map((t) => t.name).toList(),
      types: topics.map((t) => t.type).toList(),
    );
  }
}

void main() {
  const scan = RosTopic(name: '/scan', type: 'sensor_msgs/msg/LaserScan');
  const odom = RosTopic(name: '/odom', type: 'nav_msgs/msg/Odometry');
  const cmd = RosTopic(name: '/cmd_vel', type: 'geometry_msgs/msg/Twist');
  const rosout = RosTopic(name: '/rosout', type: 'rcl_interfaces/msg/Log');
  const params = RosTopic(name: '/parameter_events', type: 'rcl_interfaces/msg/ParameterEvent');

  late FakeService service;
  late TopicProvider tp;

  setUp(() async {
    service = FakeService([scan, rosout, odom, cmd, params]);
    tp = TopicProvider();
    tp.updateService(service, ConnectionStatus.connected);
    await Future<void>.delayed(Duration.zero);
  });

  tearDown(() => tp.dispose());

  test('loads on connect, sorted, system topics hidden', () {
    expect(service.calls, 1);
    expect(tp.topics.map((t) => t.name), ['/cmd_vel', '/odom', '/parameter_events', '/rosout', '/scan']);
    expect(tp.filteredTopics.map((t) => t.name), ['/cmd_vel', '/odom', '/scan']);
    expect(tp.hiddenCount, 2);
    tp.setHideSystem(false);
    expect(tp.filteredTopics.length, 5);
  });

  test('search matches name or type; family filter and counts', () {
    tp.setSearchQuery('laser');
    expect(tp.filteredTopics.single.name, '/scan');
    tp.setSearchQuery('');
    expect(tp.familyCounts, {'geometry_msgs': 1, 'nav_msgs': 1, 'sensor_msgs': 1});
    tp.toggleTypeFilter('nav_msgs');
    expect(tp.filteredTopics.single.name, '/odom');
    tp.clearFilters();
    expect(tp.filteredTopics.length, 3);
  });

  test('disconnect clears topics, error and highlight; reconnect reloads', () async {
    tp.showInGraph('/scan');
    tp.updateService(service, ConnectionStatus.disconnected);
    expect(tp.topics, isEmpty);
    expect(tp.highlightedTopic, isNull);

    tp.updateService(service, ConnectionStatus.connected);
    await Future<void>.delayed(Duration.zero);
    expect(service.calls, 2);
    expect(tp.topics, isNotEmpty);
    expect(tp.error, isNull);
  });

  test('auto-reconnect (connecting) keeps the current list', () {
    tp.updateService(service, ConnectionStatus.connecting);
    expect(tp.topics, isNotEmpty);
  });

  test('showInGraph bumps the focus request', () {
    final before = tp.graphFocusRequest;
    tp.showInGraph('/odom');
    expect(tp.graphFocusRequest, before + 1);
    expect(tp.highlightedTopic, '/odom');
  });

  test('load errors are reported and cleared on success', () async {
    service.error = Exception('boom');
    await tp.loadTopics();
    expect(tp.error, contains('boom'));
    service.error = null;
    await tp.loadTopics();
    expect(tp.error, isNull);
  });
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:robotics_tool/services/rosbridge_service.dart';

/// Minimal in-process rosbridge stand-in.
class FakeRosbridge {
  late final HttpServer _server;
  final List<WebSocket> clients = [];
  final List<Map<String, dynamic>> received = [];
  final _connections = StreamController<WebSocket>.broadcast();

  int get port => _server.port;
  Stream<WebSocket> get connections => _connections.stream;

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.transform(WebSocketTransformer()).listen((ws) {
      clients.add(ws);
      _connections.add(ws);
      ws.listen((raw) {
        final m = jsonDecode(raw as String) as Map<String, dynamic>;
        received.add(m);
        if (m['op'] == 'call_service') {
          ws.add(jsonEncode({
            'op': 'service_response',
            'id': m['id'],
            'values': {'topics': ['/a', '/b'], 'types': ['std_msgs/msg/Int32', 'std_msgs/msg/String']},
            'result': true,
          }));
        }
      }, onDone: () => clients.remove(ws));
    });
  }

  void publish(String topic, Map<String, dynamic> msg) {
    for (final c in clients) {
      c.add(jsonEncode({'op': 'publish', 'topic': topic, 'msg': msg}));
    }
  }

  Future<void> dropAll() async {
    for (final c in List.of(clients)) {
      await c.close();
    }
  }

  Future<void> stop() async {
    await _connections.close();
    await _server.close(force: true);
  }

  Iterable<Map<String, dynamic>> ops(String op) => received.where((m) => m['op'] == op);
}

Future<void> until(bool Function() cond, {Duration timeout = const Duration(seconds: 8)}) async {
  final end = DateTime.now().add(timeout);
  while (!cond()) {
    if (DateTime.now().isAfter(end)) throw TimeoutException('condition not met');
    await Future.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  late FakeRosbridge server;
  late RosbridgeService service;

  setUp(() async {
    server = FakeRosbridge();
    await server.start();
    service = RosbridgeService();
  });

  tearDown(() async {
    await service.disconnect();
    await server.stop();
  });

  test('connects and answers service calls', () async {
    final statuses = <ConnectionStatus>[];
    service.onStatusChange = statuses.add;
    await service.connect('127.0.0.1', server.port);
    expect(service.status, ConnectionStatus.connected);
    expect(statuses, [ConnectionStatus.connecting, ConnectionStatus.connected]);

    final topics = await service.getTopics();
    expect(topics.topics, ['/a', '/b']);
  });

  test('delivers subscribed topic messages, including null fields', () async {
    await service.connect('127.0.0.1', server.port);
    final got = <Map<String, dynamic>>[];
    service.subscribe('/scan', 'sensor_msgs/msg/LaserScan').listen(got.add);
    await until(() => server.ops('subscribe').isNotEmpty);

    server.publish('/scan', {'ranges': [1.0, null, 2.0]});
    await until(() => got.isNotEmpty);
    expect(got.single['ranges'], [1.0, null, 2.0]);
  });

  test('re-subscribes after an automatic reconnect', () async {
    await service.connect('127.0.0.1', server.port);
    final got = <Map<String, dynamic>>[];
    service.subscribe('/odom', 'nav_msgs/msg/Odometry').listen(got.add);
    await until(() => server.ops('subscribe').length == 1);

    final reconnected = server.connections.first;
    await server.dropAll();
    await reconnected.timeout(const Duration(seconds: 8));
    await until(() => server.ops('subscribe').length == 2);
    expect(server.ops('subscribe').last['topic'], '/odom');
    expect(service.status, ConnectionStatus.connected);

    server.publish('/odom', {'seq': 1});
    await until(() => got.isNotEmpty);
  });

  test('unsubscribed topics are not restored on reconnect', () async {
    await service.connect('127.0.0.1', server.port);
    service.subscribe('/x', 'std_msgs/msg/Int32').listen((_) {});
    service.unsubscribe('/x');
    await until(() => server.ops('unsubscribe').isNotEmpty);

    final reconnected = server.connections.first;
    await server.dropAll();
    await reconnected.timeout(const Duration(seconds: 8));
    await Future.delayed(const Duration(milliseconds: 300));
    expect(server.ops('subscribe').length, 1);
  });

  test('publish reports failure when not connected', () async {
    expect(service.publish('/cmd_vel', 'geometry_msgs/msg/Twist', {}), isFalse);
    await service.connect('127.0.0.1', server.port);
    expect(service.publish('/cmd_vel', 'geometry_msgs/msg/Twist', {'linear': {'x': 1}}), isTrue);
    await until(() => server.ops('publish').isNotEmpty);
  });

  test('gives up after repeated failures', () async {
    final port = server.port;
    await server.stop();
    await service.connect('127.0.0.1', port);
    await until(() => service.status == ConnectionStatus.failed,
        timeout: const Duration(seconds: 15));
  });
}

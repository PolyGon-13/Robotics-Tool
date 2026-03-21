import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:web_socket_channel/web_socket_channel.dart';

enum ConnectionStatus { disconnected, connecting, connected, failed }

typedef OnStatusChange = void Function(ConnectionStatus status);

class RosbridgeService {
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;

  final Map<String, Completer<Map<String, dynamic>>> _pendingCalls = {};
  final Map<String, StreamController<Map<String, dynamic>>> _topicControllers =
      {};

  ConnectionStatus _status = ConnectionStatus.disconnected;
  ConnectionStatus get status => _status;

  OnStatusChange? onStatusChange;

  String? _currentIp;
  int _currentPort = 9090;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 3;
  static const Duration _reconnectDelay = Duration(seconds: 2);

  final _random = Random();

  String _generateId() =>
      _random.nextInt(0xFFFFFF).toRadixString(16).padLeft(6, '0');

  // ─── Connection ────────────────────────────────────────────────────────────

  Future<void> connect(String ip, int port) async {
    _currentIp = ip;
    _currentPort = port;
    _reconnectAttempts = 0;
    await _doConnect();
  }

  Future<void> _doConnect() async {
    _setStatus(ConnectionStatus.connecting);

    try {
      final uri = Uri.parse('ws://$_currentIp:$_currentPort');
      _channel = WebSocketChannel.connect(uri);

      // Wait for handshake (throws if connection refused)
      await _channel!.ready;

      _setStatus(ConnectionStatus.connected);
      _reconnectAttempts = 0;

      _subscription = _channel!.stream.listen(
        _handleMessage,
        onError: _handleError,
        onDone: _handleDone,
        cancelOnError: false,
      );
    } catch (e) {
      _handleError(e);
    }
  }

  void _handleMessage(dynamic raw) {
    Map<String, dynamic> msg;
    try {
      msg = jsonDecode(raw as String) as Map<String, dynamic>;
    } catch (_) {
      return;
    }

    final op = msg['op'] as String?;

    if (op == 'service_response') {
      final id = msg['id'] as String?;
      if (id != null && _pendingCalls.containsKey(id)) {
        final values = msg['values'] as Map<String, dynamic>? ?? {};
        _pendingCalls.remove(id)!.complete(values);
      }
    } else if (op == 'publish') {
      final topic = msg['topic'] as String?;
      if (topic != null && _topicControllers.containsKey(topic)) {
        final msgData = msg['msg'] as Map<String, dynamic>? ?? {};
        _topicControllers[topic]!.add(msgData);
      }
    }
  }

  void _handleError(dynamic error) {
    _scheduleReconnect();
  }

  void _handleDone() {
    if (_status == ConnectionStatus.connected) {
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (_reconnectAttempts >= _maxReconnectAttempts || _currentIp == null) {
      _setStatus(ConnectionStatus.failed);
      _cleanUp();
      return;
    }
    _reconnectAttempts++;
    _setStatus(ConnectionStatus.connecting);
    Future.delayed(_reconnectDelay, _doConnect);
  }

  Future<void> disconnect() async {
    _currentIp = null;
    _setStatus(ConnectionStatus.disconnected);
    _cleanUp();
  }

  void _cleanUp() {
    _subscription?.cancel();
    _subscription = null;
    _channel?.sink.close();
    _channel = null;

    for (final c in _pendingCalls.values) {
      c.completeError(Exception('Disconnected'));
    }
    _pendingCalls.clear();

    for (final sc in _topicControllers.values) {
      sc.close();
    }
    _topicControllers.clear();
  }

  void _setStatus(ConnectionStatus s) {
    _status = s;
    onStatusChange?.call(s);
  }

  // ─── Service Calls ─────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> callService(
    String service, {
    Map<String, dynamic>? args,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    if (_channel == null || _status != ConnectionStatus.connected) {
      throw Exception('Not connected');
    }

    final id = '${service}_${_generateId()}';
    final completer = Completer<Map<String, dynamic>>();
    _pendingCalls[id] = completer;

    final payload = {
      'op': 'call_service',
      'id': id,
      'service': service,
      'args': ?args,
    };

    _channel!.sink.add(jsonEncode(payload));

    return completer.future.timeout(timeout, onTimeout: () {
      _pendingCalls.remove(id);
      throw TimeoutException('Service call timed out: $service', timeout);
    });
  }

  // ─── Topic Subscriptions ───────────────────────────────────────────────────

  Stream<Map<String, dynamic>> subscribe(
    String topic,
    String type, {
    int throttleRate = 100,
  }) {
    if (!_topicControllers.containsKey(topic)) {
      _topicControllers[topic] = StreamController<Map<String, dynamic>>.broadcast();

      final payload = {
        'op': 'subscribe',
        'topic': topic,
        'type': type,
        'throttle_rate': throttleRate,
      };
      _channel?.sink.add(jsonEncode(payload));
    }
    return _topicControllers[topic]!.stream;
  }

  void unsubscribe(String topic) {
    if (_topicControllers.containsKey(topic)) {
      _topicControllers.remove(topic)?.close();
      final payload = {'op': 'unsubscribe', 'topic': topic};
      _channel?.sink.add(jsonEncode(payload));
    }
  }

  // ─── Convenience API wrappers ──────────────────────────────────────────────

  Future<List<String>> getNodes() async {
    final result = await callService('/rosapi/nodes');
    final nodes = result['nodes'] as List<dynamic>? ?? [];
    return nodes.cast<String>();
  }

  Future<({List<String> topics, List<String> types})> getTopics() async {
    final result = await callService('/rosapi/topics');
    final topics = (result['topics'] as List<dynamic>? ?? []).cast<String>();
    final types = (result['types'] as List<dynamic>? ?? []).cast<String>();
    return (topics: topics, types: types);
  }

  Future<List<String>> getPublishers(String topic) async {
    final result = await callService(
      '/rosapi/publishers',
      args: {'topic': topic},
    );
    final pubs = result['publishers'] as List<dynamic>? ?? [];
    return pubs.cast<String>();
  }

  Future<List<String>> getSubscribers(String topic) async {
    final result = await callService(
      '/rosapi/subscribers',
      args: {'topic': topic},
    );
    final subs = result['subscribers'] as List<dynamic>? ?? [];
    return subs.cast<String>();
  }

  // ─── Publish ───────────────────────────────────────────────────────────────

  /// fire-and-forget: rosbridge publish op (응답 없음)
  void publish(String topic, String type, Map<String, dynamic> message) {
    if (_channel == null || _status != ConnectionStatus.connected) return;
    _channel!.sink.add(jsonEncode({
      'op': 'publish',
      'topic': topic,
      'type': type,
      'msg': message,
    }));
  }
}

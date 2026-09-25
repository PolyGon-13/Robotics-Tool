import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../utils/msg_template.dart';

enum ConnectionStatus { disconnected, connecting, connected, failed }

typedef OnStatusChange = void Function(ConnectionStatus status);

class RosbridgeService {
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;

  final Map<String, Completer<Map<String, dynamic>>> _pendingCalls = {};
  final Map<String, StreamController<Map<String, dynamic>>> _topicControllers =
      {};
  // 재연결 시 다시 보낼 subscribe 요청 (topic → payload)
  final Map<String, Map<String, dynamic>> _subscribePayloads = {};
  // 같은 topic을 여러 화면이 구독할 수 있으므로 참조 수를 센다
  final Map<String, int> _subscribeRefs = {};
  // advertise 한 topic → type (재연결 시 다시 advertise), 참조 수
  final Map<String, String> _advertised = {};
  final Map<String, int> _advertiseRefs = {};

  ConnectionStatus _status = ConnectionStatus.disconnected;
  ConnectionStatus get status => _status;

  OnStatusChange? onStatusChange;

  String? _currentIp;
  int _currentPort = 9090;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 3;
  static const Duration _reconnectDelay = Duration(seconds: 2);

  int _connectGeneration = 0;
  Timer? _reconnectTimer;

  // Liveness: a dropped Wi-Fi link often closes nothing, so the socket would
  // look "connected" for minutes. When nothing has arrived for a while, a
  // cheap service call is sent; no answer means the link is dead.
  static const Duration connectTimeout = Duration(seconds: 5);
  static const Duration idleBeforeProbe = Duration(seconds: 3);
  static const Duration probeTimeout = Duration(seconds: 2);
  Timer? _watchdog;
  DateTime _lastRx = DateTime.now();
  bool _probing = false;

  int _nextId = 0;
  String _generateId() => (++_nextId).toString();

  // ─── Connection ────────────────────────────────────────────────────────────

  Future<void> connect(String ip, int port) async {
    _currentIp = ip;
    _currentPort = port;
    _reconnectAttempts = 0;
    await _doConnect();
  }

  Future<void> _doConnect() async {
    final myGen = ++_connectGeneration;
    _setStatus(ConnectionStatus.connecting);

    // 재연결이면 끊어진 이전 채널 정리 (topic 스트림은 유지)
    _subscription?.cancel();
    _subscription = null;
    _channel?.sink.close();
    _channel = null;

    try {
      final uri = Uri.parse('ws://$_currentIp:$_currentPort');
      _channel = WebSocketChannel.connect(uri);

      // Wait for handshake (throws if refused; times out if the host is unreachable)
      await _channel!.ready.timeout(connectTimeout);

      if (myGen != _connectGeneration) return;

      _setStatus(ConnectionStatus.connected);
      _reconnectAttempts = 0;
      _lastRx = DateTime.now();
      _startWatchdog(myGen);

      _subscription = _channel!.stream.listen(
        _handleMessage,
        onError: (e) { if (myGen == _connectGeneration) _handleError(e); },
        onDone: ()    { if (myGen == _connectGeneration) _handleDone(); },
        cancelOnError: false,
      );

      // 재연결 전에 구독 / advertise 하던 topic 복구
      for (final payload in _subscribePayloads.values) {
        _channel!.sink.add(jsonEncode(payload));
      }
      for (final e in _advertised.entries) {
        _sendAdvertise(e.key, e.value);
      }
    } catch (e) {
      if (myGen != _connectGeneration) return;
      _handleError(e);
    }
  }

  void _startWatchdog(int gen) {
    _watchdog?.cancel();
    _probing = false;
    _watchdog = Timer.periodic(const Duration(seconds: 1), (_) async {
      if (gen != _connectGeneration || _status != ConnectionStatus.connected) return;
      if (_probing || DateTime.now().difference(_lastRx) < idleBeforeProbe) return;
      _probing = true;
      try {
        await callService('/rosapi/get_time', timeout: probeTimeout);
      } on TimeoutException {
        if (gen == _connectGeneration && _status == ConnectionStatus.connected) {
          _linkLost();
        }
      } catch (_) {
        // An error reply still proves the link is alive
      } finally {
        _probing = false;
      }
    });
  }

  /// The link stopped answering: drop the socket (discarding anything still
  /// buffered, e.g. old joystick commands) and reconnect.
  void _linkLost() {
    _connectGeneration++;
    _subscription?.cancel();
    _subscription = null;
    _channel?.sink.close();
    _channel = null;
    _scheduleReconnect();
  }

  void _handleMessage(dynamic raw) {
    _lastRx = DateTime.now();
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
        final completer = _pendingCalls.remove(id)!;
        final values = msg['values'];
        if (msg['result'] == false) {
          // On failure rosbridge puts the error text in "values"
          completer.completeError(Exception('${msg['service'] ?? 'Service'} failed: $values'));
        } else {
          completer.complete(values is Map<String, dynamic> ? values : <String, dynamic>{});
        }
      }
    } else if (op == 'publish') {
      final topic = msg['topic'] as String?;
      final data = msg['msg'];
      if (topic != null && _topicControllers.containsKey(topic) && data is Map<String, dynamic>) {
        _topicControllers[topic]!.add(data);
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
    _watchdog?.cancel();
    if (_reconnectAttempts >= _maxReconnectAttempts || _currentIp == null) {
      _setStatus(ConnectionStatus.failed);
      _cleanUp();
      return;
    }
    _reconnectAttempts++;
    _setStatus(ConnectionStatus.connecting);
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(_reconnectDelay, _doConnect);
  }

  Future<void> disconnect() async {
    _connectGeneration++;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _currentIp = null;
    _setStatus(ConnectionStatus.disconnected);
    _cleanUp();
  }

  void _cleanUp() {
    _watchdog?.cancel();
    _watchdog = null;
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
    _subscribePayloads.clear();
    _subscribeRefs.clear();
    _advertised.clear();
    _advertiseRefs.clear();
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
    _subscribeRefs[topic] = (_subscribeRefs[topic] ?? 0) + 1;
    if (!_topicControllers.containsKey(topic)) {
      _topicControllers[topic] = StreamController<Map<String, dynamic>>.broadcast();

      final payload = {
        'op': 'subscribe',
        'topic': topic,
        'type': type,
        'throttle_rate': throttleRate,
      };
      _subscribePayloads[topic] = payload;
      _channel?.sink.add(jsonEncode(payload));
    }
    return _topicControllers[topic]!.stream;
  }

  /// Releases one [subscribe]; the rosbridge subscription ends when the
  /// last user of the topic unsubscribes.
  void unsubscribe(String topic) {
    final refs = (_subscribeRefs[topic] ?? 0) - 1;
    if (refs > 0) {
      _subscribeRefs[topic] = refs;
      return;
    }
    _subscribeRefs.remove(topic);
    if (_topicControllers.containsKey(topic)) {
      _topicControllers.remove(topic)?.close();
      _subscribePayloads.remove(topic);
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

  /// Default-valued message for [type], built from rosapi's type
  /// definitions. Null if rosapi does not know the type.
  Future<Map<String, dynamic>?> getMessageTemplate(String type) async {
    final result = await callService(
      '/rosapi/message_details',
      args: {'type': type},
    );
    return templateFromTypedefs(type, result['typedefs'] as List<dynamic>? ?? []);
  }

  // ─── Publish ───────────────────────────────────────────────────────────────

  void _sendAdvertise(String topic, String type) {
    _channel?.sink.add(jsonEncode({'op': 'advertise', 'topic': topic, 'type': type}));
  }

  /// Registers a publisher for [topic] on the rosbridge side ahead of the
  /// first message (ROS2 rosbridge otherwise creates it on the first publish
  /// and that message is usually lost). Restored after reconnects.
  void advertise(String topic, String type) {
    _advertiseRefs[topic] = (_advertiseRefs[topic] ?? 0) + 1;
    if (_advertised.containsKey(topic)) return;
    _advertised[topic] = type;
    if (_status == ConnectionStatus.connected) _sendAdvertise(topic, type);
  }

  void unadvertise(String topic) {
    final refs = (_advertiseRefs[topic] ?? 0) - 1;
    if (refs > 0) {
      _advertiseRefs[topic] = refs;
      return;
    }
    _advertiseRefs.remove(topic);
    if (_advertised.remove(topic) != null) {
      _channel?.sink.add(jsonEncode({'op': 'unadvertise', 'topic': topic}));
    }
  }

  /// fire-and-forget: rosbridge publish op (응답 없음).
  /// 연결되어 있지 않아 보내지 못하면 false.
  bool publish(String topic, String type, Map<String, dynamic> message) {
    if (_channel == null || _status != ConnectionStatus.connected) return false;
    if (!_advertised.containsKey(topic)) {
      _advertised[topic] = type;
      _sendAdvertise(topic, type);
    }
    _channel!.sink.add(jsonEncode({
      'op': 'publish',
      'topic': topic,
      'type': type,
      'msg': message,
    }));
    return true;
  }
}

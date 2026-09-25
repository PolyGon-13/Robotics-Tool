import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/ros_topic.dart';
import '../services/rosbridge_service.dart';

class TopicProvider extends ChangeNotifier {
  RosbridgeService? _service;

  List<RosTopic> _topics = [];
  String _searchQuery = '';
  final Set<String> _typeFilters = {};
  bool _hideSystem = true;
  String? _highlightedTopic;
  int _graphFocusRequest = 0;
  bool _isLoading = false;
  String? _error;

  ConnectionStatus? _status;
  Timer? _refreshTimer;

  /// All topics, sorted by name.
  List<RosTopic> get topics => _topics;
  String get searchQuery => _searchQuery;
  Set<String> get typeFilters => Set.unmodifiable(_typeFilters);
  bool get hideSystem => _hideSystem;
  String? get highlightedTopic => _highlightedTopic;
  /// Increments whenever something asks the Graph tab to be shown.
  int get graphFocusRequest => _graphFocusRequest;
  bool get isLoading => _isLoading;
  String? get error => _error;

  /// Infrastructure topics every ROS2 system has; rarely what you look for.
  static bool isSystemTopic(RosTopic t) =>
      t.name == '/rosout' ||
      t.name == '/rosout_agg' ||
      t.name == '/parameter_events' ||
      t.name.endsWith('/transition_event') ||
      t.type.startsWith('rcl_interfaces/');

  List<RosTopic> get _visible =>
      _hideSystem ? _topics.where((t) => !isSystemTopic(t)).toList() : _topics;

  int get hiddenCount => _hideSystem ? _topics.where(isSystemTopic).length : 0;

  /// Topic count per message family, before the family filter is applied.
  Map<String, int> get familyCounts {
    final counts = <String, int>{};
    for (final t in _visible) {
      counts[t.msgFamily] = (counts[t.msgFamily] ?? 0) + 1;
    }
    return counts;
  }

  List<RosTopic> get filteredTopics {
    final q = _searchQuery.toLowerCase();
    return _visible.where((t) {
      final matchesSearch = q.isEmpty ||
          t.name.toLowerCase().contains(q) ||
          t.type.toLowerCase().contains(q);
      final matchesFilter =
          _typeFilters.isEmpty || _typeFilters.contains(t.msgFamily);
      return matchesSearch && matchesFilter;
    }).toList();
  }

  void updateService(RosbridgeService? service, ConnectionStatus status) {
    // service 인스턴스는 앱 전체에서 하나이므로 연결 상태 변화로 판단
    if (_service == service && _status == status) return;
    _service = service;
    _status = status;

    if (status == ConnectionStatus.connected) {
      _startAutoRefresh();
      loadTopics();
    } else {
      _stopAutoRefresh();
      // 자동 재연결 중(connecting)에는 기존 목록 유지
      if (status != ConnectionStatus.connecting) {
        _topics = [];
        _error = null;
        _highlightedTopic = null;
        notifyListeners();
      }
    }
  }

  void _startAutoRefresh() {
    _stopAutoRefresh();
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      loadTopics();
    });
  }

  void _stopAutoRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
  }

  Future<void> loadTopics() async {
    if (_service == null) return;
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final result = await _service!.getTopics();
      final topics = <RosTopic>[];
      for (var i = 0; i < result.topics.length; i++) {
        topics.add(RosTopic(
          name: result.topics[i],
          type: i < result.types.length ? result.types[i] : 'unknown',
        ));
      }
      topics.sort((a, b) => a.name.compareTo(b.name));
      _topics = topics;
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  void toggleTypeFilter(String family) {
    if (_typeFilters.contains(family)) {
      _typeFilters.remove(family);
    } else {
      _typeFilters.add(family);
    }
    notifyListeners();
  }

  void clearFilters() {
    _typeFilters.clear();
    notifyListeners();
  }

  void setHideSystem(bool hide) {
    _hideSystem = hide;
    notifyListeners();
  }

  void setHighlight(String? topicName) {
    _highlightedTopic = topicName;
    notifyListeners();
  }

  /// Highlight [topicName] and switch the main screen to the Graph tab.
  void showInGraph(String topicName) {
    _highlightedTopic = topicName;
    _graphFocusRequest++;
    notifyListeners();
  }

  @override
  void dispose() {
    _stopAutoRefresh();
    super.dispose();
  }
}

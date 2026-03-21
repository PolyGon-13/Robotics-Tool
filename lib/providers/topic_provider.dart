import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/ros_topic.dart';
import '../services/rosbridge_service.dart';

class TopicProvider extends ChangeNotifier {
  RosbridgeService? _service;

  List<RosTopic> _topics = [];
  String _searchQuery = '';
  final Set<String> _typeFilters = {};
  String? _highlightedTopic;
  bool _isLoading = false;
  String? _error;

  Timer? _refreshTimer;

  List<RosTopic> get topics => _topics;
  String get searchQuery => _searchQuery;
  Set<String> get typeFilters => Set.unmodifiable(_typeFilters);
  String? get highlightedTopic => _highlightedTopic;
  bool get isLoading => _isLoading;
  String? get error => _error;

  List<RosTopic> get filteredTopics {
    return _topics.where((t) {
      final matchesSearch = _searchQuery.isEmpty ||
          t.name.toLowerCase().contains(_searchQuery.toLowerCase());
      final matchesFilter =
          _typeFilters.isEmpty || _typeFilters.contains(t.msgFamily);
      return matchesSearch && matchesFilter;
    }).toList();
  }

  void updateService(RosbridgeService? service, ConnectionStatus status) {
    if (_service == service) return;
    _service = service;

    if (status == ConnectionStatus.connected) {
      _startAutoRefresh();
      loadTopics();
    } else {
      _stopAutoRefresh();
      _topics = [];
      notifyListeners();
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

  void setHighlight(String? topicName) {
    _highlightedTopic = topicName;
    notifyListeners();
  }

  @override
  void dispose() {
    _stopAutoRefresh();
    super.dispose();
  }
}

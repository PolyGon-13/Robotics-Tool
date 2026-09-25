import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/rosbridge_service.dart';
import '../utils/host_address.dart';

export '../services/rosbridge_service.dart' show ConnectionStatus;

class ConnectionProvider extends ChangeNotifier {
  final RosbridgeService _service = RosbridgeService();

  static const int maxRecent = 5;
  static const Duration _connectTimeout = Duration(seconds: 10);

  ConnectionStatus _status = ConnectionStatus.disconnected;
  String _ip = '';
  int _port = HostAddress.defaultPort;
  String? _errorMessage;
  String? _connectedIp;
  int? _connectedPort;
  List<HostAddress> _recent = [];
  Timer? _timeoutTimer;

  ConnectionStatus get status => _status;
  String get ip => _ip;
  int get port => _port;
  String? get errorMessage => _errorMessage;
  /// 현재 실제로 연결된 IP. 미연결 시 null.
  String? get connectedIp => _connectedIp;
  /// 현재 실제로 연결된 포트. 미연결 시 null.
  int? get connectedPort => _connectedPort;
  /// 최근 연결에 성공한 주소 (최신순).
  List<HostAddress> get recent => List.unmodifiable(_recent);
  RosbridgeService get service => _service;

  bool get isConnected => _status == ConnectionStatus.connected;

  ConnectionProvider() {
    _service.onStatusChange = (s) {
      _status = s;
      if (s == ConnectionStatus.connected) {
        // 연결 성공 → 최초 연결 타임아웃 해제 (이후 자동 재연결을 끊지 않도록)
        _timeoutTimer?.cancel();
        _timeoutTimer = null;
        _connectedIp = _ip;
        _connectedPort = _port;
        _errorMessage = null;
        _remember(HostAddress(_ip, _port));
      } else if (s == ConnectionStatus.failed) {
        _connectedIp = null;
        _connectedPort = null;
        _errorMessage = 'Could not reach ws://$_ip:$_port';
      } else if (s == ConnectionStatus.disconnected) {
        _connectedIp = null;
        _connectedPort = null;
      }
      notifyListeners();
    };
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _ip = prefs.getString('last_ip') ?? '';
    _port = prefs.getInt('last_port') ?? HostAddress.defaultPort;
    _recent = (prefs.getStringList('recent_hosts') ?? [])
        .map((s) => HostAddress.tryParse(s))
        .whereType<HostAddress>()
        .toList();
    notifyListeners();
  }

  Future<void> _remember(HostAddress a) async {
    _recent = [a, ..._recent.where((r) => r != a)].take(maxRecent).toList();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('recent_hosts', _recent.map((r) => r.label).toList());
  }

  Future<void> forget(HostAddress a) async {
    _recent = _recent.where((r) => r != a).toList();
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('recent_hosts', _recent.map((r) => r.label).toList());
  }

  Future<void> connect(String ip, int port) async {
    _ip = ip;
    _port = port;
    _errorMessage = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('last_ip', _ip);
    await prefs.setInt('last_port', _port);

    _timeoutTimer?.cancel();
    _timeoutTimer = Timer(_connectTimeout, () {
      if (_status == ConnectionStatus.connecting) {
        _errorMessage = 'Timed out connecting to ws://$_ip:$_port';
        _timeoutTimer = null;
        _status = ConnectionStatus.disconnected;
        notifyListeners();
        _service.disconnect();
      }
    });

    await _service.connect(ip, port);
  }

  /// 연결 시도를 사용자가 명시적으로 취소할 때 호출.
  Future<void> cancelConnect() async {
    _timeoutTimer?.cancel();
    _timeoutTimer = null;
    _errorMessage = null;
    _status = ConnectionStatus.disconnected;
    notifyListeners();
    await _service.disconnect();
  }

  Future<void> disconnect() async {
    _timeoutTimer?.cancel();
    _timeoutTimer = null;
    _status = ConnectionStatus.disconnected;
    _errorMessage = null;
    notifyListeners();
    await _service.disconnect();
  }

  @override
  void dispose() {
    _timeoutTimer?.cancel();
    _service.disconnect();
    super.dispose();
  }
}

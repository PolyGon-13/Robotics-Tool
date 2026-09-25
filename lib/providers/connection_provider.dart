import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/rosbridge_service.dart';

export '../services/rosbridge_service.dart' show ConnectionStatus;

class ConnectionProvider extends ChangeNotifier {
  final RosbridgeService _service = RosbridgeService();

  ConnectionStatus _status = ConnectionStatus.disconnected;
  String _ip = '';
  int _port = 9090;
  String? _errorMessage;
  String? _connectedIp;
  int? _connectedPort;

  ConnectionStatus get status => _status;
  String get ip => _ip;
  int get port => _port;
  String? get errorMessage => _errorMessage;
  /// 현재 실제로 연결된 IP. 미연결 시 null.
  String? get connectedIp => _connectedIp;
  /// 현재 실제로 연결된 포트. 미연결 시 null.
  int? get connectedPort => _connectedPort;
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
      } else if (s == ConnectionStatus.failed) {
        _connectedIp = null;
        _connectedPort = null;
        _errorMessage = 'Connection failed after $_maxRetries attempts';
      } else if (s == ConnectionStatus.disconnected) {
        _connectedIp = null;
        _connectedPort = null;
      }
      notifyListeners();
    };
    _loadLastIp();
  }

  static const int _maxRetries = 3;
  static const Duration _connectTimeout = Duration(seconds: 10);
  Timer? _timeoutTimer;

  Future<void> _loadLastIp() async {
    final prefs = await SharedPreferences.getInstance();
    _ip = prefs.getString('last_ip') ?? '';
    _port = prefs.getInt('last_port') ?? 9090;
    notifyListeners();
  }

  Future<void> _saveLastIp() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('last_ip', _ip);
    await prefs.setInt('last_port', _port);
  }

  Future<void> connect(String ip, int port) async {
    _ip = ip;
    _port = port;
    _errorMessage = null;
    await _saveLastIp();

    _timeoutTimer?.cancel();
    _timeoutTimer = Timer(_connectTimeout, () {
      if (_status == ConnectionStatus.connecting) {
        _errorMessage = 'Connection timed out';
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

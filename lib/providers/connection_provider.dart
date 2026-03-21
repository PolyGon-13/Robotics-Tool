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

  ConnectionStatus get status => _status;
  String get ip => _ip;
  int get port => _port;
  String? get errorMessage => _errorMessage;
  RosbridgeService get service => _service;

  bool get isConnected => _status == ConnectionStatus.connected;

  ConnectionProvider() {
    _service.onStatusChange = (s) {
      _status = s;
      if (s == ConnectionStatus.failed) {
        _errorMessage = 'Connection failed after $_maxRetries attempts';
      } else if (s == ConnectionStatus.connected) {
        _errorMessage = null;
      }
      notifyListeners();
    };
    _loadLastIp();
  }

  static const int _maxRetries = 3;

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
    await _service.connect(ip, port);
  }

  Future<void> disconnect() async {
    _status = ConnectionStatus.disconnected;
    _errorMessage = null;
    notifyListeners();
    await _service.disconnect();
  }

  @override
  void dispose() {
    _service.disconnect();
    super.dispose();
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers/connection_provider.dart';
import '../widgets/connection_status_badge.dart';
import '../widgets/settings_button.dart';

class ConnectionScreen extends StatefulWidget {
  const ConnectionScreen({super.key});

  @override
  State<ConnectionScreen> createState() => _ConnectionScreenState();
}

class _ConnectionScreenState extends State<ConnectionScreen> {
  final _ipController = TextEditingController();
  final _portController = TextEditingController(text: '9090');
  bool _hasNavigated = false;

  @override
  void initState() {
    super.initState();
    _restoreIpPort();
  }

  Future<void> _restoreIpPort() async {
    final prefs = await SharedPreferences.getInstance();
    final ip = prefs.getString('last_ip') ?? '';
    final port = prefs.getInt('last_port') ?? 9090;
    if (mounted) {
      setState(() {
        if (ip.isNotEmpty) _ipController.text = ip;
        _portController.text = port.toString();
      });
    }
  }

  @override
  void dispose() {
    _ipController.dispose();
    _portController.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final ip = _ipController.text.trim();
    final port = int.tryParse(_portController.text.trim()) ?? 9090;
    if (ip.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter an IP address')),
      );
      return;
    }
    await context.read<ConnectionProvider>().connect(ip, port);
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ConnectionProvider>(
      builder: (context, conn, _) {
        // Navigate when connected
        if (conn.isConnected && !_hasNavigated) {
          _hasNavigated = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              Navigator.pushReplacementNamed(context, '/main');
            }
          });
        }
        if (!conn.isConnected) _hasNavigated = false;

        return Scaffold(
          appBar: AppBar(
            title: const Text('ROS2 Monitor'),
            centerTitle: true,
            actions: const [SettingsButton()],
          ),
          body: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(Icons.router, size: 80, color: Colors.blue),
                    const SizedBox(height: 32),
                    const Text(
                      'Connect to rosbridge',
                      style:
                          TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 32),
                    TextField(
                      controller: _ipController,
                      decoration: const InputDecoration(
                        labelText: 'ROS PC IP Address',
                        hintText: '192.168.1.100',
                        prefixIcon: Icon(Icons.computer),
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _portController,
                      decoration: const InputDecoration(
                        labelText: 'Port',
                        prefixIcon: Icon(Icons.settings_ethernet),
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      readOnly: true,
                      decoration: const InputDecoration(
                        labelText: 'ROS_DOMAIN_ID (server side)',
                        hintText: '0',
                        prefixIcon: Icon(Icons.info_outline),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 24),
                    const ConnectionStatusBadge(),
                    if (conn.errorMessage != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        conn.errorMessage!,
                        style: const TextStyle(color: Colors.red),
                        textAlign: TextAlign.center,
                      ),
                    ],
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: conn.status == ConnectionStatus.connecting
                          ? null
                          : _connect,
                      icon: conn.status == ConnectionStatus.connecting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.link),
                      label: Text(
                        conn.status == ConnectionStatus.connecting
                            ? 'Connecting…'
                            : 'Connect',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

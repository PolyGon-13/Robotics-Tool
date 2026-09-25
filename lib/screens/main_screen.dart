import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/connection_provider.dart';
import '../providers/topic_provider.dart';
import 'graph_screen.dart';
import 'topic_list_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;
  bool _wasConnected = false;
  bool _navigating = false;
  int _seenGraphRequest = 0;
  ConnectionProvider? _connProvider;
  TopicProvider? _topicProvider;

  static const _tabs = [
    NavigationDestination(icon: Icon(Icons.list), label: 'Topics'),
    NavigationDestination(icon: Icon(Icons.account_tree), label: 'Graph'),
  ];

  static const _screens = [
    TopicListScreen(),
    GraphScreen(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _connProvider = context.read<ConnectionProvider>();
      _wasConnected = _connProvider!.status == ConnectionStatus.connected;
      _connProvider!.addListener(_onConnectionChanged);
      _topicProvider = context.read<TopicProvider>();
      _seenGraphRequest = _topicProvider!.graphFocusRequest;
      _topicProvider!.addListener(_onTopicsChanged);
    });
  }

  @override
  void dispose() {
    _connProvider?.removeListener(_onConnectionChanged);
    _topicProvider?.removeListener(_onTopicsChanged);
    super.dispose();
  }

  void _onTopicsChanged() {
    final req = _topicProvider!.graphFocusRequest;
    if (req != _seenGraphRequest && mounted) {
      _seenGraphRequest = req;
      setState(() => _currentIndex = 1);
    }
  }

  void _onConnectionChanged() {
    if (!mounted || _navigating) return;
    final status = _connProvider!.status;
    if (status == ConnectionStatus.connected) {
      _wasConnected = true;
    } else if (_wasConnected &&
        (status == ConnectionStatus.failed ||
            status == ConnectionStatus.disconnected)) {
      _wasConnected = false;
      _navigating = true;
      final message = status == ConnectionStatus.failed
          ? 'Lost connection to ${_connProvider!.ip}:${_connProvider!.port}'
          : null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final messenger = ScaffoldMessenger.of(context);
        Navigator.of(context).pushNamedAndRemoveUntil('/', (_) => false);
        if (message != null) {
          messenger.showSnackBar(SnackBar(content: Text(message)));
        }
      });
    }
  }

  /// Back from the main screen ends the session (after asking), instead of
  /// leaving the connection running behind the home screen.
  Future<void> _confirmDisconnect() async {
    final conn = context.read<ConnectionProvider>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Disconnect?'),
        content: Text('Close the connection to ${conn.ip}:${conn.port}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Stay')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Disconnect')),
        ],
      ),
    );
    // The connection listener navigates home once disconnected
    if (ok == true) await conn.disconnect();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_currentIndex != 0) {
          setState(() => _currentIndex = 0); // Back from Graph → Topics first
        } else {
          _confirmDisconnect();
        }
      },
      child: Scaffold(
        body: IndexedStack(
          index: _currentIndex,
          children: _screens,
        ),
        bottomNavigationBar: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _ReconnectBanner(),
            NavigationBar(
              selectedIndex: _currentIndex,
              onDestinationSelected: (i) => setState(() => _currentIndex = i),
              destinations: _tabs,
            ),
          ],
        ),
      ),
    );
  }
}

/// Shown while the link dropped and the service is retrying.
class _ReconnectBanner extends StatelessWidget {
  const _ReconnectBanner();

  @override
  Widget build(BuildContext context) {
    final conn = context.watch<ConnectionProvider>();
    final show = conn.status == ConnectionStatus.connecting;
    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      child: !show
          ? const SizedBox(width: double.infinity)
          : Container(
              width: double.infinity,
              color: Colors.orange.shade800,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Connection lost — reconnecting to ${conn.ip}:${conn.port}…',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/connection_provider.dart';
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
  ConnectionProvider? _connProvider;

  static const _tabs = [
    NavigationDestination(icon: Icon(Icons.list),         label: 'Topics'),
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
      _wasConnected =
          _connProvider!.status == ConnectionStatus.connected;
      _connProvider!.addListener(_onConnectionChanged);
    });
  }

  @override
  void dispose() {
    _connProvider?.removeListener(_onConnectionChanged);
    super.dispose();
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
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Navigator.of(context).pushNamedAndRemoveUntil('/', (_) => false);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) => setState(() => _currentIndex = i),
        destinations: _tabs,
      ),
    );
  }
}

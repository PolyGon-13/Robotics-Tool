import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/connection_provider.dart';
import '../providers/theme_provider.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          // ── 섹션 1: 테마 ───────────────────────────────────────────────
          const _SectionHeader('Theme'),
          Consumer<ThemeProvider>(
            builder: (context, tp, _) => RadioGroup<ThemeMode>(
              groupValue: tp.themeMode,
              onChanged: (v) { if (v != null) tp.setThemeMode(v); },
              child: Column(
                children: [
                  RadioListTile<ThemeMode>(
                    title: const Text('System Default'),
                    subtitle: const Text('Follow device settings'),
                    secondary: const Icon(Icons.brightness_auto),
                    value: ThemeMode.system,
                  ),
                  RadioListTile<ThemeMode>(
                    title: const Text('Light'),
                    secondary: const Icon(Icons.light_mode),
                    value: ThemeMode.light,
                  ),
                  RadioListTile<ThemeMode>(
                    title: const Text('Dark'),
                    secondary: const Icon(Icons.dark_mode),
                    value: ThemeMode.dark,
                  ),
                ],
              ),
            ),
          ),

          const Divider(),

          // ── 섹션 2: 연결 정보 + 연결 끊기 ────────────────────────────
          const _SectionHeader('Connection'),
          Consumer<ConnectionProvider>(
            builder: (context, conn, _) => Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.computer),
                  title: const Text('Last IP'),
                  subtitle: Text(
                    conn.ip.isEmpty ? 'Not connected yet' : conn.ip,
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.settings_ethernet),
                  title: const Text('Port'),
                  subtitle: Text(conn.port.toString()),
                ),
                ListTile(
                  leading: Icon(
                    Icons.circle,
                    size: 14,
                    color: switch (conn.status) {
                      ConnectionStatus.connected    => Colors.green,
                      ConnectionStatus.connecting   => Colors.orange,
                      ConnectionStatus.failed       => Colors.red,
                      ConnectionStatus.disconnected => Colors.grey,
                    },
                  ),
                  title: const Text('Status'),
                  subtitle: Text(switch (conn.status) {
                    ConnectionStatus.connected    => 'Connected',
                    ConnectionStatus.connecting   => 'Connecting…',
                    ConnectionStatus.failed       => 'Connection Failed',
                    ConnectionStatus.disconnected => 'Disconnected',
                  }),
                ),

                // ── Disconnect 버튼 ────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Theme.of(context).colorScheme.error,
                        side: BorderSide(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                      // disconnect() → 즉시 상태 disconnected로 변경
                      // → main_screen 리스너가 '/'로 이동 처리
                      onPressed: conn.status == ConnectionStatus.disconnected
                          ? null
                          : () => conn.disconnect(),
                      icon: const Icon(Icons.link_off),
                      label: const Text('Disconnect'),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const Divider(),

          // ── 섹션 3: 앱 정보 ────────────────────────────────────────────
          const _SectionHeader('About'),
          const ListTile(
            leading: Icon(Icons.apps),
            title: Text('App Name'),
            subtitle: Text('Robotics-Tool'),
          ),
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('Version'),
            subtitle: Text('1.0.0'),
          ),
          const ListTile(
            leading: Icon(Icons.person_outline),
            title: Text('Developer'),
            subtitle: Text('PolyGon'),
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/connection_provider.dart';
import '../utils/host_address.dart';
import '../widgets/connection_status_badge.dart';
import '../widgets/settings_button.dart';

class ConnectionScreen extends StatefulWidget {
  const ConnectionScreen({super.key});

  @override
  State<ConnectionScreen> createState() => _ConnectionScreenState();
}

class _ConnectionScreenState extends State<ConnectionScreen> {
  final _hostController = TextEditingController();
  final _portController = TextEditingController(text: '${HostAddress.defaultPort}');
  bool _hasNavigated = false;
  bool _restored = false;
  String? _inputError;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_restored) return;
    final conn = context.read<ConnectionProvider>();
    if (conn.ip.isNotEmpty) {
      _hostController.text = conn.ip;
      _portController.text = '${conn.port}';
      _restored = true;
    }
  }

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    super.dispose();
  }

  Future<void> _connect([HostAddress? target]) async {
    FocusScope.of(context).unfocus();
    String? error;
    final port = int.tryParse(_portController.text.trim());
    final addr = target ??
        HostAddress.tryParse(_hostController.text,
            fallbackPort: port ?? HostAddress.defaultPort, onError: (e) => error = e);
    if (target == null && port == null && _portController.text.trim().isNotEmpty) {
      error = 'Port must be a number';
    }
    setState(() => _inputError = addr == null || error != null ? error : null);
    if (addr == null || error != null) return;

    _hostController.text = addr.host;
    _portController.text = '${addr.port}';
    await context.read<ConnectionProvider>().connect(addr.host, addr.port);
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ConnectionProvider>(
      builder: (context, conn, _) {
        // Fill the fields once the saved address has loaded (after this
        // frame: changing a controller during build would rebuild mid-build)
        if (!_restored && conn.ip.isNotEmpty) {
          _restored = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || _hostController.text.isNotEmpty) return;
            _hostController.text = conn.ip;
            _portController.text = '${conn.port}';
          });
        }
        if (conn.isConnected && !_hasNavigated) {
          _hasNavigated = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            // Replace everything above Home (also a Settings page opened
            // while connecting), so Back from Main never lands here again
            if (mounted) {
              Navigator.of(context).pushNamedAndRemoveUntil('/main', ModalRoute.withName('/'));
            }
          });
        }
        if (!conn.isConnected) _hasNavigated = false;
        final connecting = conn.status == ConnectionStatus.connecting;
        final cs = Theme.of(context).colorScheme;

        return PopScope(
          onPopInvokedWithResult: (didPop, _) {
            if (didPop && connecting) conn.cancelConnect();
          },
          child: Scaffold(
            appBar: AppBar(
              title: const Text('Connect'),
              actions: const [SettingsButton()],
            ),
            body: SafeArea(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                children: [
                  Icon(Icons.router_outlined, size: 64, color: cs.primary),
                  const SizedBox(height: 12),
                  Text('Connect to rosbridge',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  Text(
                    'Enter the IP address of the PC running rosbridge_server.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 3,
                        child: TextField(
                          controller: _hostController,
                          enabled: !connecting,
                          keyboardType: TextInputType.url,
                          autocorrect: false,
                          textInputAction: TextInputAction.go,
                          onSubmitted: (_) => _connect(),
                          onChanged: (_) {
                            if (_inputError != null) setState(() => _inputError = null);
                          },
                          decoration: InputDecoration(
                            labelText: 'IP address',
                            hintText: '192.168.0.10',
                            prefixIcon: const Icon(Icons.computer),
                            border: const OutlineInputBorder(),
                            errorText: _inputError,
                            errorMaxLines: 2,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 1,
                        child: TextField(
                          controller: _portController,
                          enabled: !connecting,
                          keyboardType: TextInputType.number,
                          textInputAction: TextInputAction.go,
                          onSubmitted: (_) => _connect(),
                          decoration: const InputDecoration(
                            labelText: 'Port',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 52,
                    child: FilledButton.icon(
                      onPressed: connecting ? conn.cancelConnect : () => _connect(),
                      icon: connecting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.link),
                      label: Text(connecting ? 'Connecting… (tap to cancel)' : 'Connect',
                          style: const TextStyle(fontSize: 16)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const ConnectionStatusBadge(),
                  if (conn.errorMessage != null && !connecting) ...[
                    const SizedBox(height: 12),
                    _TroubleshootCard(message: conn.errorMessage!),
                  ],
                  if (conn.recent.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    Text('Recent',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(color: cs.primary)),
                    const SizedBox(height: 4),
                    for (final r in conn.recent)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.history),
                        title: Text(r.label),
                        enabled: !connecting,
                        onTap: () => _connect(r),
                        trailing: IconButton(
                          tooltip: 'Remove ${r.label}',
                          icon: const Icon(Icons.close),
                          onPressed: () => conn.forget(r),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _TroubleshootCard extends StatelessWidget {
  final String message;
  const _TroubleshootCard({required this.message});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget item(String text, [String? code]) => Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('•  ', style: TextStyle(color: cs.onErrorContainer)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(text, style: TextStyle(color: cs.onErrorContainer)),
                    if (code != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: SelectableText(code,
                            style: TextStyle(
                                fontFamily: 'monospace', fontSize: 12, color: cs.onErrorContainer)),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(message,
              style: TextStyle(fontWeight: FontWeight.w700, color: cs.onErrorContainer)),
          const SizedBox(height: 4),
          Text('Check that:', style: TextStyle(color: cs.onErrorContainer)),
          item('rosbridge is running on the PC',
              'ros2 launch rosbridge_server rosbridge_websocket_launch.xml'),
          item('The phone and the PC are on the same Wi-Fi network'),
          item('The IP is the PC\'s address', 'hostname -I'),
          item('The port (default 9090) is not blocked by a firewall'),
        ],
      ),
    );
  }
}

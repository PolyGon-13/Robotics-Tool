import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/connection_provider.dart';
import '../utils/rate_meter.dart';
import '../widgets/raw_json_tree_widget.dart';
import '../widgets/visualizations/visualizer_registry.dart';

class VisualizationScreen extends StatefulWidget {
  final String topic;
  final String type;

  const VisualizationScreen({
    super.key,
    required this.topic,
    required this.type,
  });

  @override
  State<VisualizationScreen> createState() => _VisualizationScreenState();
}

class _VisualizationScreenState extends State<VisualizationScreen> {
  StreamSubscription? _sub;
  late final ConnectionProvider _conn;
  final RateMeter _rate = RateMeter();
  Timer? _ticker;

  Map<String, dynamic>? _latestMsg;
  bool _paused = false;
  late bool _showRaw = !hasVisualizer(widget.type);
  final DateTime _openedAt = DateTime.now();

  @override
  void initState() {
    super.initState();
    _conn = context.read<ConnectionProvider>();
    _sub = _conn.service.subscribe(widget.topic, widget.type).listen(_onMsg);
    // Refresh rate / "no data" status even when no messages arrive.
    _ticker = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted) setState(() {});
    });
  }

  void _onMsg(Map<String, dynamic> msg) {
    _rate.tick();
    if (_paused) return;
    setState(() => _latestMsg = msg);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _sub?.cancel();
    _conn.service.unsubscribe(widget.topic);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canVisualize = hasVisualizer(widget.type);
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.topic,
                style: const TextStyle(fontSize: 16),
                overflow: TextOverflow.ellipsis),
            Text(widget.type,
                style: Theme.of(context).textTheme.bodySmall,
                overflow: TextOverflow.ellipsis),
          ],
        ),
        actions: [
          if (canVisualize)
            IconButton(
              icon: Icon(_showRaw ? Icons.insights : Icons.data_object),
              tooltip: _showRaw ? 'Show visualization' : 'Show raw message',
              onPressed: () => setState(() => _showRaw = !_showRaw),
            ),
          IconButton(
            icon: Icon(_paused ? Icons.play_arrow : Icons.pause),
            tooltip: _paused ? 'Resume' : 'Pause',
            onPressed: () => setState(() => _paused = !_paused),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(30),
          child: _StatusStrip(
            rate: _rate,
            paused: _paused,
            connected: context.watch<ConnectionProvider>().isConnected,
            waitingFor: DateTime.now().difference(_openedAt),
          ),
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    final msg = _latestMsg;
    if (msg == null) {
      return _WaitingForData(
        topic: widget.topic,
        waited: DateTime.now().difference(_openedAt),
      );
    }
    final raw = SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: RawJsonTreeWidget(data: msg),
    );
    if (!hasVisualizer(widget.type)) return raw;
    // Keep the visualizer mounted while raw JSON is shown so its history
    // (charts, trajectory) keeps recording.
    return IndexedStack(
      index: _showRaw ? 1 : 0,
      sizing: StackFit.expand,
      children: [
        buildVisualizer(widget.type, widget.topic, msg),
        _showRaw ? raw : const SizedBox.shrink(),
      ],
    );
  }
}

// ─── Status strip ────────────────────────────────────────────────────────────

class _StatusStrip extends StatelessWidget {
  final RateMeter rate;
  final bool paused;
  final bool connected;
  final Duration waitingFor;

  const _StatusStrip({
    required this.rate,
    required this.paused,
    required this.connected,
    required this.waitingFor,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final now = DateTime.now();

    final (IconData icon, Color color, String text) = switch (true) {
      _ when !connected => (Icons.link_off, cs.error, 'Disconnected — reconnecting…'),
      _ when !rate.hasData => (Icons.hourglass_empty, cs.outline,
          'Waiting for data… ${_secs(waitingFor)}'),
      _ when rate.isStale(now) => (Icons.warning_amber_rounded, Colors.orange.shade800,
          'No data for ${_secs(rate.sinceLast(now)!)}'),
      _ => (Icons.circle, Colors.green.shade600,
          '${rate.rate(now).toStringAsFixed(1)} Hz'),
    };

    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      color: color.withValues(alpha: 0.12),
      child: Row(
        children: [
          Icon(icon, size: icon == Icons.circle ? 10 : 16, color: color),
          const SizedBox(width: 8),
          Text(text,
              style: TextStyle(
                  color: color, fontWeight: FontWeight.w600, fontSize: 13)),
          const Spacer(),
          if (paused) ...[
            Icon(Icons.pause_circle, size: 16, color: cs.primary),
            const SizedBox(width: 4),
            Text('Paused',
                style: TextStyle(color: cs.primary, fontSize: 13)),
            const SizedBox(width: 12),
          ],
          Text('${rate.count} msgs',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
        ],
      ),
    );
  }

  static String _secs(Duration d) =>
      '${(d.inMilliseconds / 1000).toStringAsFixed(1)} s';
}

class _WaitingForData extends StatelessWidget {
  final String topic;
  final Duration waited;

  const _WaitingForData({required this.topic, required this.waited});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final slow = waited > const Duration(seconds: 3);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 20),
            Text('Waiting for the first message on $topic',
                textAlign: TextAlign.center),
            if (slow) ...[
              const SizedBox(height: 12),
              Text(
                'Nothing received yet. The topic may have no active publisher, '
                'or it publishes rarely.',
                textAlign: TextAlign.center,
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

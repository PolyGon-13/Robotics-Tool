import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/ros_message.dart';
import '../providers/connection_provider.dart';
import '../widgets/raw_json_tree_widget.dart';

class RawDataScreen extends StatefulWidget {
  final String topic;
  final String type;

  const RawDataScreen({super.key, required this.topic, required this.type});

  @override
  State<RawDataScreen> createState() => _RawDataScreenState();
}

class _RawDataScreenState extends State<RawDataScreen> {
  final List<RosMessage> _history = [];
  StreamSubscription? _sub;
  int _selected = 0;

  static const int _maxHistory = 20;

  @override
  void initState() {
    super.initState();
    final service = context.read<ConnectionProvider>().service;
    _sub = service.subscribe(widget.topic, widget.type).listen((msg) {
      setState(() {
        _history.insert(
            0, RosMessage.now(topic: widget.topic, data: msg));
        if (_history.length > _maxHistory) _history.removeLast();
        _selected = 0;
      });
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    context.read<ConnectionProvider>().service.unsubscribe(widget.topic);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // When used as a standalone screen (embedded in VisualizationScreen),
    // we don't add an AppBar; otherwise we add one.
    final isEmbedded = ModalRoute.of(context) == null ||
        ModalRoute.of(context)!.settings.name == null;

    Widget body = _buildBody();

    if (isEmbedded) return body;

    return Scaffold(
      appBar: AppBar(
        title: Text('Raw: ${widget.topic}'),
        actions: [
          if (_history.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.copy),
              tooltip: 'Copy JSON',
              onPressed: _copySelected,
            ),
        ],
      ),
      body: body,
    );
  }

  Widget _buildBody() {
    if (_history.isEmpty) {
      return const Center(child: Text('Waiting for messages…'));
    }

    return Column(
      children: [
        _buildHistoryBar(),
        const Divider(height: 1),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(8),
            child: RawJsonTreeWidget(data: _history[_selected].data),
          ),
        ),
      ],
    );
  }

  Widget _buildHistoryBar() {
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Text('History:', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _history.length,
              separatorBuilder: (_, _) => const SizedBox(width: 4),
              itemBuilder: (_, i) {
                final ts = _history[i].receivedAt;
                final label =
                    '${ts.hour.toString().padLeft(2, '0')}:${ts.minute.toString().padLeft(2, '0')}:${ts.second.toString().padLeft(2, '0')}';
                return ChoiceChip(
                  label: Text(label, style: const TextStyle(fontSize: 11)),
                  selected: _selected == i,
                  onSelected: (_) => setState(() => _selected = i),
                );
              },
            ),
          ),
          IconButton(
            icon: const Icon(Icons.copy, size: 20),
            tooltip: 'Copy',
            onPressed: _history.isEmpty ? null : _copySelected,
          ),
        ],
      ),
    );
  }

  void _copySelected() {
    if (_history.isEmpty) return;
    final text = const JsonEncoder.withIndent('  ').convert(_history[_selected].data);
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Copied to clipboard')),
    );
  }
}

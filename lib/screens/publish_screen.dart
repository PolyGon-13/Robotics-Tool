import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/connection_provider.dart';
import '../widgets/settings_button.dart';

class PublishScreen extends StatefulWidget {
  final String topic;
  final String type;

  const PublishScreen({super.key, required this.topic, required this.type});

  @override
  State<PublishScreen> createState() => _PublishScreenState();
}

class _PublishScreenState extends State<PublishScreen> {
  late final TextEditingController _controller;
  bool _isValid = true;
  String? _errorText;
  bool _isRepeating = false;
  int _intervalMs = 500;
  Timer? _timer;
  bool _isSending = false;

  static const List<int> _intervals = [100, 500, 1000];

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _defaultTemplate(widget.type));
    _controller.addListener(_validate);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  // ─── 타입별 기본 JSON 템플릿 ──────────────────────────────────────────────

  String _defaultTemplate(String type) {
    if (type.contains('Twist')) {
      return '{\n'
          '  "linear":  {"x": 0.0, "y": 0.0, "z": 0.0},\n'
          '  "angular": {"x": 0.0, "y": 0.0, "z": 0.0}\n'
          '}';
    }
    if (type.contains('Vector3')) {
      return '{"x": 0.0, "y": 0.0, "z": 0.0}';
    }
    if (type.contains('Point')) {
      return '{"x": 0.0, "y": 0.0, "z": 0.0}';
    }
    if (type.contains('Pose')) {
      return '{\n'
          '  "position":    {"x": 0.0, "y": 0.0, "z": 0.0},\n'
          '  "orientation": {"x": 0.0, "y": 0.0, "z": 0.0, "w": 1.0}\n'
          '}';
    }
    if (type.contains('std_msgs') || type.contains('std_msgs/msg')) {
      if (type.contains('String')) return '{"data": ""}';
      if (type.contains('Bool'))   return '{"data": false}';
      if (type.contains('Float')) return '{"data": 0.0}';
      return '{"data": 0}';
    }
    return '{}';
  }

  // ─── JSON 유효성 검사 ─────────────────────────────────────────────────────

  void _validate() {
    try {
      jsonDecode(_controller.text);
      if (_isValid && _errorText == null) return; // 이미 유효 상태면 setState 생략
      setState(() {
        _isValid = true;
        _errorText = null;
      });
    } on FormatException catch (e) {
      setState(() {
        _isValid = false;
        _errorText = e.message;
      });
    }
  }

  // ─── 발행 ─────────────────────────────────────────────────────────────────

  Future<void> _sendOnce() async {
    if (!_isValid) return;
    setState(() => _isSending = true);
    try {
      final msg = jsonDecode(_controller.text) as Map<String, dynamic>;
      context.read<ConnectionProvider>().service.publish(
            widget.topic,
            widget.type,
            msg,
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Published!'),
            duration: Duration(milliseconds: 800),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Publish failed: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  void _toggleRepeat(bool value) {
    _timer?.cancel();
    _timer = null;
    if (value && _isValid) {
      _timer = Timer.periodic(
        Duration(milliseconds: _intervalMs),
        (_) => _sendOnce(),
      );
    }
    setState(() => _isRepeating = value && _isValid);
  }

  void _onIntervalChanged(int? val) {
    if (val == null) return;
    setState(() => _intervalMs = val);
    if (_isRepeating) {
      // 인터벌 변경 시 타이머 재시작
      _toggleRepeat(false);
      _toggleRepeat(true);
    }
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Publish', style: TextStyle(fontSize: 16)),
            Text(
              widget.topic,
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        actions: const [SettingsButton()],
      ),
      body: Column(
        children: [
          // 타입 칩
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Chip(
                avatar: const Icon(Icons.label_outline, size: 16),
                label: Text(widget.type, style: const TextStyle(fontSize: 11)),
                padding: EdgeInsets.zero,
              ),
            ),
          ),

          // JSON 에디터
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: TextField(
                controller: _controller,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                keyboardType: TextInputType.multiline,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                decoration: InputDecoration(
                  labelText: 'Message (JSON)',
                  alignLabelWithHint: true,
                  border: const OutlineInputBorder(),
                  errorText: _errorText,
                  errorMaxLines: 3,
                ),
              ),
            ),
          ),

          // 반복 발행 토글
          SwitchListTile(
            title: const Text('Repeat Publish'),
            subtitle: Text(
              _isRepeating
                  ? 'Publishing every $_intervalMs ms…'
                  : 'Send repeatedly on interval',
            ),
            secondary: Icon(
              _isRepeating ? Icons.pause_circle : Icons.repeat,
              color: _isRepeating ? cs.primary : null,
            ),
            value: _isRepeating,
            onChanged: _isValid ? _toggleRepeat : null,
          ),

          // 인터벌 선택 (반복 중일 때만 표시)
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            child: _isRepeating
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Interval',
                        border: OutlineInputBorder(),
                        isDense: true,
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<int>(
                          value: _intervalMs,
                          isDense: true,
                          isExpanded: true,
                          items: _intervals
                              .map((ms) => DropdownMenuItem(
                                    value: ms,
                                    child: Text('$ms ms'),
                                  ))
                              .toList(),
                          onChanged: _onIntervalChanged,
                        ),
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),

          // Publish Once 버튼
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: (!_isValid || _isSending) ? null : _sendOnce,
                  icon: _isSending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.send),
                  label: const Text('Publish Once'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

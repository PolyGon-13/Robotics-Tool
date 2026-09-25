import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/connection_provider.dart';
import '../services/rosbridge_service.dart';
import '../utils/ros_msg.dart';
import '../widgets/teleop_pad.dart';

class PublishScreen extends StatefulWidget {
  final String topic;
  final String type;

  const PublishScreen({super.key, required this.topic, required this.type});

  @override
  State<PublishScreen> createState() => _PublishScreenState();
}

class _PublishScreenState extends State<PublishScreen> {
  late final RosbridgeService _service;
  late final TextEditingController _controller;
  late final bool _isTwist =
      const {'geometry_msgs/Twist', 'geometry_msgs/TwistStamped'}.contains(baseType(widget.type));
  late bool _joystick = _isTwist;

  String _template = '{}';
  bool _edited = false;
  bool _isValid = true;
  String? _errorText;
  bool _isRepeating = false;
  int _intervalMs = 500;
  Timer? _timer;
  int _sentCount = 0;

  static const List<int> _intervals = [100, 200, 500, 1000];
  static const _encoder = JsonEncoder.withIndent('  ');

  @override
  void initState() {
    super.initState();
    _service = context.read<ConnectionProvider>().service;
    _service.advertise(widget.topic, widget.type);
    _template = _fallbackTemplate(widget.type);
    _controller = TextEditingController(text: _template);
    _controller.addListener(_validate);
    _loadTemplate();
  }

  @override
  void dispose() {
    _timer?.cancel();
    // Let the joystick's final stop messages go out before unadvertising
    final service = _service;
    final topic = widget.topic;
    Timer(const Duration(seconds: 1), () => service.unadvertise(topic));
    _controller.dispose();
    super.dispose();
  }

  // ─── Templates ────────────────────────────────────────────────────────────

  /// Ask rosapi for the message definition; keeps the user's edits.
  Future<void> _loadTemplate() async {
    try {
      final t = await _service.getMessageTemplate(widget.type);
      if (t == null || !mounted) return;
      _template = _encoder.convert(t);
      if (!_edited) {
        _controller.text = _template;
        _edited = false;
      }
    } catch (_) {
      // rosapi unavailable: keep the built-in template
    }
  }

  String _fallbackTemplate(String type) {
    final t = baseType(type);
    const vec = {'x': 0.0, 'y': 0.0, 'z': 0.0};
    final Object msg = switch (t) {
      'geometry_msgs/Twist' => {'linear': vec, 'angular': vec},
      'geometry_msgs/TwistStamped' => {
          'header': {'frame_id': 'base_link'},
          'twist': {'linear': vec, 'angular': vec},
        },
      'geometry_msgs/Vector3' || 'geometry_msgs/Point' => vec,
      'geometry_msgs/Pose' => {
          'position': vec,
          'orientation': {'x': 0.0, 'y': 0.0, 'z': 0.0, 'w': 1.0},
        },
      'geometry_msgs/PoseStamped' => {
          'header': {'frame_id': 'map'},
          'pose': {
            'position': vec,
            'orientation': {'x': 0.0, 'y': 0.0, 'z': 0.0, 'w': 1.0},
          },
        },
      'std_msgs/String' => {'data': ''},
      'std_msgs/Bool' => {'data': false},
      _ when t.startsWith('std_msgs/Float') => {'data': 0.0},
      _ when t.startsWith('std_msgs/') && !t.contains('Array') => {'data': 0},
      _ => <String, dynamic>{},
    };
    return _encoder.convert(msg);
  }

  // ─── JSON editing ─────────────────────────────────────────────────────────

  void _validate() {
    if (_controller.text != _template) _edited = true;
    try {
      final v = jsonDecode(_controller.text);
      final err = v is Map ? null : 'The message must be a JSON object: { ... }';
      if (_isValid == (err == null) && _errorText == err) return;
      if (err != null && _isRepeating) _toggleRepeat(false);
      setState(() {
        _isValid = err == null;
        _errorText = err;
      });
    } on FormatException catch (e) {
      // Stop repeating: the editor no longer holds a sendable message
      if (_isRepeating) _toggleRepeat(false);
      setState(() {
        _isValid = false;
        _errorText = e.message;
      });
    }
  }

  void _format() {
    try {
      _controller.text = _encoder.convert(jsonDecode(_controller.text));
    } on FormatException {
      // invalid JSON: leave as is, error already shown
    }
  }

  void _reset() {
    _controller.text = _template;
    _edited = false;
  }

  // ─── Publishing ───────────────────────────────────────────────────────────

  bool _publish(Map<String, dynamic> msg) {
    final ok = _service.publish(widget.topic, widget.type, msg);
    if (ok && mounted) setState(() => _sentCount++);
    return ok;
  }

  /// Publishes the editor content once. Returns false (and stops repeating)
  /// if the message could not be sent.
  bool _send({bool fromRepeat = false}) {
    if (!_isValid) return false;
    final decoded = jsonDecode(_controller.text) as Map<String, dynamic>;
    if (!_publish(decoded)) {
      _fail('Not connected — message was not sent');
      return false;
    }
    if (!fromRepeat) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text('Published to ${widget.topic}'),
          duration: const Duration(milliseconds: 900),
        ));
    }
    return true;
  }

  /// Used by the joystick; must not touch [context] (it can run after the
  /// screen is closed to send the final stop).
  bool _sendTwist(double linear, double angular) {
    final twist = {
      'linear': {'x': linear, 'y': 0.0, 'z': 0.0},
      'angular': {'x': 0.0, 'y': 0.0, 'z': angular},
    };
    final Map<String, dynamic> msg;
    if (baseType(widget.type) == 'geometry_msgs/TwistStamped') {
      final now = DateTime.now().microsecondsSinceEpoch;
      msg = {
        'header': {
          'stamp': {'sec': now ~/ 1000000, 'nanosec': (now % 1000000) * 1000},
          'frame_id': 'base_link',
        },
        'twist': twist,
      };
    } else {
      msg = twist;
    }
    return _publish(msg);
  }

  void _fail(String message) {
    if (_isRepeating) _toggleRepeat(false);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        backgroundColor: Theme.of(context).colorScheme.error,
      ));
  }

  void _toggleRepeat(bool value) {
    _timer?.cancel();
    _timer = null;
    if (value && _isValid) {
      _timer = Timer.periodic(
        Duration(milliseconds: _intervalMs),
        (_) => _send(fromRepeat: true),
      );
    }
    setState(() => _isRepeating = value && _isValid);
  }

  void _onIntervalChanged(int? val) {
    if (val == null) return;
    setState(() => _intervalMs = val);
    if (_isRepeating) {
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
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Publish ${widget.topic}', overflow: TextOverflow.ellipsis),
            Text(widget.type,
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                overflow: TextOverflow.ellipsis),
          ],
        ),
        actions: [
          if (_sentCount > 0)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(child: Text('$_sentCount sent', style: TextStyle(color: cs.onSurfaceVariant))),
            ),
        ],
        bottom: !_isTwist
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(52),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: true, label: Text('Joystick'), icon: Icon(Icons.gamepad)),
                      ButtonSegment(value: false, label: Text('JSON'), icon: Icon(Icons.data_object)),
                    ],
                    selected: {_joystick},
                    onSelectionChanged: (s) {
                      if (_isRepeating) _toggleRepeat(false);
                      setState(() => _joystick = s.first);
                    },
                  ),
                ),
              ),
      ),
      body: _joystick
          ? SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: TeleopPad(send: _sendTwist),
            )
          : _jsonEditor(cs),
    );
  }

  Widget _jsonEditor(ColorScheme cs) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
          child: Row(
            children: [
              TextButton.icon(
                onPressed: _reset,
                icon: const Icon(Icons.restart_alt, size: 18),
                label: const Text('Template'),
              ),
              TextButton.icon(
                onPressed: _isValid ? _format : null,
                icon: const Icon(Icons.format_align_left, size: 18),
                label: const Text('Format'),
              ),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: TextField(
              controller: _controller,
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              keyboardType: TextInputType.multiline,
              autocorrect: false,
              enableSuggestions: false,
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
        SwitchListTile(
          title: const Text('Repeat'),
          subtitle: Text(_isRepeating
              ? 'Publishing every $_intervalMs ms'
              : 'Publish continuously at an interval'),
          secondary: Icon(
            _isRepeating ? Icons.pause_circle : Icons.repeat,
            color: _isRepeating ? cs.primary : null,
          ),
          value: _isRepeating,
          onChanged: _isValid ? _toggleRepeat : null,
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          child: _isRepeating
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: SegmentedButton<int>(
                    segments: [
                      for (final ms in _intervals)
                        ButtonSegment(value: ms, label: Text('${1000 ~/ ms} Hz')),
                    ],
                    selected: {_intervalMs},
                    onSelectionChanged: (s) => _onIntervalChanged(s.first),
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton.icon(
                onPressed: _isValid ? () => _send() : null,
                icon: const Icon(Icons.send),
                label: const Text('Publish once'),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

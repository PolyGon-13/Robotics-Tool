import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Sends a velocity command; returns false if it could not be sent.
typedef CommandSender = bool Function(double linear, double angular);

/// Virtual joystick for driving a robot with Twist messages.
///
/// Commands are sent at [rateHz] only while a finger is on the stick.
/// Releasing, pressing STOP, or leaving the screen sends zero velocity
/// several times, so one lost message cannot leave the robot moving.
class TeleopPad extends StatefulWidget {
  final CommandSender send;
  final double rateHz;

  const TeleopPad({super.key, required this.send, this.rateHz = 10});

  @override
  State<TeleopPad> createState() => _TeleopPadState();
}

class _TeleopPadState extends State<TeleopPad> {
  double _maxLinear = 0.3; // m/s
  double _maxAngular = 1.0; // rad/s
  Offset _knob = Offset.zero; // normalized, |knob| <= 1, up = forward
  bool _active = false;
  bool _lastSendFailed = false;
  Timer? _timer;
  final List<Timer> _stopTimers = [];

  // `+ 0.0` turns -0.0 into 0.0 so the readout never shows "-0.00"
  double get _linear => -_knob.dy * _maxLinear + 0.0;
  double get _angular => -_knob.dx * _maxAngular + 0.0; // stick left = turn left (+z)

  void _sendCurrent() {
    final ok = widget.send(_linear, _angular);
    if (ok == _lastSendFailed && mounted) setState(() => _lastSendFailed = !ok);
  }

  void _start() {
    for (final t in _stopTimers) {
      t.cancel();
    }
    _stopTimers.clear();
    _active = true;
    _timer?.cancel();
    _timer = Timer.periodic(
      Duration(milliseconds: (1000 / widget.rateHz).round()),
      (_) => _sendCurrent(),
    );
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
    _active = false;
    if (mounted) setState(() => _knob = Offset.zero);
    final send = widget.send;
    send(0, 0);
    // Repeat the stop in case a message is dropped
    for (final ms in [100, 250]) {
      _stopTimers.add(Timer(Duration(milliseconds: ms), () => send(0, 0)));
    }
  }

  void _move(Offset local, double radius) {
    final center = Offset(radius, radius);
    var v = (local - center) / radius;
    if (v.distance > 1) v = v / v.distance;
    setState(() => _knob = v);
    if (!_active) {
      _start();
      _sendCurrent();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    // Pending repeated stops are left to fire: [send] must not depend on
    // this widget's context.
    if (_active) {
      final send = widget.send;
      send(0, 0);
      Timer(const Duration(milliseconds: 100), () => send(0, 0));
      Timer(const Duration(milliseconds: 250), () => send(0, 0));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return LayoutBuilder(builder: (context, constraints) {
      final size = math.min(constraints.maxWidth - 32, 280.0);
      final radius = size / 2;
      return Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: Colors.orange.shade800),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('The robot moves while you hold the stick. '
                      'Release it to stop.'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _readout(context),
          const SizedBox(height: 16),
          GestureDetector(
            onPanStart: (d) => _move(d.localPosition, radius),
            onPanUpdate: (d) => _move(d.localPosition, radius),
            onPanEnd: (_) => _stop(),
            onPanCancel: _stop,
            child: CustomPaint(
              size: Size.square(size),
              painter: _PadPainter(knob: _knob, active: _active, colors: cs),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton.icon(
              // Same strong red in light and dark themes: it is an emergency control
              style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFC62828), foregroundColor: Colors.white),
              onPressed: _stop,
              icon: const Icon(Icons.stop_circle_outlined),
              label: const Text('STOP', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            ),
          ),
          const SizedBox(height: 16),
          _slider('Max linear speed', _maxLinear, 0.05, 1.5, 'm/s',
              (v) => setState(() => _maxLinear = v)),
          _slider('Max turn speed', _maxAngular, 0.1, 3.0, 'rad/s',
              (v) => setState(() => _maxAngular = v)),
        ],
      );
    });
  }

  Widget _readout(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    const style = TextStyle(fontSize: 22, fontWeight: FontWeight.w700,
        fontFeatures: [FontFeature.tabularFigures()]);
    Widget value(String label, String text) => Expanded(
          child: Column(children: [
            Text(label, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
            FittedBox(fit: BoxFit.scaleDown, child: Text(text, style: style)),
          ]),
        );
    return Column(
      children: [
        Row(children: [
          value('Linear x', '${_linear.toStringAsFixed(2)} m/s'),
          value('Angular z', '${_angular.toStringAsFixed(2)} rad/s'),
        ]),
        if (_lastSendFailed)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('Not connected — commands are not being sent',
                style: TextStyle(color: cs.error, fontWeight: FontWeight.w700)),
          ),
      ],
    );
  }

  Widget _slider(String label, double value, double min, double max, String unit,
      ValueChanged<double> onChanged) {
    return Row(
      children: [
        SizedBox(width: 110, child: Text(label, maxLines: 2)),
        Expanded(
          child: Slider(
            value: value,
            min: min,
            max: max,
            divisions: ((max - min) / 0.05).round(),
            label: '${value.toStringAsFixed(2)} $unit',
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 76,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: Text('${value.toStringAsFixed(2)} $unit'),
          ),
        ),
      ],
    );
  }
}

class _PadPainter extends CustomPainter {
  final Offset knob;
  final bool active;
  final ColorScheme colors;

  _PadPainter({required this.knob, required this.active, required this.colors});

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    canvas.drawCircle(c, r, Paint()..color = colors.surfaceContainerHighest);
    canvas.drawCircle(c, r, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = active ? colors.primary : colors.outline);
    final guide = Paint()
      ..color = colors.outlineVariant
      ..strokeWidth = 1;
    canvas.drawLine(Offset(c.dx, c.dy - r), Offset(c.dx, c.dy + r), guide);
    canvas.drawLine(Offset(c.dx - r, c.dy), Offset(c.dx + r, c.dy), guide);
    for (final (label, at) in [
      ('FWD', Offset(c.dx, c.dy - r + 14)),
      ('BACK', Offset(c.dx, c.dy + r - 14)),
      ('LEFT', Offset(c.dx - r + 24, c.dy)),
      ('RIGHT', Offset(c.dx + r - 26, c.dy)),
    ]) {
      final tp = TextPainter(
        text: TextSpan(text: label, style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, at - Offset(tp.width / 2, tp.height / 2));
    }
    final k = c + knob * (r - 30);
    canvas.drawLine(c, k, Paint()
      ..color = colors.primary.withValues(alpha: 0.4)
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round);
    canvas.drawCircle(k, 30, Paint()..color = active ? colors.primary : colors.secondary);
  }

  @override
  bool shouldRepaint(covariant _PadPainter old) =>
      old.knob != knob || old.active != active || old.colors != colors;
}

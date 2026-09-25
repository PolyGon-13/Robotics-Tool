import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:robotics_tool/widgets/teleop_pad.dart';

void main() {
  late List<(double, double)> sent;

  bool record(double l, double a) {
    sent.add((l, a));
    return true;
  }

  Future<void> pumpPad(WidgetTester tester) async {
    tester.view.physicalSize = const Size(412, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: TeleopPad(send: record))),
    ));
  }

  Finder pad() => find.byWidgetPredicate(
      (w) => w is CustomPaint && w.size.width > 100 && w.size.width == w.size.height);

  setUp(() => sent = []);

  testWidgets('nothing is sent until the stick is touched', (tester) async {
    await pumpPad(tester);
    await tester.pump(const Duration(seconds: 1));
    expect(sent, isEmpty);
  });

  testWidgets('pushing up drives forward, releasing stops', (tester) async {
    await pumpPad(tester);
    final center = tester.getCenter(pad());
    final g = await tester.startGesture(center);
    await g.moveBy(const Offset(0, -200)); // full forward
    await tester.pump(const Duration(milliseconds: 350));
    expect(sent, isNotEmpty);
    expect(sent.last.$1, closeTo(0.3, 1e-6), reason: 'default max linear speed');
    expect(sent.last.$2, closeTo(0, 1e-6));
    final whileHeld = sent.length;
    expect(whileHeld, greaterThanOrEqualTo(3), reason: 'repeats at ~10 Hz');

    await g.up();
    await tester.pump(const Duration(milliseconds: 400));
    final after = sent.sublist(whileHeld);
    expect(after, isNotEmpty);
    expect(after.every((c) => c == (0.0, 0.0)), isTrue, reason: 'only stops after release');
    expect(after.length, greaterThanOrEqualTo(3), reason: 'stop is repeated');

    final count = sent.length;
    await tester.pump(const Duration(seconds: 1));
    expect(sent.length, count, reason: 'no traffic when idle');
  });

  testWidgets('stick left turns left (positive angular z)', (tester) async {
    await pumpPad(tester);
    final g = await tester.startGesture(tester.getCenter(pad()));
    await g.moveBy(const Offset(-200, 0));
    await tester.pump(const Duration(milliseconds: 150));
    expect(sent.last.$2, greaterThan(0));
    await g.up();
    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets('leaving the screen while driving sends stop', (tester) async {
    await pumpPad(tester);
    final g = await tester.startGesture(tester.getCenter(pad()));
    await g.moveBy(const Offset(0, -100));
    await tester.pump(const Duration(milliseconds: 150));
    sent.clear();
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pump(const Duration(milliseconds: 400));
    expect(sent, isNotEmpty);
    expect(sent.every((c) => c == (0.0, 0.0)), isTrue);
  });

  testWidgets('STOP button sends zero', (tester) async {
    await pumpPad(tester);
    await tester.tap(find.text('STOP'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(sent, isNotEmpty);
    expect(sent.every((c) => c == (0.0, 0.0)), isTrue);
  });

  test('sendStopReliably keeps retrying while sending fails', () async {
    var failuresLeft = 4;
    var delivered = 0;
    bool flaky(double l, double a) {
      if (failuresLeft > 0) {
        failuresLeft--;
        return false;
      }
      delivered++;
      return true;
    }
    final t = sendStopReliably(flaky);
    await Future.delayed(const Duration(milliseconds: 1200));
    expect(delivered, 3, reason: 'three stops once the link is back');
    expect(t.isActive, isFalse);
  });
}

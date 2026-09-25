import 'package:flutter_test/flutter_test.dart';
import 'package:robotics_tool/utils/rate_meter.dart';

void main() {
  final t0 = DateTime(2026, 1, 1, 12);
  DateTime at(double s) => t0.add(Duration(microseconds: (s * 1e6).round()));

  void feed(RateMeter m, double hz, double from, double to) {
    for (var t = from; t <= to + 1e-9; t += 1 / hz) {
      m.tick(at(t));
    }
  }

  test('no data yet', () {
    final m = RateMeter();
    expect(m.hasData, isFalse);
    expect(m.rate(at(0)), 0);
    expect(m.isStale(at(10)), isFalse, reason: 'never received is not "stale"');
  });

  test('steady 10 Hz', () {
    final m = RateMeter();
    feed(m, 10, 0, 5);
    expect(m.rate(at(5.05)), closeTo(10, 0.01));
    expect(m.count, 51);
    expect(m.isStale(at(5.05)), isFalse);
  });

  test('rate follows a slowdown instead of the session average', () {
    final m = RateMeter();
    feed(m, 20, 0, 10);
    feed(m, 2, 10.5, 16);
    expect(m.rate(at(16.1)), closeTo(2, 0.01));
  });

  test('goes stale after several missed periods, then recovers', () {
    final m = RateMeter();
    feed(m, 10, 0, 2);
    // 5 periods at 10 Hz = 0.5 s, but never sooner than minStaleAfter (2 s)
    expect(m.isStale(at(3.5)), isFalse);
    expect(m.isStale(at(4.2)), isTrue);
    expect(m.rate(at(4.2)), 0);
    m.tick(at(4.3));
    expect(m.isStale(at(4.35)), isFalse);
  });

  test('slow topics get a longer stale threshold', () {
    final m = RateMeter();
    feed(m, 1, 0, 3); // 1 Hz → 5 s threshold
    expect(m.isStale(at(6)), isFalse);
    expect(m.isStale(at(8.5)), isTrue);
  });

  test('reset clears everything', () {
    final m = RateMeter();
    feed(m, 10, 0, 1);
    m.reset();
    expect(m.hasData, isFalse);
    expect(m.count, 0);
  });
}

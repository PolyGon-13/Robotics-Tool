import 'package:flutter_test/flutter_test.dart';
import 'package:robotics_tool/utils/time_series.dart';

void main() {
  group('TimeSeries', () {
    test('drops samples older than maxAge', () {
      final ts = TimeSeries(maxAge: 10);
      for (var t = 0.0; t <= 20; t += 1) {
        ts.add(t, t);
      }
      expect(ts.samples.first.t, 10);
      expect(ts.samples.last.v, 20);
    });

    test('ignores non-finite values', () {
      final ts = TimeSeries()
        ..add(double.nan, 0)
        ..add(double.infinity, 1)
        ..add(2, 2);
      expect(ts.samples.length, 1);
    });

    test('range respects the since cutoff', () {
      final ts = TimeSeries()
        ..add(100, 0)
        ..add(1, 5)
        ..add(3, 6);
      expect(ts.range(), (1.0, 100.0));
      expect(ts.range(since: 4), (1.0, 3.0));
      expect(TimeSeries().range(), isNull);
    });
  });

  group('NiceScale', () {
    test('covers the data with round steps', () {
      final s = NiceScale.of(0.13, 0.87);
      expect(s.min, lessThanOrEqualTo(0.13));
      expect(s.max, greaterThanOrEqualTo(0.87));
      expect([0.1, 0.2, 0.25, 0.5], contains(s.step));
    });

    test('minSpan keeps noise from filling the chart', () {
      // 12.30 V ± 3 mV should not be drawn as a full-height swing
      final s = NiceScale.of(12.297, 12.303, minSpan: 0.5);
      expect(s.max - s.min, greaterThanOrEqualTo(0.5));
    });

    test('flat and inverted input', () {
      final flat = NiceScale.of(5, 5);
      expect(flat.max, greaterThan(flat.min));
      final zero = NiceScale.of(0, 0);
      expect(zero.max, greaterThan(zero.min));
      final inv = NiceScale.of(3, 1);
      expect(inv.min, lessThanOrEqualTo(1));
    });

    test('ticks are evenly spaced and bounded', () {
      final s = NiceScale.of(-1.2, 3.7);
      final t = s.ticks;
      expect(t.first, s.min);
      expect(t.last, closeTo(s.max, 1e-9));
      expect(t.length, lessThanOrEqualTo(8));
    });
  });

  test('niceStep', () {
    expect(niceStep(0.7), 1);
    expect(niceStep(1.7), 2);
    expect(niceStep(2.3), 2.5);
    expect(niceStep(3.2), 5);
    expect(niceStep(0.032), closeTo(0.05, 1e-12));
  });

  group('fmtNum', () {
    test('keeps ~4 significant digits', () {
      expect(fmtNum(12.30645), '12.31');
      expect(fmtNum(0.123456), '0.1235');
      expect(fmtNum(1234.5), '1235');
      expect(fmtNum(2.0), '2');
      expect(fmtNum(0), '0');
      expect(fmtNum(-0.00001), '-1.00e-5');
    });
    test('special values', () {
      expect(fmtNum(double.nan), 'NaN');
      expect(fmtNum(double.infinity), '∞');
    });
  });

  test('fmtTick uses the precision of the step', () {
    expect(fmtTick(12.25, 0.25), '12.25');
    expect(fmtTick(12.5, 0.5), '12.5');
    expect(fmtTick(10, 5), '10');
    expect(fmtTick(2.5, 2.5), '2.5');
    expect(fmtTick(0.2, 0.2), '0.2');
    expect(fmtTick(1e-12, 0.1), '0');
  });
}

import 'dart:math' as math;

/// A sample in a time series: [t] is seconds on a monotonic clock.
class Sample {
  final double t;
  final double v;
  const Sample(this.t, this.v);
}

/// Seconds since app start on a monotonic clock, shared by all series so
/// charts opened side by side line up.
final Stopwatch _clock = Stopwatch()..start();
double nowSeconds() => _clock.elapsedMicroseconds / 1e6;

/// Rolling buffer that keeps only the last [maxAge] seconds of samples.
class TimeSeries {
  TimeSeries({this.maxAge = 30});

  final double maxAge;
  final List<Sample> samples = [];

  bool get isEmpty => samples.isEmpty;
  Sample? get last => samples.isEmpty ? null : samples.last;

  void add(double v, [double? t]) {
    if (!v.isFinite) return;
    t ??= nowSeconds();
    samples.add(Sample(t, v));
    final cutoff = t - maxAge;
    var drop = 0;
    while (drop < samples.length && samples[drop].t < cutoff) {
      drop++;
    }
    // Remove in chunks: shifting the whole list on every sample is O(n)
    if (drop > 32 || drop > samples.length ~/ 4) samples.removeRange(0, drop);
  }

  void clear() => samples.clear();

  /// (min, max) of values at or after [since]; null when empty.
  (double, double)? range({double since = double.negativeInfinity}) {
    double lo = double.infinity, hi = double.negativeInfinity;
    for (final s in samples) {
      if (s.t < since) continue;
      if (s.v < lo) lo = s.v;
      if (s.v > hi) hi = s.v;
    }
    return lo.isFinite ? (lo, hi) : null;
  }
}

/// "Nice" axis ticks (steps of 1, 2, 2.5 or 5 × 10^k) covering [lo, hi].
class NiceScale {
  final double min;
  final double max;
  final double step;

  const NiceScale(this.min, this.max, this.step);

  factory NiceScale.of(double lo, double hi, {int maxTicks = 5, double minSpan = 0}) {
    if (!lo.isFinite || !hi.isFinite) return const NiceScale(0, 1, 0.25);
    if (hi < lo) (lo, hi) = (hi, lo);
    var span = hi - lo;
    if (span < minSpan) {
      final mid = (lo + hi) / 2;
      lo = mid - minSpan / 2;
      hi = mid + minSpan / 2;
      span = minSpan;
    }
    if (span == 0) {
      final pad = lo == 0 ? 1.0 : lo.abs() * 0.1;
      lo -= pad;
      hi += pad;
      span = hi - lo;
    }
    final step = niceStep(span / math.max(1, maxTicks - 1));
    final nMin = (lo / step).floorToDouble() * step;
    final nMax = (hi / step).ceilToDouble() * step;
    return NiceScale(nMin, nMax, step);
  }

  List<double> get ticks {
    final out = <double>[];
    final n = ((max - min) / step).round();
    for (var i = 0; i <= n; i++) {
      out.add(min + i * step);
    }
    return out;
  }
}

double niceStep(double raw) {
  if (raw <= 0 || !raw.isFinite) return 1;
  final exp = math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
  final f = raw / exp;
  final nice = f <= 1 ? 1 : f <= 2 ? 2 : f <= 2.5 ? 2.5 : f <= 5 ? 5 : 10;
  return nice * exp;
}

/// Compact number formatting for readouts: 4 significant digits, no
/// scientific notation for everyday robot magnitudes.
String fmtNum(double v, {int sig = 4}) {
  if (v.isNaN) return 'NaN';
  if (v.isInfinite) return v > 0 ? '∞' : '-∞';
  final a = v.abs();
  if (a == 0) return '0';
  if (a >= 1e6 || a < 1e-4) return v.toStringAsExponential(2);
  final intDigits = a >= 1 ? (math.log(a) / math.ln10).floor() + 1 : 0;
  final decimals = (sig - intDigits).clamp(0, 6);
  var s = v.toStringAsFixed(decimals);
  if (s.contains('.')) {
    s = s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  }
  return s == '-0' ? '0' : s;
}

/// Fixed-decimals formatting that never prints "-0.0".
String fmtFixed(double v, int digits) {
  final s = v.toStringAsFixed(digits);
  return RegExp(r'^-0(\.0*)?$').hasMatch(s) ? s.substring(1) : s;
}

/// Tick label for an axis whose ticks are [step] apart.
String fmtTick(double v, double step) {
  if (v.abs() < step * 1e-6) return '0';
  final decimals = step >= 1 ? 0 : (-(math.log(step) / math.ln10).floor()).clamp(0, 6);
  final scaled = step / math.pow(10, -decimals);
  final stepHasHalf = (scaled - scaled.round()).abs() > 1e-6; // e.g. 2.5, 0.25
  return v.toStringAsFixed(decimals + (stepHasHalf ? 1 : 0));
}

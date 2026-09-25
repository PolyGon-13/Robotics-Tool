/// Message-rate and freshness tracking for one topic.
///
/// The rate is computed over a sliding time window, so it drops when a
/// publisher slows down or stops instead of averaging over the whole session.
class RateMeter {
  RateMeter({
    this.window = const Duration(seconds: 3),
    this.minStaleAfter = const Duration(seconds: 2),
    this.stalePeriods = 5,
  });

  /// Time span the rate is averaged over.
  final Duration window;

  /// Data is never reported stale sooner than this.
  final Duration minStaleAfter;

  /// Data is stale after this many missed periods at the recent rate.
  final int stalePeriods;

  final List<DateTime> _stamps = [];
  DateTime? _last;
  int _count = 0;
  double _lastRate = 0;

  int get count => _count;
  DateTime? get lastMessageAt => _last;
  bool get hasData => _last != null;

  void tick([DateTime? now]) {
    now ??= DateTime.now();
    _stamps.add(now);
    _last = now;
    _count++;
    _prune(now);
    _lastRate = _computeRate();
  }

  void _prune(DateTime now) {
    final cutoff = now.subtract(window);
    while (_stamps.isNotEmpty && _stamps.first.isBefore(cutoff)) {
      _stamps.removeAt(0);
    }
  }

  double _computeRate() {
    if (_stamps.length < 2) return 0;
    final span = _stamps.last.difference(_stamps.first).inMicroseconds / 1e6;
    return span > 0 ? (_stamps.length - 1) / span : 0;
  }

  /// Messages per second over the recent window; 0 once the topic goes quiet.
  double rate([DateTime? now]) {
    now ??= DateTime.now();
    if (isStale(now)) return 0;
    return _lastRate;
  }

  Duration? sinceLast([DateTime? now]) =>
      _last == null ? null : (now ?? DateTime.now()).difference(_last!);

  Duration get staleAfter {
    if (_lastRate <= 0) return minStaleAfter;
    final expected = Duration(
        microseconds: (stalePeriods * 1e6 / _lastRate).round());
    return expected > minStaleAfter ? expected : minStaleAfter;
  }

  /// True when messages were flowing but none arrived for [staleAfter].
  bool isStale([DateTime? now]) {
    final since = sinceLast(now);
    return since != null && since > staleAfter;
  }

  void reset() {
    _stamps.clear();
    _last = null;
    _count = 0;
    _lastRate = 0;
  }
}

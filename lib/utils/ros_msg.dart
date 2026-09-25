import 'dart:math' as math;

/// Tolerant accessors for rosbridge JSON messages.
///
/// rosbridge encodes `inf`/`NaN` floats as `null`, integers may arrive where
/// floats are expected (and vice versa), and optional fields can be missing.
/// These helpers never throw on unexpected shapes.

/// Converts a JSON value to a double. `null`, non-numbers and unparsable
/// strings become `null`; "inf"/"nan" strings become the matching double.
double? asDouble(dynamic v) {
  if (v is num) return v.toDouble();
  if (v is String) {
    final s = v.trim().toLowerCase();
    if (s == 'nan') return double.nan;
    if (s == 'inf' || s == '+inf' || s == 'infinity') return double.infinity;
    if (s == '-inf' || s == '-infinity') return double.negativeInfinity;
    return double.tryParse(s);
  }
  if (v is bool) return v ? 1 : 0;
  return null;
}

int? asInt(dynamic v) {
  if (v is int) return v;
  if (v is num && v.isFinite) return v.round();
  if (v is String) return int.tryParse(v.trim());
  return null;
}

Map<String, dynamic> asMap(dynamic v) {
  if (v is Map<String, dynamic>) return v;
  if (v is Map) return v.map((k, val) => MapEntry(k.toString(), val));
  return const {};
}

List<dynamic> asList(dynamic v) => v is List ? v : const [];

/// Reads a dotted path such as `pose.pose.position.x`.
dynamic field(dynamic msg, String path) {
  dynamic cur = msg;
  for (final key in path.split('.')) {
    if (cur is Map) {
      cur = cur[key];
    } else if (cur is List) {
      final i = int.tryParse(key);
      cur = (i != null && i >= 0 && i < cur.length) ? cur[i] : null;
    } else {
      return null;
    }
  }
  return cur;
}

/// Finite double at [path], or [fallback].
double numAt(dynamic msg, String path, [double fallback = 0]) {
  final v = asDouble(field(msg, path));
  return (v != null && v.isFinite) ? v : fallback;
}

/// List of doubles; entries that are not finite numbers become `null`.
List<double?> doubleList(dynamic v) => asList(v).map((e) {
      final d = asDouble(e);
      return (d != null && d.isFinite) ? d : null;
    }).toList();

/// Normalizes `pkg/Type` and `pkg/msg/Type` to `pkg/Type`.
String baseType(String type) => type.replaceFirst('/msg/', '/');

// ─── Geometry ────────────────────────────────────────────────────────────────

class Euler {
  final double roll, pitch, yaw; // radians
  const Euler(this.roll, this.pitch, this.yaw);
}

/// Quaternion (x, y, z, w) to roll/pitch/yaw (ZYX convention, as in tf2).
Euler quatToEuler(double x, double y, double z, double w) {
  final n = math.sqrt(x * x + y * y + z * z + w * w);
  if (n == 0) return const Euler(0, 0, 0);
  x /= n; y /= n; z /= n; w /= n;
  final roll = math.atan2(2 * (w * x + y * z), 1 - 2 * (x * x + y * y));
  final sinp = (2 * (w * y - z * x)).clamp(-1.0, 1.0);
  final pitch = math.asin(sinp);
  final yaw = math.atan2(2 * (w * z + x * y), 1 - 2 * (y * y + z * z));
  return Euler(roll, pitch, yaw);
}

Euler quatMsgToEuler(dynamic q) => quatToEuler(
      numAt(q, 'x'), numAt(q, 'y'), numAt(q, 'z'), numAt(q, 'w', 1),
    );

double radToDeg(double r) => r * 180 / math.pi;

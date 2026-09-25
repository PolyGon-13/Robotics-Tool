import 'ros_msg.dart';

/// Builds a default-valued JSON message from rosapi `message_details`
/// typedefs, e.g. geometry_msgs/Twist → {linear: {x: 0.0, ...}, ...}.
///
/// Each typedef has parallel `fieldnames`, `fieldtypes` and `fieldarraylen`
/// lists; arraylen -1 = single value, 0 = variable-length array (empty),
/// n > 0 = fixed-length array.
Map<String, dynamic>? templateFromTypedefs(String type, List<dynamic> typedefs) {
  final defs = <String, Map<String, dynamic>>{
    for (final d in typedefs)
      if (d is Map && d['type'] != null) baseType(d['type'].toString()): asMap(d),
  };

  dynamic build(String t, int depth) {
    final prim = primitiveDefault(t);
    if (prim != null) return prim;
    final def = defs[baseType(t)];
    if (def == null || depth > 12) return <String, dynamic>{};
    final names = asList(def['fieldnames']);
    final types = asList(def['fieldtypes']);
    final lens = asList(def['fieldarraylen']);
    final out = <String, dynamic>{};
    for (var i = 0; i < names.length && i < types.length; i++) {
      final ft = types[i].toString();
      final len = i < lens.length ? (asInt(lens[i]) ?? -1) : -1;
      out[names[i].toString()] = len < 0
          ? build(ft, depth + 1)
          : List.generate(len, (_) => build(ft, depth + 1));
    }
    // An all-zero quaternion is invalid; default to "no rotation"
    if (baseType(t) == 'geometry_msgs/Quaternion' && out.containsKey('w')) {
      out['w'] = 1.0;
    }
    return out;
  }

  if (!defs.containsKey(baseType(type))) return null;
  final result = build(type, 0);
  return result is Map<String, dynamic> ? result : null;
}

/// Default value for a ROS primitive type name, or null if not primitive.
Object? primitiveDefault(String t) {
  switch (t) {
    case 'bool':
      return false;
    case 'string':
    case 'wstring':
      return '';
    case 'float32':
    case 'float64':
    case 'double':
    case 'float':
      return 0.0;
    case 'byte':
    case 'char':
    case 'octet':
    case 'int8':
    case 'uint8':
    case 'int16':
    case 'uint16':
    case 'int32':
    case 'uint32':
    case 'int64':
    case 'uint64':
      return 0;
  }
  if (t.startsWith('string<') || t.startsWith('wstring<')) return '';
  return null;
}

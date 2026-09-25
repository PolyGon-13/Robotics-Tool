/// A rosbridge endpoint the user typed or picked from history.
class HostAddress {
  final String host;
  final int port;

  const HostAddress(this.host, this.port);

  static const defaultPort = 9090;

  String get label => '$host:$port';

  @override
  bool operator ==(Object other) =>
      other is HostAddress && other.host == host && other.port == port;

  @override
  int get hashCode => Object.hash(host, port);

  /// Parses "192.168.0.5", "robot.local:9091" or a pasted
  /// "ws://192.168.0.5:9090/". [fallbackPort] is used when none is given.
  /// Returns null with [error] set when the input cannot be used.
  static HostAddress? tryParse(String input,
      {int fallbackPort = defaultPort, void Function(String error)? onError}) {
    var s = input.trim();
    if (s.isEmpty) {
      onError?.call('Enter the IP address of the PC running rosbridge');
      return null;
    }
    s = s.replaceFirst(RegExp(r'^(wss?|https?)://', caseSensitive: false), '');
    s = s.replaceFirst(RegExp(r'/.*$'), '');
    var port = fallbackPort;
    final colon = s.lastIndexOf(':');
    if (colon > 0 && !s.contains(']')) {
      final p = int.tryParse(s.substring(colon + 1));
      if (p == null) {
        onError?.call('Port must be a number');
        return null;
      }
      port = p;
      s = s.substring(0, colon);
    }
    if (port < 1 || port > 65535) {
      onError?.call('Port must be between 1 and 65535');
      return null;
    }
    if (!RegExp(r'^[A-Za-z0-9.\-_]+$').hasMatch(s)) {
      onError?.call('"$s" is not a valid IP address or host name');
      return null;
    }
    // Looks like an IPv4 address: every part must be 0-255
    if (RegExp(r'^[0-9.]+$').hasMatch(s)) {
      final parts = s.split('.');
      if (parts.length != 4 ||
          parts.any((p) => p.isEmpty || int.parse(p) > 255)) {
        onError?.call('"$s" is not a valid IPv4 address (e.g. 192.168.0.10)');
        return null;
      }
    }
    return HostAddress(s, port);
  }
}

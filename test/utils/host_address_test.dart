import 'package:flutter_test/flutter_test.dart';
import 'package:robotics_tool/utils/host_address.dart';

void main() {
  HostAddress? parse(String s, {int port = 9090}) =>
      HostAddress.tryParse(s, fallbackPort: port);

  String? errorFor(String s) {
    String? err;
    HostAddress.tryParse(s, onError: (e) => err = e);
    return err;
  }

  test('plain IPv4 uses the fallback port', () {
    expect(parse('192.168.0.5'), const HostAddress('192.168.0.5', 9090));
    expect(parse(' 10.0.0.1 ', port: 9091), const HostAddress('10.0.0.1', 9091));
  });

  test('host:port and host names', () {
    expect(parse('robot.local:9091'), const HostAddress('robot.local', 9091));
    expect(parse('localhost'), const HostAddress('localhost', 9090));
  });

  test('pasted websocket URLs', () {
    expect(parse('ws://192.168.0.5:9090'), const HostAddress('192.168.0.5', 9090));
    expect(parse('WS://robot:8080/'), const HostAddress('robot', 8080));
  });

  test('rejects bad input with a helpful message', () {
    expect(errorFor(''), contains('IP address'));
    expect(errorFor('192.168.0'), contains('IPv4'));
    expect(errorFor('192.168.0.300'), contains('IPv4'));
    expect(errorFor('1.2.3.4:abc'), contains('number'));
    expect(errorFor('1.2.3.4:70000'), contains('65535'));
    expect(errorFor('my robot'), contains('not a valid'));
  });

  test('label', () {
    expect(const HostAddress('10.0.0.2', 9090).label, '10.0.0.2:9090');
  });
}

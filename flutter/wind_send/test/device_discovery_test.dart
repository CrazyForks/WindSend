import 'package:flutter_test/flutter_test.dart';
import 'package:wind_send/device.dart';

void main() {
  group('DeviceEndpoint', () {
    test('normalizes whitespace and bracketed IPv6 addresses', () {
      final ipv4 = DeviceEndpoint(host: ' 192.168.0.42 ', port: 6779);
      final ipv6 = DeviceEndpoint(host: ' [fd00::42] ', port: 6780);

      expect(ipv4.host, '192.168.0.42');
      expect(ipv4.authority, '192.168.0.42:6779');
      expect(ipv6.host, 'fd00::42');
      expect(ipv6.authority, '[fd00::42]:6780');
    });

    test('rejects endpoints that cannot be connected to', () {
      expect(() => DeviceEndpoint(host: '  '), throwsArgumentError);
      expect(
        () => DeviceEndpoint(host: '192.168.0.42', port: 0),
        throwsRangeError,
      );
      expect(
        () => DeviceEndpoint(host: '192.168.0.42', port: 65536),
        throwsRangeError,
      );
    });
  });
}

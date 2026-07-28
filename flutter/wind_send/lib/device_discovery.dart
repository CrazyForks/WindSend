import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'device.dart';
import 'protocol/protocol.dart';
import 'db/shared_preferences/cnf.dart' show globalLocalDeviceName;

/// A validated network endpoint used for both directed pairing and LAN scans.
final class DeviceEndpoint {
  final String host;
  final int port;

  factory DeviceEndpoint({
    required String host,
    int port = Device.defaultPort,
  }) {
    var normalizedHost = host.trim();
    if (normalizedHost.startsWith('[') && normalizedHost.endsWith(']')) {
      normalizedHost = normalizedHost.substring(1, normalizedHost.length - 1);
    }
    if (normalizedHost.isEmpty) {
      throw ArgumentError.value(host, 'host', 'must not be empty');
    }
    if (port < 1 || port > 65535) {
      throw RangeError.range(port, 1, 65535, 'port');
    }
    return DeviceEndpoint._(normalizedHost, port);
  }

  const DeviceEndpoint._(this.host, this.port);

  String get authority => host.contains(':') ? '[$host]:$port' : '$host:$port';
}

/// Discovery failures are typed so callers can present actionable recovery
/// instead of leaking socket and protocol implementation details to users.
sealed class DeviceDiscoveryFailure implements Exception {
  const DeviceDiscoveryFailure();
}

final class NoLocalNetworkFailure extends DeviceDiscoveryFailure {
  const NoLocalNetworkFailure();

  @override
  String toString() => 'No private local network interface is available';
}

final class NoPairableDeviceFailure extends DeviceDiscoveryFailure {
  const NoPairableDeviceFailure();

  @override
  String toString() => 'No pairable WindSend device was found';
}

final class DevicePairingConnectionFailure extends DeviceDiscoveryFailure {
  final DeviceEndpoint endpoint;
  final Object cause;

  const DevicePairingConnectionFailure(this.endpoint, this.cause);

  @override
  String toString() => 'Could not connect to ${endpoint.authority}: $cause';
}

final class DevicePairingRejectedFailure extends DeviceDiscoveryFailure {
  final DeviceEndpoint endpoint;
  final int responseCode;
  final String? responseMessage;

  const DevicePairingRejectedFailure(
    this.endpoint,
    this.responseCode,
    this.responseMessage,
  );

  @override
  String toString() =>
      'Pairing was rejected by ${endpoint.authority} ($responseCode)';
}

final class DevicePairingProtocolFailure extends DeviceDiscoveryFailure {
  final DeviceEndpoint endpoint;
  final Object cause;

  const DevicePairingProtocolFailure(this.endpoint, this.cause);

  @override
  String toString() =>
      'Invalid pairing response from ${endpoint.authority}: $cause';
}

abstract interface class DevicePairingService {
  Future<Device> discover();

  Future<Device> pairAt(DeviceEndpoint endpoint);
}

/// Production pairing service. Keeping the UI behind an interface makes every
/// loading, success, and recovery path testable without opening real sockets.
final class LanDevicePairingService implements DevicePairingService {
  const LanDevicePairingService();

  @override
  Future<Device> discover() => DeviceDiscoveryUtils.search();

  @override
  Future<Device> pairAt(DeviceEndpoint endpoint) =>
      DeviceDiscoveryUtils.pairAt(endpoint);
}

/// Extension for device discovery and network scanning functionality
extension DeviceDiscovery on Device {
  /// Automatically scan and update ip
  Future<String?> findServer() async {
    final state = refState();
    state.findingServerRunning ??= _findServerInner();
    final found = await state.findingServerRunning!;
    state.findingServerRunning = null;
    if (found != null) {
      refState().tryDirectConnectErr = Future.value(null);
    }
    return found;
  }

  Future<String?> _findServerInner() async {
    final myIps = await DeviceDiscoveryUtils.getLocalIps();
    if (myIps.isEmpty) {
      return null;
    }

    String result = await pingDeviceLoop(myIps);
    if (result == '') {
      return null;
    }
    iP = result;
    return result;
  }

  Future<String> pingDeviceLoop(List<String> myIps) async {
    final rangeNum = myIps.length * DeviceDiscoveryUtils._hostsPerSubnet;
    StreamSubscription<String>? subscription;
    final msgController = StreamController<String>();
    // add a listener immediately
    final ipFuture = msgController.stream
        .take(rangeNum)
        .firstWhere((element) => element != '', orElse: () => '')
        .whenComplete(() => subscription?.cancel());

    Stream<String> tryStream = DeviceDiscoveryUtils._ipRanges(myIps);

    subscription = tryStream.listen((ip) {
      var device = Device.copy(this);
      device.iP = ip;
      _pingDevice2(msgController, device, timeout: const Duration(seconds: 3));
    });
    return ipFuture;
  }

  Future<void> _pingDevice2(
    StreamController<String> msgController,
    Device device, {
    Duration timeout = const Duration(seconds: 2),
  }) async {
    bool ok;
    try {
      await device.pingDevice(timeout: timeout);
      ok = true;
    } catch (e) {
      ok = false;
    }
    msgController.add(ok ? device.iP : '');
  }
}

/// Utility class for device discovery static methods
class DeviceDiscoveryUtils {
  DeviceDiscoveryUtils._();

  /// Number of host addresses probed per /24 subnet (i.e. .1 through .254).
  static const int _hostsPerSubnet = 254;

  /// Collect the local IPv4 addresses that plausibly belong to a physical LAN.
  ///
  /// Interface selection is based on address semantics rather than adapter
  /// names: adapter naming is localized and driver/OS-dependent (e.g. "WiFi",
  /// "WLAN", "Wi-Fi", "以太网"), so a name whitelist silently fails on any host
  /// whose adapter happens to be named differently. We instead keep RFC1918
  /// private IPv4 addresses, drop known virtual/VPN adapters, and return one
  /// representative address per /24 subnet so the caller can scan every LAN the
  /// host is attached to.
  static Future<List<String>> getLocalIps() async {
    final interfaces = await NetworkInterface.list(
      includeLoopback: false,
      includeLinkLocal: false,
      type: InternetAddressType.IPv4,
    );
    // Keyed by /24 prefix to avoid scanning the same subnet twice.
    final bySubnet = <String, String>{};
    for (final interface in interfaces) {
      if (_isVirtualInterface(interface.name)) {
        continue;
      }
      for (final addr in interface.addresses) {
        if (!_isPrivateIPv4(addr.address)) {
          continue;
        }
        final prefix = addr.address.substring(0, addr.address.lastIndexOf('.'));
        bySubnet.putIfAbsent(prefix, () => addr.address);
      }
    }
    return bySubnet.values.toList();
  }

  /// Whether [ip] falls in an RFC1918 private range, the address space used by
  /// home/office LANs that WindSend devices live on.
  static bool _isPrivateIPv4(String ip) {
    final parts = ip.split('.');
    if (parts.length != 4) {
      return false;
    }
    final a = int.tryParse(parts[0]);
    final b = int.tryParse(parts[1]);
    if (a == null || b == null) {
      return false;
    }
    return a == 10 || // 10.0.0.0/8
        (a == 172 && b >= 16 && b <= 31) || // 172.16.0.0/12
        (a == 192 && b == 168); // 192.168.0.0/16
  }

  /// Whether [name] denotes a virtual/VPN adapter that should never be scanned,
  /// even when it carries a private address (e.g. WSL/Hyper-V vEthernet).
  static bool _isVirtualInterface(String name) {
    final n = name.toLowerCase();
    const virtualMarkers = [
      'virtual',
      'vethernet',
      'vmware',
      'vbox',
      'hyper-v',
      'docker',
      'wsl',
      'loopback',
    ];
    return virtualMarkers.any(n.contains);
  }

  /// For every candidate subnet, scan nearby IPs first (±15 from the host
  /// address), then the rest. Nearby devices are more likely to be the target.
  static Stream<String> _ipRanges(List<String> myIps) async* {
    // Probe the ±15 neighbourhood of every subnet up front...
    for (final myIp in myIps) {
      final prefix = myIp.substring(0, myIp.lastIndexOf('.'));
      final suffix = int.parse(myIp.substring(myIp.lastIndexOf('.') + 1));
      for (var i = max(suffix - 15, 1); i <= min(suffix + 15, 254); i++) {
        yield '$prefix.$i';
      }
    }
    // ...then give nearby IPs time to respond before scanning the remainder.
    await Future.delayed(const Duration(milliseconds: 500));
    for (final myIp in myIps) {
      final prefix = myIp.substring(0, myIp.lastIndexOf('.'));
      final suffix = int.parse(myIp.substring(myIp.lastIndexOf('.') + 1));
      final mainStart = max(suffix - 15, 1);
      final mainEnd = min(suffix + 15, 254);
      for (var i = 1; i < mainStart; i++) {
        yield '$prefix.$i';
      }
      for (var i = mainEnd + 1; i < 255; i++) {
        yield '$prefix.$i';
      }
    }
  }

  static Future<Device> _matchDeviceLoop(
    StreamController<Device> msgController,
    List<String> myIps,
  ) async {
    final rangeNum = myIps.length * _hostsPerSubnet;
    StreamSubscription<String>? subscription;

    // add a listener immediately
    var resultFuture = msgController.stream
        .take(rangeNum)
        .firstWhere(
          (element) => element.secretKey != '',
          orElse: () => throw const NoPairableDeviceFailure(),
        )
        .whenComplete(() => subscription?.cancel());

    Stream<String> tryStream = _ipRanges(myIps);
    subscription = tryStream.listen((ip) {
      _matchDevice(msgController, ip, timeout: const Duration(seconds: 3));
    });

    return resultFuture;
  }

  static Future<void> _matchDevice(
    StreamController<Device> msgController,
    String ip, {
    Duration timeout = const Duration(seconds: 2),
  }) async {
    try {
      final device = await pairAt(DeviceEndpoint(host: ip), timeout: timeout);
      msgController.add(device);
    } catch (_) {
      msgController.add(Device(targetDeviceName: '', iP: ip, secretKey: ''));
    }
  }

  /// Pair with one explicitly selected endpoint and return all connection
  /// credentials needed to persist a usable [Device].
  static Future<Device> pairAt(
    DeviceEndpoint endpoint, {
    Duration timeout = const Duration(seconds: 3),
  }) async {
    SecureSocket? conn;
    try {
      try {
        conn = await SecureSocket.connect(
          endpoint.host,
          endpoint.port,
          // Quick Pair is the trust-bootstrap step: its response supplies the
          // CA that authenticates every subsequent connection.
          onBadCertificate: (_) => true,
          timeout: timeout,
        );
      } on HandshakeException catch (error) {
        throw DevicePairingProtocolFailure(endpoint, error);
      } catch (error) {
        throw DevicePairingConnectionFailure(endpoint, error);
      }

      final headInfo = HeadInfo(
        globalLocalDeviceName,
        DeviceAction.matchDevice,
        'no need',
        '',
      );

      RespHead respHead;
      try {
        await headInfo.writeToConn(conn);
        await conn.flush();
        (respHead, _) = await RespHead.readHeadAndBodyFromConn(
          conn,
          timeout: timeout,
        );
      } on TimeoutException catch (error) {
        throw DevicePairingConnectionFailure(endpoint, error);
      } on SocketException catch (error) {
        throw DevicePairingConnectionFailure(endpoint, error);
      } on DeviceDiscoveryFailure {
        rethrow;
      } catch (error) {
        throw DevicePairingProtocolFailure(endpoint, error);
      }

      if (respHead.code != Device.respOkCode) {
        throw DevicePairingRejectedFailure(
          endpoint,
          respHead.code,
          respHead.msg,
        );
      }
      if (respHead.msg == null) {
        throw DevicePairingProtocolFailure(
          endpoint,
          const FormatException('response message is missing'),
        );
      }

      try {
        final json = jsonDecode(respHead.msg!);
        if (json is! Map<String, dynamic>) {
          throw const FormatException('response message is not an object');
        }
        final resp = MatchActionResp.fromJson(json);
        if (resp.deviceName.trim().isEmpty ||
            resp.secretKeyHex.trim().isEmpty ||
            resp.caCertificate.trim().isEmpty) {
          throw const FormatException('response credentials are incomplete');
        }
        return Device(
          targetDeviceName: resp.deviceName.trim(),
          iP: endpoint.host,
          port: endpoint.port,
          secretKey: resp.secretKeyHex.trim(),
          trustedCertificate: resp.caCertificate,
        );
      } catch (error) {
        throw DevicePairingProtocolFailure(endpoint, error);
      }
    } finally {
      if (conn != null) {
        try {
          await conn.flush();
        } catch (_) {}
        try {
          await conn.close();
        } catch (_) {}
        conn.destroy();
      }
    }
  }

  /// Search for devices on the local network
  static Future<Device> search() async {
    final myIps = await getLocalIps();
    if (myIps.isEmpty) {
      throw const NoLocalNetworkFailure();
    }
    return await _matchDeviceLoop(StreamController<Device>(), myIps);
  }
}

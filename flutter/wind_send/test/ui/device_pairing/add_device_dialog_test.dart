import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wind_send/db/shared_preferences/cnf.dart';
import 'package:wind_send/device.dart';
import 'package:wind_send/language.dart';
import 'package:wind_send/ui/device_pairing/add_device_dialog.dart';

final class _FakePairingService implements DevicePairingService {
  final Device device;
  Object? failure;
  int discoveryCalls = 0;
  DeviceEndpoint? requestedEndpoint;

  _FakePairingService(this.device);

  @override
  Future<Device> discover() async {
    discoveryCalls++;
    if (failure case final failure?) {
      throw failure;
    }
    return Device.copy(device);
  }

  @override
  Future<Device> pairAt(DeviceEndpoint endpoint) async {
    requestedEndpoint = endpoint;
    if (failure case final failure?) {
      throw failure;
    }
    final result = Device.copy(device);
    result.iP = endpoint.host;
    result.port = endpoint.port;
    return result;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({
      'DeviceName': 'TEST-CLIENT',
      'FileSavePath': '.',
      'ImageSavePath': '.',
    });
    await LocalConfig.initInstance();
    final localization = FlutterLocalization.instance;
    await localization.ensureInitialized();
    localization.init(
      mapLocales: const [
        MapLocale('en', AppLocale.en, countryCode: 'US'),
        MapLocale('zh', AppLocale.zh, countryCode: 'CN'),
      ],
      initLanguageCode: 'en',
    );
  });

  testWidgets(
    'automatic discovery remains available and enables add on success',
    (tester) async {
      final service = _FakePairingService(_pairedDevice());
      await _pumpDialog(tester, service);

      await tester.tap(find.byKey(const Key('start-device-discovery')));
      await tester.pumpAndSettle();

      expect(service.discoveryCalls, 1);
      expect(find.text('DESKTOP-TEST'), findsOneWidget);
      expect(find.text('192.168.0.80:6779'), findsOneWidget);
      final submit = tester.widget<FilledButton>(
        find.byKey(const Key('add-device-submit')),
      );
      expect(submit.onPressed, isNotNull);
    },
  );

  testWidgets('automatic discovery preserves support for duplicate hostnames', (
    tester,
  ) async {
    final service = _FakePairingService(_pairedDevice());
    final devices = [
      Device(
        targetDeviceName: 'DESKTOP-TEST',
        iP: '192.168.0.70',
        secretKey: 'existing',
      ),
    ];
    await _pumpDialog(tester, service, devices: devices);

    await tester.tap(find.byKey(const Key('start-device-discovery')));
    await tester.pumpAndSettle();

    expect(find.text('DESKTOP-TEST (2)'), findsOneWidget);
    final submit = tester.widget<FilledButton>(
      find.byKey(const Key('add-device-submit')),
    );
    expect(submit.onPressed, isNotNull);
  });

  testWidgets(
    'direct pairing uses the entered address and keeps credentials hidden',
    (tester) async {
      final service = _FakePairingService(_pairedDevice());
      await _pumpDialog(tester, service);

      await tester.tap(find.text('By address'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('device-address-input')),
        '192.168.1.80',
      );
      await tester.enterText(
        find.byKey(const Key('device-port-input')),
        '6780',
      );
      await tester.tap(find.byKey(const Key('pair-device-at-address')));
      await tester.pumpAndSettle();

      expect(service.requestedEndpoint?.host, '192.168.1.80');
      expect(service.requestedEndpoint?.port, 6780);
      expect(find.text('192.168.1.80:6780'), findsOneWidget);
      expect(find.byKey(const Key('manual-secret-key')), findsNothing);
      expect(find.byKey(const Key('manual-certificate')), findsNothing);

      await tester.enterText(
        find.byKey(const Key('device-address-input')),
        '192.168.1.81',
      );
      await tester.pump();
      final submit = tester.widget<FilledButton>(
        find.byKey(const Key('add-device-submit')),
      );
      expect(submit.onPressed, isNull);
    },
  );

  testWidgets('manual mode retains every connection field', (tester) async {
    final service = _FakePairingService(_pairedDevice());
    await _pumpDialog(tester, service);

    await tester.tap(find.text('Manual'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('manual-device-name')), findsOneWidget);
    expect(find.byKey(const Key('device-address-input')), findsOneWidget);
    expect(find.byKey(const Key('device-port-input')), findsOneWidget);
    expect(find.byKey(const Key('manual-secret-key')), findsOneWidget);
    expect(find.byKey(const Key('manual-certificate')), findsOneWidget);
  });

  testWidgets('the three pairing modes fit a phone-width dialog', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final service = _FakePairingService(_pairedDevice());
    await _pumpDialog(tester, service);
    await tester.tap(find.text('Manual'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('manual-secret-key')), findsOneWidget);
  });

  testWidgets('manual mode can add a device without running discovery', (
    tester,
  ) async {
    final service = _FakePairingService(_pairedDevice());
    final devices = <Device>[];
    await _pumpDialog(tester, service, devices: devices);

    await tester.tap(find.text('Manual'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('manual-device-name')),
      'MANUAL-DEVICE',
    );
    await tester.enterText(
      find.byKey(const Key('device-address-input')),
      '192.168.2.80',
    );
    await tester.enterText(find.byKey(const Key('device-port-input')), '6781');
    await tester.enterText(
      find.byKey(const Key('manual-secret-key')),
      '0123456789abcdef',
    );
    await tester.enterText(
      find.byKey(const Key('manual-certificate')),
      'test certificate',
    );
    await tester.tap(find.byKey(const Key('add-device-submit')));
    await tester.pumpAndSettle();

    expect(service.discoveryCalls, 0);
    expect(service.requestedEndpoint, isNull);
    expect(devices, hasLength(1));
    expect(devices.single.targetDeviceName, 'MANUAL-DEVICE');
    expect(devices.single.iP, '192.168.2.80');
    expect(devices.single.port, 6781);
    expect(devices.single.secretKey, '0123456789abcdef');
    expect(devices.single.trustedCertificate, 'test certificate');
    expect(devices.single.autoSelect, isFalse);
  });

  testWidgets(
    'a rejected direct pairing explains that Quick Pair is required',
    (tester) async {
      final service = _FakePairingService(_pairedDevice());
      final endpoint = DeviceEndpoint(host: '192.168.1.80');
      service.failure = DevicePairingRejectedFailure(
        endpoint,
        Device.unauthorizedCode,
        'search not allowed',
      );
      await _pumpDialog(tester, service);

      await tester.tap(find.text('By address'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('device-address-input')),
        endpoint.host,
      );
      await tester.tap(find.byKey(const Key('pair-device-at-address')));
      await tester.pumpAndSettle();

      expect(
        find.text('Quick Pair is not enabled on the target device'),
        findsOneWidget,
      );
    },
  );
}

Device _pairedDevice() {
  return Device(
    targetDeviceName: 'DESKTOP-TEST',
    iP: '192.168.0.80',
    secretKey: '0123456789abcdef',
    trustedCertificate:
        '-----BEGIN CERTIFICATE-----\ntest\n-----END CERTIFICATE-----',
  );
}

Future<void> _pumpDialog(
  WidgetTester tester,
  DevicePairingService pairingService, {
  List<Device>? devices,
}) async {
  final localization = FlutterLocalization.instance;
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en', 'US'),
      supportedLocales: localization.supportedLocales,
      localizationsDelegates: localization.localizationsDelegates,
      home: Scaffold(
        body: AddNewDeviceDialog(
          devices: devices ?? <Device>[],
          pairingService: pairingService,
          onAddDevice: () {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

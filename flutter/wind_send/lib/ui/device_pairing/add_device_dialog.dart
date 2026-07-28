import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localization/flutter_localization.dart';

import '../../db/shared_preferences/cnf.dart';
import '../../device.dart';
import '../../language.dart';
import '../../utils/utils.dart';

enum _PairingMethod { automatic, direct, manual }

sealed class _PairingAttempt {
  const _PairingAttempt();
}

final class _PairingIdle extends _PairingAttempt {
  const _PairingIdle();
}

final class _PairingRunning extends _PairingAttempt {
  final DeviceEndpoint? endpoint;

  const _PairingRunning({this.endpoint});
}

final class _PairingReady extends _PairingAttempt {
  final Device device;

  const _PairingReady(this.device);
}

final class _PairingFailed extends _PairingAttempt {
  final Object failure;

  const _PairingFailed(this.failure);
}

class AddNewDeviceDialog extends StatefulWidget {
  final List<Device> devices;
  final void Function() onAddDevice;
  final DevicePairingService pairingService;

  const AddNewDeviceDialog({
    super.key,
    required this.devices,
    required this.onAddDevice,
    this.pairingService = const LanDevicePairingService(),
  });

  @override
  State<AddNewDeviceDialog> createState() => _AddNewDeviceDialogState();
}

class _AddNewDeviceDialogState extends State<AddNewDeviceDialog> {
  final _endpointFormKey = GlobalKey<FormState>();
  final _manualFormKey = GlobalKey<FormState>();
  final _hostFocusNode = FocusNode();
  final _deviceNameController = TextEditingController();
  final _hostController = TextEditingController();
  final _portController = TextEditingController(
    text: Device.defaultPort.toString(),
  );
  final _secretKeyController = TextEditingController();
  final _certificateController = TextEditingController();

  _PairingMethod _method = _PairingMethod.automatic;
  _PairingAttempt _attempt = const _PairingIdle();
  bool _autoSelect = true;
  bool _obscureSecretKey = true;

  bool get _isPairing => _attempt is _PairingRunning;

  Device? get _pairedDevice => switch (_attempt) {
    _PairingReady(:final device) => device,
    _ => null,
  };

  @override
  void dispose() {
    _hostFocusNode.dispose();
    _deviceNameController.dispose();
    _hostController.dispose();
    _portController.dispose();
    _secretKeyController.dispose();
    _certificateController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      title: Text(context.formatString(AppLocale.addDevice, [])),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildMethodSelector(context),
              const SizedBox(height: 16),
              if (_method != _PairingMethod.manual) ...[
                _buildQuickPairNotice(context),
                const SizedBox(height: 16),
              ],
              switch (_method) {
                _PairingMethod.automatic => _buildAutomaticMode(context),
                _PairingMethod.direct => _buildDirectMode(context),
                _PairingMethod.manual => _buildManualMode(context),
              },
              if (_method != _PairingMethod.manual) ...[
                const SizedBox(height: 12),
                _buildAttemptFeedback(context),
                if (_pairedDevice != null) ...[
                  const SizedBox(height: 4),
                  _buildAutoSelectToggle(context),
                ],
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.formatString(AppLocale.cancel, [])),
        ),
        FilledButton(
          key: const Key('add-device-submit'),
          onPressed: _canSubmit ? _submit : null,
          child: Text(context.formatString(AppLocale.addDevice, [])),
        ),
      ],
    );
  }

  bool get _canSubmit =>
      !_isPairing &&
      (_method == _PairingMethod.manual || _attempt is _PairingReady);

  Widget _buildMethodSelector(BuildContext context) {
    return SegmentedButton<_PairingMethod>(
      showSelectedIcon: false,
      segments: [
        ButtonSegment(
          value: _PairingMethod.automatic,
          label: Text(context.formatString(AppLocale.pairingAutomatic, [])),
        ),
        ButtonSegment(
          value: _PairingMethod.direct,
          label: Text(context.formatString(AppLocale.pairingDirect, [])),
        ),
        ButtonSegment(
          value: _PairingMethod.manual,
          label: Text(context.formatString(AppLocale.pairingManual, [])),
        ),
      ],
      selected: {_method},
      onSelectionChanged: _isPairing
          ? null
          : (selection) => _selectMethod(selection.single),
    );
  }

  Widget _buildQuickPairNotice(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.phonelink_lock_outlined,
            color: colors.onSecondaryContainer,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.formatString(AppLocale.quickPairInstruction, []),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colors.onSecondaryContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  context.formatString(AppLocale.quickPairOneShotHint, []),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.onSecondaryContainer,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAutomaticMode(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        key: const Key('start-device-discovery'),
        onPressed: _isPairing ? null : _discover,
        icon: const Icon(Icons.radar_outlined),
        label: Text(context.formatString(AppLocale.startDeviceDiscovery, [])),
      ),
    );
  }

  Widget _buildDirectMode(BuildContext context) {
    return Form(
      key: _endpointFormKey,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHostField(context),
          const SizedBox(height: 12),
          _buildPortField(context, onSubmitted: (_) => _pairDirectly()),
          const SizedBox(height: 12),
          FilledButton.icon(
            key: const Key('pair-device-at-address'),
            onPressed: _isPairing ? null : _pairDirectly,
            icon: const Icon(Icons.link),
            label: Text(
              context.formatString(AppLocale.connectAndFetchCredentials, []),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildManualMode(BuildContext context) {
    return Form(
      key: _manualFormKey,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            context.formatString(AppLocale.manualConfigurationHint, []),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          TextFormField(
            key: const Key('manual-device-name'),
            controller: _deviceNameController,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              labelText: context.formatString(AppLocale.deviceName, []),
            ),
            textInputAction: TextInputAction.next,
            validator: Device.deviceNameValidator(context, widget.devices),
          ),
          const SizedBox(height: 12),
          _buildHostField(context),
          const SizedBox(height: 12),
          _buildPortField(context),
          const SizedBox(height: 12),
          TextFormField(
            key: const Key('manual-secret-key'),
            controller: _secretKeyController,
            obscureText: _obscureSecretKey,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              labelText: context.formatString(AppLocale.secretKey, []),
              suffixIcon: IconButton(
                tooltip: context.formatString(
                  _obscureSecretKey
                      ? AppLocale.showSecretKey
                      : AppLocale.hideSecretKey,
                  [],
                ),
                onPressed: () {
                  setState(() => _obscureSecretKey = !_obscureSecretKey);
                },
                icon: Icon(
                  _obscureSecretKey
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
              ),
            ),
            textInputAction: TextInputAction.next,
            validator: Device.secretKeyValidator(context),
          ),
          const SizedBox(height: 12),
          TextFormField(
            key: const Key('manual-certificate'),
            controller: _certificateController,
            minLines: 3,
            maxLines: 6,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              labelText: context.formatString(AppLocale.certificate, []),
              alignLabelWithHint: true,
            ),
            validator: Device.certificateAuthorityValidator(context),
          ),
          const SizedBox(height: 4),
          _buildAutoSelectToggle(context),
        ],
      ),
    );
  }

  Widget _buildHostField(BuildContext context) {
    return TextFormField(
      key: const Key('device-address-input'),
      controller: _hostController,
      focusNode: _hostFocusNode,
      enabled: !_isPairing,
      decoration: InputDecoration(
        border: const OutlineInputBorder(),
        labelText: context.formatString(AppLocale.deviceAddress, []),
        hintText: context.formatString(AppLocale.deviceAddressHint, []),
      ),
      keyboardType: TextInputType.url,
      textInputAction: TextInputAction.next,
      onChanged: (_) => _invalidateDirectPairing(),
      validator: Device.ipValidator(context, false),
    );
  }

  Widget _buildPortField(
    BuildContext context, {
    ValueChanged<String>? onSubmitted,
  }) {
    return TextFormField(
      key: const Key('device-port-input'),
      controller: _portController,
      enabled: !_isPairing,
      decoration: InputDecoration(
        border: const OutlineInputBorder(),
        labelText: context.formatString(AppLocale.devicePort, []),
      ),
      keyboardType: TextInputType.number,
      textInputAction: onSubmitted == null
          ? TextInputAction.next
          : TextInputAction.done,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      onChanged: (_) => _invalidateDirectPairing(),
      onFieldSubmitted: onSubmitted,
      validator: Device.portValidator(context),
    );
  }

  Widget _buildAutoSelectToggle(BuildContext context) {
    return SwitchListTile.adaptive(
      contentPadding: EdgeInsets.zero,
      title: Text(context.formatString(AppLocale.autoSelectIp, [])),
      value: _autoSelect,
      onChanged: _isPairing
          ? null
          : (value) => setState(() => _autoSelect = value),
    );
  }

  Widget _buildAttemptFeedback(BuildContext context) {
    return switch (_attempt) {
      _PairingIdle() => const SizedBox.shrink(),
      _PairingRunning(:final endpoint) => _buildProgressCard(context, endpoint),
      _PairingReady(:final device) => _buildReadyCard(context, device),
      _PairingFailed(:final failure) => _buildFailureCard(context, failure),
    };
  }

  Widget _buildProgressCard(BuildContext context, DeviceEndpoint? endpoint) {
    final message = endpoint == null
        ? context.formatString(AppLocale.scanningDevices, [])
        : context.formatString(AppLocale.connectingToDevice, [
            endpoint.authority,
          ]);
    return _buildStatusCard(
      context,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      foregroundColor: Theme.of(context).colorScheme.onSurface,
      leading: const SizedBox.square(
        dimension: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
      child: Text(message),
    );
  }

  Widget _buildReadyCard(BuildContext context, Device device) {
    final colors = Theme.of(context).colorScheme;
    final authority = DeviceEndpoint(
      host: device.iP,
      port: device.port,
    ).authority;
    return _buildStatusCard(
      context,
      color: colors.primaryContainer,
      foregroundColor: colors.onPrimaryContainer,
      leading: const Icon(Icons.check_circle_outline),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            device.targetDeviceName,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: colors.onPrimaryContainer,
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(authority),
          const SizedBox(height: 2),
          Text(
            context.formatString(AppLocale.pairingCredentialsReady, []),
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: colors.onPrimaryContainer),
          ),
        ],
      ),
    );
  }

  Widget _buildFailureCard(BuildContext context, Object failure) {
    final colors = Theme.of(context).colorScheme;
    return _buildStatusCard(
      context,
      color: colors.errorContainer,
      foregroundColor: colors.onErrorContainer,
      leading: const Icon(Icons.error_outline),
      child: Text(_failureMessage(context, failure)),
    );
  }

  Widget _buildStatusCard(
    BuildContext context, {
    required Color color,
    required Color foregroundColor,
    required Widget leading,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: IconTheme(
        data: IconThemeData(color: foregroundColor),
        child: DefaultTextStyle.merge(
          style: TextStyle(color: foregroundColor),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              leading,
              const SizedBox(width: 12),
              Expanded(child: child),
            ],
          ),
        ),
      ),
    );
  }

  String _failureMessage(BuildContext context, Object failure) {
    return switch (failure) {
      NoLocalNetworkFailure() => context.formatString(
        AppLocale.pairingNoLocalNetwork,
        [],
      ),
      NoPairableDeviceFailure() => context.formatString(
        AppLocale.pairingNoDeviceFound,
        [],
      ),
      DevicePairingConnectionFailure(:final endpoint) => context.formatString(
        AppLocale.pairingConnectionFailed,
        [endpoint.authority],
      ),
      DevicePairingRejectedFailure(:final responseCode)
          when responseCode == Device.unauthorizedCode =>
        context.formatString(AppLocale.pairingRejected, []),
      DevicePairingRejectedFailure() || DevicePairingProtocolFailure() =>
        context.formatString(AppLocale.pairingProtocolFailed, []),
      _ => context.formatString(AppLocale.pairingProtocolFailed, []),
    };
  }

  void _selectMethod(_PairingMethod method) {
    setState(() {
      _method = method;
      _attempt = const _PairingIdle();
      _autoSelect = method == _PairingMethod.automatic;
    });
    if (method == _PairingMethod.direct) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _hostFocusNode.requestFocus();
        }
      });
    }
  }

  void _invalidateDirectPairing() {
    if (_method == _PairingMethod.direct &&
        _attempt is! _PairingIdle &&
        !_isPairing) {
      setState(() => _attempt = const _PairingIdle());
    }
  }

  Future<void> _discover() async {
    await _runPairing(const _PairingRunning(), widget.pairingService.discover);
  }

  Future<void> _pairDirectly() async {
    if (!(_endpointFormKey.currentState?.validate() ?? false)) {
      return;
    }
    final endpoint = DeviceEndpoint(
      host: _hostController.text,
      port: int.parse(_portController.text),
    );
    await _runPairing(
      _PairingRunning(endpoint: endpoint),
      () => widget.pairingService.pairAt(endpoint),
    );
  }

  Future<void> _runPairing(
    _PairingRunning running,
    Future<Device> Function() operation,
  ) async {
    setState(() => _attempt = running);
    try {
      final device = await operation();
      if (!mounted) {
        return;
      }
      device.targetDeviceName = _nextAvailableDeviceName(
        device.targetDeviceName,
      );
      _populateControllers(device);
      setState(() => _attempt = _PairingReady(device));
    } catch (failure) {
      if (mounted) {
        setState(() => _attempt = _PairingFailed(failure));
      }
    }
  }

  void _populateControllers(Device device) {
    _deviceNameController.text = device.targetDeviceName;
    _hostController.text = device.iP;
    _portController.text = device.port.toString();
    _secretKeyController.text = device.secretKey;
    _certificateController.text = device.trustedCertificate;
  }

  /// Hostnames only need to be unique on their own networks, while WindSend
  /// uses the display name as a local persistence key. A stable suffix keeps
  /// two same-named computers addable without the old random renaming.
  String _nextAvailableDeviceName(String requestedName) {
    final existingNames = widget.devices
        .map((device) => device.targetDeviceName)
        .toSet();
    if (!existingNames.contains(requestedName)) {
      return requestedName;
    }
    for (var suffix = 2; ; suffix++) {
      final candidate = '$requestedName ($suffix)';
      if (!existingNames.contains(candidate)) {
        return candidate;
      }
    }
  }

  void _submit() {
    final Device? newDevice;
    if (_method == _PairingMethod.manual) {
      if (!(_manualFormKey.currentState?.validate() ?? false)) {
        return;
      }
      newDevice = Device(
        targetDeviceName: _deviceNameController.text.trim(),
        iP: _hostController.text.trim(),
        port: int.parse(_portController.text),
        secretKey: _secretKeyController.text.trim(),
        trustedCertificate: _certificateController.text.trim(),
        autoSelect: _autoSelect,
      );
    } else {
      final pairedDevice = _pairedDevice;
      if (pairedDevice == null) {
        return;
      }
      newDevice = Device.copy(pairedDevice)..autoSelect = _autoSelect;
    }

    if (newDevice.iP.toLowerCase() == Device.webIP) {
      newDevice.iP = Device.webIP;
      newDevice.autoSelect = false;
      newDevice.actionCopy = false;
      newDevice.actionPasteText = false;
      newDevice.actionPasteFile = false;
      newDevice.actionWebCopy = true;
      newDevice.actionWebPaste = true;
    }

    newDevice.uniqueId = generateRandomString(16);
    widget.devices.add(newDevice);
    LocalConfig.setDevice(newDevice);
    widget.onAddDevice();
    Navigator.pop(context);
  }
}

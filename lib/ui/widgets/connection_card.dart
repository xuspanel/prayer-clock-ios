import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:provider/provider.dart';

import '../../state/clock_controller.dart';
import '../../transport/ble_framing.dart';
import '../theme/p4_theme.dart';

/// Top connection card (`#conn`, lines 84-100) + Web Fallback banner (§6.2).
///
/// Requests Bluetooth permission only at the moment the user taps
/// "Connect Bluetooth" (§4).
class ConnectionCard extends StatefulWidget {
  const ConnectionCard({super.key});

  @override
  State<ConnectionCard> createState() => _ConnectionCardState();
}

class _ConnectionCardState extends State<ConnectionCard> {
  late final TextEditingController _ipCtrl;

  @override
  void initState() {
    super.initState();
    final ctrl = context.read<ClockController>();
    _ipCtrl = TextEditingController(text: ctrl.ipInput);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final ctrl = context.watch<ClockController>();
    if (_ipCtrl.text != ctrl.ipInput &&
        !FocusScope.of(context).hasPrimaryFocus) {
      _ipCtrl.text = ctrl.ipInput;
    }
  }

  @override
  void dispose() {
    _ipCtrl.dispose();
    super.dispose();
  }

  Future<void> _onConnectBleTapped(ClockController ctrl) async {
    if (ctrl.anyTransferBusy) {
      ctrl.showMsg('Finish or cancel the transfer before changing connection');
      return;
    }
    if (kIsWeb) {
      ctrl.showMsg(
        'Web version — Bluetooth is not available in browsers on iPhone; use the iOS app for Bluetooth.',
      );
      return;
    }

    final selectedDevice = await showModalBottomSheet<BluetoothDevice>(
      context: context,
      backgroundColor: P4Colors.card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => const _BleDevicePickerSheet(),
    );

    if (selectedDevice != null && mounted) {
      await ctrl.connectBleDevice(selectedDevice);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<ClockController>();
    final isBle = ctrl.mode == 'ble';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (kIsWeb)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: P4Colors.tabBarBg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: P4Colors.amber, width: 1),
            ),
            child: const Text(
              'Web version — Bluetooth is not available in browsers on iPhone; use the iOS app for Bluetooth.',
              style: TextStyle(color: P4Colors.amber, fontSize: 13),
            ),
          ),
        P4Card(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                ctrl.connText,
                key: const Key('conn_status_text'),
                style: TextStyle(
                  color: ctrl.connOk ? P4Colors.teal : P4Colors.dim,
                  fontSize: 14,
                ),
              ),
              if (ctrl.firmwareVersion.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    ctrl.firmwareVersion,
                    style: const TextStyle(color: P4Colors.dim, fontSize: 12),
                  ),
                ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  if (!isBle)
                    P4Button(
                      key: const Key('btn_connect_ble'),
                      label: '📶 Connect Bluetooth',
                      small: true,
                      onPressed: () => _onConnectBleTapped(ctrl),
                    ),
                  if (isBle)
                    P4Button(
                      key: const Key('btn_disconnect_ble'),
                      label: 'Disconnect Bluetooth',
                      color: P4Colors.slate,
                      small: true,
                      onPressed: () => ctrl.disconnectBle(),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const Key('input_wifi_ip'),
                      controller: _ipCtrl,
                      style: const TextStyle(color: P4Colors.text, fontSize: 15),
                      decoration: InputDecoration(
                        hintText: 'WiFi: board IP or hostname',
                        suffixIcon: _ipCtrl.text.isNotEmpty
                            ? IconButton(
                                tooltip: 'Clear saved IP',
                                icon: const Icon(
                                  Icons.clear,
                                  size: 18,
                                  color: P4Colors.dim,
                                ),
                                onPressed: () {
                                  _ipCtrl.clear();
                                  ctrl.clearSavedIp();
                                },
                              )
                            : null,
                      ),
                      onChanged: ctrl.setIpInput,
                      onSubmitted: (v) => ctrl.connectWifi(v),
                    ),
                  ),
                  const SizedBox(width: 8),
                  P4Button(
                    key: const Key('btn_connect_wifi'),
                    label: 'Connect WiFi',
                    color: P4Colors.slate,
                    small: true,
                    onPressed: () => ctrl.connectWifi(_ipCtrl.text),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _BleDevicePickerSheet extends StatefulWidget {
  const _BleDevicePickerSheet();

  @override
  State<_BleDevicePickerSheet> createState() => _BleDevicePickerSheetState();
}

class _BleDevicePickerSheetState extends State<_BleDevicePickerSheet> {
  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<bool>? _isScanningSub;
  List<ScanResult> _results = <ScanResult>[];
  bool _scanning = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _startScan();
  }

  Future<void> _startScan() async {
    setState(() {
      _error = '';
      _scanning = true;
    });
    try {
      final supported = await FlutterBluePlus.isSupported;
      if (!supported) {
        setState(() {
          _scanning = false;
          _error = 'Bluetooth Low Energy is not supported on this device.';
        });
        return;
      }

      _scanSub ??= FlutterBluePlus.onScanResults.listen((results) {
        if (mounted) {
          setState(() {
            _results = results;
          });
        }
      });

      _isScanningSub ??= FlutterBluePlus.isScanning.listen((isScanning) {
        if (mounted) {
          setState(() {
            _scanning = isScanning;
          });
        }
      });

      await FlutterBluePlus.startScan(
        withServices: [Guid(kP4ServiceUuid)],
        timeout: const Duration(seconds: 10),
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _scanning = false;
          _error = 'Bluetooth scan error: $e';
        });
      }
    }
  }

  @override
  void dispose() {
    FlutterBluePlus.stopScan().catchError((_) {});
    _scanSub?.cancel();
    _isScanningSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '📶 Select Prayer Clock (BLE)',
                  style: TextStyle(
                    color: P4Colors.teal,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                P4Button(
                  label: _scanning ? 'Scanning...' : '↻ Rescan',
                  small: true,
                  color: P4Colors.slate,
                  onPressed: _scanning ? null : _startScan,
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'Service UUID: 6e400001-b5a3-f393-e0a9-e50e24dcca9e',
              style: TextStyle(color: P4Colors.dim, fontSize: 12),
            ),
            if (_error.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  _error,
                  style: const TextStyle(color: P4Colors.red, fontSize: 14),
                ),
              ),
            const SizedBox(height: 10),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 280),
              child: _results.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: Text(
                          _scanning
                              ? 'Searching for nearby Prayer Clock...'
                              : 'No Prayer Clock found nearby. Make sure Bluetooth is enabled and the clock is powered on.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: P4Colors.dim),
                        ),
                      ),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      itemCount: _results.length,
                      separatorBuilder: (_, _) =>
                          const Divider(color: P4Colors.slate, height: 1),
                      itemBuilder: (ctx, i) {
                        final r = _results[i];
                        final name = r.advertisementData.advName.isNotEmpty
                            ? r.advertisementData.advName
                            : (r.device.platformName.isNotEmpty
                                ? r.device.platformName
                                : 'P4-Clock (${r.device.remoteId.str})');
                        return ListTile(
                          title: Text(
                            name,
                            style: const TextStyle(
                              color: P4Colors.text,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: Text(
                            '${r.device.remoteId.str}  •  ${r.rssi} dBm',
                            style: const TextStyle(
                              color: P4Colors.dim,
                              fontSize: 12,
                            ),
                          ),
                          trailing: P4Button(
                            label: 'Connect',
                            small: true,
                            onPressed: () {
                              FlutterBluePlus.stopScan().catchError((_) {});
                              Navigator.of(context).pop(r.device);
                            },
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}


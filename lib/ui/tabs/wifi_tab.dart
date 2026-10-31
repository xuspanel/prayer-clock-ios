import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/clock_controller.dart';
import '../theme/p4_theme.dart';

/// Tab 6: WiFi (`#t-wifi`, lines 342-373 & 1707-1776).
class WifiTab extends StatefulWidget {
  const WifiTab({super.key});

  @override
  State<WifiTab> createState() => _WifiTabState();
}

class _WifiTabState extends State<WifiTab> {
  final TextEditingController _ssidCtrl = TextEditingController();
  final TextEditingController _passCtrl = TextEditingController();
  final FocusNode _passFocus = FocusNode();
  bool _showPassword = false;

  @override
  void dispose() {
    _ssidCtrl.dispose();
    _passCtrl.dispose();
    _passFocus.dispose();
    super.dispose();
  }

  Future<void> _onToggleConnect(ClockController ctrl, bool isConnected) async {
    if (isConnected && ctrl.mode == 'wifi') {
      final ok = await showP4ConfirmDialog(
        context,
        title: 'Disconnect WiFi',
        message: 'Disconnect WiFi? This page stops working (use Bluetooth).',
        confirmLabel: 'Disconnect',
      );
      if (!ok) return;
    }
    await ctrl.toggleWifiConnection(isConnected);
  }

  Future<void> _onClearSaved(ClockController ctrl) async {
    final ok = await showP4ConfirmDialog(
      context,
      title: 'Clear saved WiFi',
      message:
          'Erase the saved WiFi network and password?${ctrl.mode == 'wifi' ? ' This page stops working.' : ''}',
      confirmLabel: 'Erase',
    );
    if (ok) {
      await ctrl.clearSavedWifi();
    }
  }

  Future<void> _onRestart(ClockController ctrl) async {
    if (ctrl.anyTransferBusy) {
      ctrl.showMsg('Finish or cancel the transfer first');
      return;
    }
    final ok = await showP4ConfirmDialog(
      context,
      title: 'Restart board',
      message: 'Restart the board now?',
      confirmLabel: 'Restart',
      confirmColor: P4Colors.orange,
    );
    if (ok) {
      await ctrl.restartBoard();
    }
  }

  Future<void> _onMaint(ClockController ctrl) async {
    if (ctrl.mode != 'wifi') {
      ctrl.showMsg('Maintenance mode works over WiFi only');
      return;
    }
    if (ctrl.anyTransferBusy) {
      ctrl.showMsg('Finish or cancel the transfer first');
      return;
    }
    final ok = await showP4ConfirmDialog(
      context,
      title: 'Maintenance mode',
      message:
          'Restart the clock in maintenance mode?\nThe clock, alarms and azan pause until you restart it normally from the maintenance page.',
      confirmLabel: 'Restart in maintenance mode',
      confirmColor: P4Colors.indigo,
    );
    if (ok) {
      await ctrl.startMaintenanceMode();
    }
  }

  Future<void> _onKeepChanged(ClockController ctrl, bool nextVal) async {
    if (!nextVal && ctrl.keep0 && ctrl.mode == 'wifi') {
      final ok = await showP4ConfirmDialog(
        context,
        title: 'Stay connected OFF',
        message:
            'With "Stay connected" OFF the board leaves WiFi after the time sync and this page stops working. Continue?',
        confirmLabel: 'Continue',
      );
      if (!ok) return;
    }
    await ctrl.setWifiKeep(nextVal);
  }

  Future<void> _onJoinNetwork(ClockController ctrl) async {
    final s = _ssidCtrl.text.trim();
    if (s.isEmpty) {
      ctrl.showMsg('Choose a network first');
      return;
    }
    if (ctrl.mode == 'wifi') {
      final ok = await showP4ConfirmDialog(
        context,
        title: 'Join network',
        message:
            'The board leaves the current network to join "$s". This page may stop working. Continue?',
        confirmLabel: 'Join',
        confirmColor: P4Colors.teal,
      );
      if (!ok) return;
    }
    await ctrl.joinWifi(s, _passCtrl.text);
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<ClockController>();
    final d = ctrl.wifiData;

    final statusText = d?['status']?.toString() ?? '';
    final rtcText = d?['rtc']?.toString() ?? '';
    final isConnected =
        (d?['con'] == true || d?['con'] == 1) ||
        (d?['busy'] == true || d?['busy'] == 1);
    final isScanning = d?['scan'] == 'busy';
    final List<dynamic> rawNets =
        (d?['nets'] is List) ? (d!['nets'] as List) : const [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        P4Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '📶 WiFi',
                style: TextStyle(
                  color: P4Colors.teal,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (statusText.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    statusText,
                    style: const TextStyle(color: P4Colors.text, fontSize: 15),
                  ),
                ),
              if (rtcText.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    rtcText,
                    style: const TextStyle(color: P4Colors.dim, fontSize: 14),
                  ),
                ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  P4Button(
                    key: const Key('btn_wifi_toggle'),
                    label: isConnected ? '✕ Disconnect' : '📶 Connect',
                    small: true,
                    onPressed: () => _onToggleConnect(ctrl, isConnected),
                  ),
                  P4Button(
                    key: const Key('btn_wifi_clear'),
                    label: '🗑 Clear saved',
                    small: true,
                    color: P4Colors.red,
                    onPressed: () => _onClearSaved(ctrl),
                  ),
                  P4Button(
                    key: const Key('btn_wifi_restart'),
                    label: '↻ Restart board',
                    small: true,
                    color: P4Colors.orange,
                    onPressed: () => _onRestart(ctrl),
                  ),
                  if (ctrl.mode == 'wifi')
                    P4Button(
                      key: const Key('btn_wifi_maint'),
                      label: '🔧 OTA mode',
                      small: true,
                      color: P4Colors.indigo,
                      onPressed: ctrl.mtGo ? null : () => _onMaint(ctrl),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              P4FieldRow(
                label: const Text(
                  'Stay connected (needed for the WiFi page + OTA)',
                ),
                control: Checkbox(
                  key: const Key('cb_wifi_keep'),
                  value: ctrl.keep0,
                  onChanged: (v) => _onKeepChanged(ctrl, v ?? true),
                ),
              ),
            ],
          ),
        ),
        P4Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Join a network',
                style: TextStyle(
                  color: P4Colors.teal,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              P4Button(
                key: const Key('btn_wifi_scan'),
                label: isScanning ? 'Scanning...' : '↻ Scan',
                small: true,
                onPressed: ctrl.scanWifi,
              ),
              const SizedBox(height: 8),
              if (d != null && d['nets'] is List && rawNets.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 6),
                  child: Text(
                    'No networks found',
                    style: TextStyle(color: P4Colors.dim),
                  ),
                )
              else if (rawNets.isNotEmpty)
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 280),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: rawNets.length,
                    itemBuilder: (ctx, i) {
                      final n = rawNets[i];
                      if (n is! Map) return const SizedBox.shrink();
                      final ssid = n['s']?.toString() ?? '';
                      final rssi = n['r']?.toString() ?? '';
                      final isOpen = n['o'] == true || n['o'] == 1;
                      return InkWell(
                        onTap: () {
                          setState(() {
                            _ssidCtrl.text = ssid;
                            _passCtrl.clear();
                          });
                          _passFocus.requestFocus();
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            vertical: 10,
                            horizontal: 4,
                          ),
                          decoration: const BoxDecoration(
                            border: Border(
                              bottom: BorderSide(color: P4Colors.slate),
                            ),
                          ),
                          child: Text(
                            '📶 $ssid   ($rssi dBm)${isOpen ? '  [open]' : ''}',
                            style: const TextStyle(color: P4Colors.text),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              P4FieldRow(
                label: const Text('Network'),
                control: TextField(
                  key: const Key('input_wifi_ssid'),
                  controller: _ssidCtrl,
                  decoration: const InputDecoration(
                    hintText: 'tap a network or type it',
                  ),
                ),
              ),
              P4FieldRow(
                label: const Text('Password'),
                control: TextField(
                  key: const Key('input_wifi_pass'),
                  controller: _passCtrl,
                  focusNode: _passFocus,
                  obscureText: !_showPassword,
                  autocorrect: false,
                  enableSuggestions: false,
                ),
              ),
              P4FieldRow(
                label: const Text('Show password'),
                control: Checkbox(
                  value: _showPassword,
                  onChanged: (v) => setState(() => _showPassword = v ?? false),
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: P4Button(
                  key: const Key('btn_wifi_join'),
                  label: '✔ Join network',
                  onPressed: () => _onJoinNetwork(ctrl),
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'The network is saved after a successful connection.',
                style: TextStyle(color: P4Colors.dim, fontSize: 13),
              ),
            ],
          ),
        ),
      ],
    );
  }
}


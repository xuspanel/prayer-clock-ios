import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../state/clock_controller.dart';
import '../theme/p4_theme.dart';

/// Tab 8: System (`#t-sys`, lines 414-492 & 1455-1531, 2065-2110).
///
/// Includes PIN and clock card, Firmware update (OTA, WiFi only) + Offline Bluetooth page
/// download, Maintenance mode (WiFi only), Video mode, and Bluetooth console (BLE only).
class SystemTab extends StatefulWidget {
  const SystemTab({super.key});

  @override
  State<SystemTab> createState() => _SystemTabState();
}

class _SystemTabState extends State<SystemTab> {
  final TextEditingController _newPinCtrl = TextEditingController();
  final TextEditingController _bleCmdCtrl = TextEditingController();
  String? _selectedFwName;
  Uint8List? _selectedFwBytes;

  @override
  void dispose() {
    _newPinCtrl.dispose();
    _bleCmdCtrl.dispose();
    super.dispose();
  }

  Future<void> _onSetPin(ClockController ctrl) async {
    final p = _newPinCtrl.text.trim();
    if (p.isNotEmpty && !RegExp(r'^\d{4,8}$').hasMatch(p)) {
      ctrl.showMsg('PIN must be 4 - 8 digits, or empty to remove it');
      return;
    }
    if (p.isEmpty) {
      final ok = await showP4ConfirmDialog(
        context,
        title: 'Remove PIN',
        message:
            'Remove the PIN? Anyone nearby / on your WiFi can then use this page.',
        confirmLabel: 'Remove PIN',
      );
      if (!ok) return;
    }
    _newPinCtrl.clear();
    await ctrl.setNewPin(p);
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

  Future<void> _onPickFirmware(ClockController ctrl) async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['bin'],
      withData: true,
    );
    if (res != null && res.files.isNotEmpty && res.files.first.bytes != null) {
      setState(() {
        _selectedFwName = res.files.first.name;
        _selectedFwBytes = res.files.first.bytes;
      });
    }
  }

  Future<void> _onInstallOta(ClockController ctrl) async {
    if (ctrl.mode != 'wifi' || !ctrl.ready) {
      ctrl.showMsg('Firmware update needs an unlocked WiFi connection');
      return;
    }
    if (ctrl.anyTransferBusy) {
      ctrl.showMsg('Another transfer is running');
      return;
    }
    if (_selectedFwName == null || _selectedFwBytes == null) {
      ctrl.showMsg('Choose the .bin file first');
      return;
    }
    if (!RegExp(r'\.bin$', caseSensitive: false).hasMatch(_selectedFwName!)) {
      ctrl.showMsg('That is not a .bin file');
      return;
    }
    final ok = await showP4ConfirmDialog(
      context,
      title: 'Firmware Update (OTA)',
      message: 'Install $_selectedFwName? The clock restarts when done.',
      confirmLabel: 'Install',
      confirmColor: P4Colors.orange,
    );
    if (!ok) return;
    await ctrl.installOtaFirmware(_selectedFwName!, _selectedFwBytes!);
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
    if (ctrl.mtGo) return;
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

  Future<void> _onVideoMode(ClockController ctrl) async {
    if (ctrl.anyTransferBusy) {
      ctrl.showMsg('Finish or cancel the transfer first');
      return;
    }
    final ok = await showP4ConfirmDialog(
      context,
      title: 'Video mode',
      message:
          'Restart the clock in video mode?\nIt goes back to the clock by itself before the next azan or alarm.',
      confirmLabel: 'Restart in video mode',
      confirmColor: P4Colors.indigo,
    );
    if (ok) {
      await ctrl.startVideoMode();
    }
  }

  void _onSendConsole(ClockController ctrl) {
    final text = _bleCmdCtrl.text;
    _bleCmdCtrl.clear();
    ctrl.sendBleConsoleCommand(text);
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<ClockController>();
    final isWifi = ctrl.mode == 'wifi';
    final isBle = ctrl.mode == 'ble';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Card 1: PIN and clock
        P4Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '🔒 PIN and clock',
                style: TextStyle(
                  color: P4Colors.teal,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              P4FieldRow(
                label: const Text('New PIN (4-8 digits, empty = no PIN)'),
                control: TextField(
                  key: const Key('input_new_pin'),
                  controller: _newPinCtrl,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  maxLength: 8,
                  decoration: const InputDecoration(counterText: ''),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  P4Button(
                    key: const Key('btn_set_pin'),
                    label: 'Set PIN',
                    onPressed: () => _onSetPin(ctrl),
                  ),
                  P4Button(
                    key: const Key('btn_set_time'),
                    label: '🕒 Set board clock from this phone',
                    color: P4Colors.slate,
                    onPressed: ctrl.setBoardClockFromPhone,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  P4Button(
                    key: const Key('btn_lock_page'),
                    label: 'Lock this page',
                    color: P4Colors.slate,
                    onPressed: ctrl.logout,
                  ),
                  P4Button(
                    key: const Key('btn_sys_restart'),
                    label: '↻ Restart board',
                    color: P4Colors.orange,
                    onPressed: () => _onRestart(ctrl),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'The PIN is retained only while this page is open.\nLock this page to clear the current login.',
                style: TextStyle(color: P4Colors.dim, fontSize: 13),
              ),
            ],
          ),
        ),

        // Card 2: Firmware update (OTA, WiFi only)
        if (isWifi)
          P4Card(
            key: const Key('card_ota'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '⬆ Firmware update (OTA, WiFi only)',
                  style: TextStyle(
                    color: P4Colors.teal,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'PlatformIO: .pio/build/<env>/firmware.bin.\nSettings and SD card files are kept.',
                  style: TextStyle(color: P4Colors.dim, fontSize: 13),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: P4Button(
                        key: const Key('btn_choose_fw'),
                        label: _selectedFwName ?? 'Choose .bin file...',
                        color: P4Colors.slate,
                        small: true,
                        onPressed: () => _onPickFirmware(ctrl),
                      ),
                    ),
                    const SizedBox(width: 8),
                    P4Button(
                      key: const Key('btn_install_ota'),
                      label: 'Install',
                      color: P4Colors.orange,
                      onPressed: () => _onInstallOta(ctrl),
                    ),
                  ],
                ),
                if (ctrl.otaStatus.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      ctrl.otaStatus,
                      style: const TextStyle(
                        color: P4Colors.amber,
                        fontSize: 14,
                      ),
                    ),
                  ),
                const SizedBox(height: 14),
                const Text(
                  'Offline Bluetooth page',
                  style: TextStyle(
                    color: P4Colors.dim,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Save this page to control the clock over Bluetooth without WiFi, using a browser that supports Web Bluetooth.\nOpening a saved file is browser/platform dependent.\nIf necessary, use a trusted HTTPS host or localhost.',
                  style: TextStyle(color: P4Colors.dim, fontSize: 13),
                ),
                const SizedBox(height: 10),
                Center(
                  child: P4Button(
                    key: const Key('btn_dl_p4clock_html'),
                    label: '⬇ Download p4clock.html',
                    small: true,
                    color: P4Colors.slate,
                    onPressed: () {
                      final url = ctrl.baseUrl.isNotEmpty
                          ? '${ctrl.baseUrl}/p4clock.html'
                          : 'https://prayer.xus.me/p4clock.html?dl=1';
                      launchUrl(
                        Uri.parse(url),
                        mode: LaunchMode.externalApplication,
                      );
                    },
                  ),
                ),
              ],
            ),
          ),

        // Card 3: Maintenance mode (WiFi only)
        if (isWifi)
          P4Card(
            key: const Key('card_maint'),
            borderColor: P4Colors.indigo,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '🔧 Maintenance mode (WiFi only)',
                  style: TextStyle(
                    color: P4Colors.teal,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'The clock restarts into a small maintenance page for firmware updates and SD card files.\nThe clock, alarms and azan pause until you restart it normally from that page.\nUse it if the normal update above fails.',
                  style: TextStyle(color: P4Colors.dim, fontSize: 13),
                ),
                const SizedBox(height: 10),
                Center(
                  child: P4Button(
                    key: const Key('btn_sys_maint'),
                    label: '🔧 Restart in maintenance mode',
                    color: P4Colors.indigo,
                    onPressed: ctrl.mtGo ? null : () => _onMaint(ctrl),
                  ),
                ),
                if (ctrl.maintStatus.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      ctrl.maintStatus,
                      style: const TextStyle(
                        color: P4Colors.amber,
                        fontSize: 14,
                      ),
                    ),
                  ),
              ],
            ),
          ),

        // Card 4: Video mode
        P4Card(
          key: const Key('card_video'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '🎥 Video mode',
                style: TextStyle(
                  color: P4Colors.teal,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'The clock restarts into a video player for the videos in /video on the SD card (made with convert_video.bat).\nControl it on the clock screen or from its own web page. It goes back to the clock by itself before the next azan or alarm.',
                style: TextStyle(color: P4Colors.dim, fontSize: 13),
              ),
              const SizedBox(height: 10),
              Center(
                child: P4Button(
                  key: const Key('btn_sys_video'),
                  label: '🎥 Restart in video mode',
                  color: P4Colors.indigo,
                  onPressed: () => _onVideoMode(ctrl),
                ),
              ),
              if (ctrl.videoStatus.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    ctrl.videoStatus,
                    style: const TextStyle(
                      color: P4Colors.amber,
                      fontSize: 14,
                    ),
                  ),
                ),
            ],
          ),
        ),

        // Card 5: Bluetooth console (BLE only)
        if (isBle)
          P4Card(
            key: const Key('card_ble_console'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '🖥 Bluetooth console',
                  style: TextStyle(
                    color: P4Colors.teal,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Text commands - type help. Protected commands may require pin followed by your PIN.',
                  style: TextStyle(color: P4Colors.dim, fontSize: 13),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        key: const Key('input_ble_cmd'),
                        controller: _bleCmdCtrl,
                        decoration: const InputDecoration(
                          hintText: 'e.g. help, ls, status',
                        ),
                        onSubmitted: (_) => _onSendConsole(ctrl),
                      ),
                    ),
                    const SizedBox(width: 6),
                    P4Button(
                      key: const Key('btn_ble_send'),
                      label: 'Send',
                      small: true,
                      onPressed: () => _onSendConsole(ctrl),
                    ),
                    const SizedBox(width: 6),
                    P4Button(
                      key: const Key('btn_ble_clear'),
                      label: 'Clear',
                      small: true,
                      color: P4Colors.slate,
                      onPressed: ctrl.clearBleConsole,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  height: 200,
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: P4Colors.bg,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: ListView.builder(
                    itemCount: ctrl.bleConsoleLines.length,
                    itemBuilder: (ctx, i) => Text(
                      ctrl.bleConsoleLines[i],
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 13,
                        color: P4Colors.text,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}


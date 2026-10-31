import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/clock_controller.dart';
import '../../transport/p4_transport.dart';
import '../theme/p4_theme.dart';

/// Tab 5: Settings (`#t-set`, lines 294-340 & 615-649, 1206-1329).
class SettingsTab extends StatefulWidget {
  const SettingsTab({super.key});

  @override
  State<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<SettingsTab> {
  int _syncedVersion = -1;

  final TextEditingController _bnameCtrl = TextEditingController();
  int _bright = 80;
  bool _h24 = true;
  int _method = 0;
  int _hijri = 0;
  final TextEditingController _locksecCtrl = TextEditingController(text: '0');

  @override
  void dispose() {
    _bnameCtrl.dispose();
    _locksecCtrl.dispose();
    super.dispose();
  }

  void _syncFromSettings(ClockController ctrl) {
    final d = ctrl.setD;
    if (d == null) return;
    if (ctrl.dirtySet && _syncedVersion >= 0) return;
    _syncedVersion = ctrl.settingsFormVersion;

    _bnameCtrl.text = d['bname']?.toString() ?? '';
    _bright =
        (d['bright'] is num) ? (d['bright'] as num).toInt().clamp(5, 100) : 80;
    _h24 = d['h24'] == null ? true : (d['h24'] == true || d['h24'] == 1);
    _method = (d['method'] is num) ? (d['method'] as num).toInt() : 0;
    _hijri = (d['hijri'] is num) ? (d['hijri'] as num).toInt() : 0;
    if (d['locksec'] != null) {
      _locksecCtrl.text = d['locksec'].toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<ClockController>();
    if (_syncedVersion != ctrl.settingsFormVersion) {
      _syncFromSettings(ctrl);
    }

    final d = ctrl.setD;
    final defBle = d?['defble']?.toString() ?? 'P4-Clock';
    final defHost = d?['defhost']?.toString() ?? 'prayerclock';

    // `function namePreview()` (lines 626-638)
    final trimmedName = _bnameCtrl.text.trim();
    final isNameGood = validClockName(trimmedName);
    final previewBle = trimmedName.isNotEmpty ? trimmedName : defBle;
    final previewHost = hostForName(trimmedName, defHost: defHost);
    final String namePreviewText = isNameGood
        ? 'Bluetooth: $previewBle\nWiFi: http://$previewHost.local/'
        : 'Use up to 20 English letters, numbers, spaces and - _ . Include a letter or number.';

    // `function nameSaved(d)` (lines 640-649)
    final savedBle = d?['ble']?.toString() ??
        d?['bname']?.toString() ??
        d?['defble']?.toString() ??
        'P4-Clock';
    final savedHost = d?['host']?.toString() ??
        hostForName(d?['bname']?.toString() ?? '', defHost: defHost);
    final String nameSavedText = d != null
        ? 'Saved Bluetooth name: $savedBle\nSaved WiFi address: http://$savedHost.local/'
        : '';

    final methodItems = List<DropdownMenuItem<int>>.generate(
      ctrl.methods.length,
      (i) {
        final angle = i < ctrl.methodAngles.length
            ? ctrl.methodAngles[i].toStringAsFixed(1)
            : '0.0';
        return DropdownMenuItem(
          value: i,
          child: Text(
            '${ctrl.methods[i]}  (Fajr $angle)',
            overflow: TextOverflow.ellipsis,
          ),
        );
      },
    );
    final effectiveMethod =
        (methodItems.isNotEmpty && _method >= 0 && _method < methodItems.length)
            ? _method
            : 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        P4Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '⚙ Settings',
                style: TextStyle(
                  color: P4Colors.teal,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              P4FieldRow(
                label: const Text('Clock name'),
                control: TextField(
                  key: const Key('input_clock_name'),
                  controller: _bnameCtrl,
                  maxLength: 20,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    hintText: defBle,
                    counterText: '',
                  ),
                  onChanged: (_) {
                    ctrl.dirtySet = true;
                    setState(() {});
                  },
                ),
              ),
              const Text(
                'Up to 20 English letters, numbers, spaces and - _ .\nLeave empty to restore the default names.\nThis setting applies to both the WiFi and Bluetooth remotes.',
                style: TextStyle(color: P4Colors.dim, fontSize: 13),
              ),
              const SizedBox(height: 8),
              Text(
                namePreviewText,
                key: const Key('text_name_preview'),
                style: TextStyle(
                  color: isNameGood ? P4Colors.teal : P4Colors.amber,
                  fontSize: 14,
                ),
              ),
              if (nameSavedText.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  nameSavedText,
                  key: const Key('text_name_saved'),
                  style: const TextStyle(color: P4Colors.dim, fontSize: 14),
                ),
              ],
              const SizedBox(height: 6),
              const Text(
                'The new Bluetooth scan name may appear after disconnecting and scanning again.\nYour browser may retain the old device name.\nThe router\'s hostname entry may update on the next WiFi connection.',
                style: TextStyle(color: P4Colors.dim, fontSize: 13),
              ),
              const SizedBox(height: 10),
              P4FieldRow(
                label: Text('Brightness $_bright'),
                control: Slider(
                  key: const Key('slider_brightness'),
                  min: 5,
                  max: 100,
                  divisions: 95,
                  value: _bright.toDouble(),
                  onChanged: (v) {
                    final next = v.round();
                    setState(() => _bright = next);
                    ctrl.setBrightnessDebounced(next);
                  },
                ),
              ),
              P4FieldRow(
                label: const Text('24-hour clock'),
                control: Checkbox(
                  key: const Key('cb_h24'),
                  value: _h24,
                  onChanged: (v) {
                    setState(() {
                      ctrl.dirtySet = true;
                      _h24 = v ?? true;
                    });
                  },
                ),
              ),
              P4FieldRow(
                label: const Text('Calculation method'),
                control: methodItems.isEmpty
                    ? const Text(
                        'Connect to load methods',
                        style: TextStyle(color: P4Colors.dim),
                      )
                    : DropdownButtonFormField<int>(
                        key: const Key('select_method'),
                        initialValue: effectiveMethod,
                        isExpanded: true,
                        items: methodItems,
                        onChanged: (v) {
                          if (v != null) {
                            setState(() {
                              ctrl.dirtySet = true;
                              _method = v;
                            });
                          }
                        },
                      ),
              ),
              P4FieldRow(
                label: const Text('Hijri date adjust'),
                control: DropdownButtonFormField<int>(
                  key: const Key('select_hijri'),
                  initialValue: _hijri.clamp(-2, 2),
                  isExpanded: true,
                  items: const [
                    DropdownMenuItem(value: -2, child: Text('-2 days')),
                    DropdownMenuItem(value: -1, child: Text('-1 day')),
                    DropdownMenuItem(
                      value: 0,
                      child: Text('0 (Umm al-Qura)'),
                    ),
                    DropdownMenuItem(value: 1, child: Text('+1 day')),
                    DropdownMenuItem(value: 2, child: Text('+2 days')),
                  ],
                  onChanged: (v) {
                    if (v != null) {
                      setState(() {
                        ctrl.dirtySet = true;
                        _hijri = v;
                      });
                    }
                  },
                ),
              ),
              P4FieldRow(
                label: const Text('Clock screen auto-lock (0-600 s, 0 = off)'),
                control: TextField(
                  key: const Key('input_locksec'),
                  controller: _locksecCtrl,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => ctrl.dirtySet = true,
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child: P4Button(
                  key: const Key('btn_save_settings'),
                  label: '✔ Save settings',
                  onPressed: ctrl.setSaving
                      ? null
                      : () => ctrl.saveGeneralSettings(
                            bname: _bnameCtrl.text,
                            method: effectiveMethod,
                            hijri: _hijri,
                            h24: _h24,
                            locksecRaw: _locksecCtrl.text,
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


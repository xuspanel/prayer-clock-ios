import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/clock_controller.dart';
import '../../transport/p4_transport.dart';
import '../theme/p4_theme.dart';

/// Tab 2: Prayer (`#t-pray`, lines 159-205 & 1194-1361).
class PrayerTab extends StatefulWidget {
  const PrayerTab({super.key});

  @override
  State<PrayerTab> createState() => _PrayerTabState();
}

class _PrayerTabState extends State<PrayerTab> {
  int _syncedVersion = -1;

  List<bool> _az = <bool>[true, true, true];
  String _azFajr = '';
  String _azFile = '';
  String _azMag = '';
  final TextEditingController _azVolCtrl = TextEditingController(text: '15');
  final TextEditingController _leadCtrl = TextEditingController(text: '0');
  bool _fDefChecked = true;
  final TextEditingController _fAngleCtrl = TextEditingController(text: '18.0');
  final TextEditingController _maghCtrl = TextEditingController(text: '0');
  bool _azBg = false;

  @override
  void dispose() {
    _azVolCtrl.dispose();
    _leadCtrl.dispose();
    _fAngleCtrl.dispose();
    _maghCtrl.dispose();
    super.dispose();
  }

  String _pickAzFile(List<String> files, String want, int fallbackIndex) {
    if (files.isEmpty) return '';
    final idx = files.indexWhere((p) => p.toLowerCase() == want.toLowerCase());
    if (idx >= 0) return files[idx];
    final clamped = fallbackIndex.clamp(0, files.length - 1);
    return files[clamped];
  }

  void _syncFromSettings(ClockController ctrl) {
    final d = ctrl.setD;
    if (d == null) return;
    if (ctrl.dirtyPray && _syncedVersion >= 0) return;
    _syncedVersion = ctrl.settingsFormVersion;

    final rawAz = (d['az'] is List) ? (d['az'] as List) : const [];
    _az = List<bool>.generate(
      3,
      (i) => i < rawAz.length ? (rawAz[i] == true || rawAz[i] == 1) : false,
    );

    _azVolCtrl.text = (d['azvol'] ?? 15).toString();
    _leadCtrl.text = (d['lead'] ?? 0).toString();
    _maghCtrl.text = (d['magh'] ?? 0).toString();
    _azBg = d['azbg'] == true || d['azbg'] == 1;

    final azFiles = (d['azfiles'] is List)
        ? (d['azfiles'] as List).map((e) => e.toString()).toList()
        : <String>[];

    _azFile = _pickAzFile(
      azFiles,
      d['azfile']?.toString() ?? '/azan/azan.mp3',
      0,
    );
    final dhuhrIdx = azFiles.indexOf(_azFile);
    _azFajr = _pickAzFile(
      azFiles,
      d['azfajr']?.toString() ?? '/azan/azan_fajr.mp3',
      dhuhrIdx < 0 ? 0 : dhuhrIdx,
    );
    _azMag = _pickAzFile(
      azFiles,
      d['azmag']?.toString() ?? '',
      dhuhrIdx < 0 ? 0 : dhuhrIdx,
    );

    final methodIdx = (d['method'] is num) ? (d['method'] as num).toInt() : 0;
    final defAngle = (methodIdx >= 0 && methodIdx < ctrl.methodAngles.length)
        ? ctrl.methodAngles[methodIdx]
        : 0.0;
    final rawFangle = double.tryParse(d['fangle']?.toString() ?? '0') ?? 0.0;
    _fDefChecked = !(rawFangle > 0);
    _fAngleCtrl.text = (rawFangle > 0 ? rawFangle : defAngle).toStringAsFixed(1);
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<ClockController>();
    if (_syncedVersion != ctrl.settingsFormVersion) {
      _syncFromSettings(ctrl);
    }

    final st = ctrl.lastSt;
    final d = ctrl.setD;
    final List<int> pt = (st?['pt'] is List)
        ? (st!['pt'] as List)
            .map((e) => (e is num) ? e.toInt() : -1)
            .toList()
        : const <int>[];
    final int? nextIdx =
        (st?['nexti'] is num) ? (st!['nexti'] as num).toInt() : null;

    final int methodIdx =
        (d?['method'] is num) ? (d!['method'] as num).toInt() : 0;
    final double defAngle =
        (methodIdx >= 0 && methodIdx < ctrl.methodAngles.length)
            ? ctrl.methodAngles[methodIdx]
            : 0.0;
    final String methodName =
        (methodIdx >= 0 && methodIdx < ctrl.methods.length)
            ? ctrl.methods[methodIdx]
            : '';
    final double savedFangle =
        double.tryParse(d?['fangle']?.toString() ?? '0') ?? 0.0;
    final String phdr = d != null
        ? '${d['city'] ?? ''}  |  $methodName  |  Fajr angle '
            '${savedFangle > 0 ? '${savedFangle.toStringAsFixed(1)} (custom)' : defAngle.toStringAsFixed(1)}'
            '  |  Maghrib = sunset + ${d['magh'] ?? 0} min'
        : '';

    final List<String> azFiles = (d?['azfiles'] is List)
        ? (d!['azfiles'] as List).map((e) => e.toString()).toList()
        : <String>[];

    Widget buildSoundDropdown(String value, ValueChanged<String> onChanged) {
      if (azFiles.isEmpty) {
        return DropdownButtonFormField<String>(
          initialValue: '',
          isExpanded: true,
          items: const [
            DropdownMenuItem(
              value: '',
              child: Text('(no audio files in /azan)'),
            ),
          ],
          onChanged: (_) {},
        );
      }
      final effectiveVal = azFiles.contains(value) ? value : azFiles.first;
      return DropdownButtonFormField<String>(
        initialValue: effectiveVal,
        isExpanded: true,
        items: azFiles
            .map(
              (p) => DropdownMenuItem<String>(
                value: p,
                child: Text(
                  baseName(p),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            )
            .toList(),
        onChanged: (v) {
          if (v != null) {
            ctrl.dirtyPray = true;
            onChanged(v);
          }
        },
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        P4Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '🕐 Today',
                style: TextStyle(
                  color: P4Colors.teal,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              if (pt.isEmpty)
                const Text(
                  'Prayer times not known yet (board clock not set)',
                  style: TextStyle(color: P4Colors.dim, fontSize: 15),
                )
              else
                ...List<Widget>.generate(
                  pt.length < prayerNames.length ? pt.length : prayerNames.length,
                  (i) {
                    final isNext = i == nextIdx;
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        vertical: 8,
                        horizontal: 4,
                      ),
                      decoration: const BoxDecoration(
                        border: Border(
                          bottom: BorderSide(color: P4Colors.slate),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            prayerNames[i],
                            style: TextStyle(
                              color: isNext ? P4Colors.amber : P4Colors.text,
                              fontWeight:
                                  isNext ? FontWeight.bold : FontWeight.normal,
                              fontSize: 18,
                            ),
                          ),
                          Text(
                            formatHm(pt[i], h24: ctrl.is24Hour),
                            style: TextStyle(
                              color: isNext ? P4Colors.amber : P4Colors.text,
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              if (phdr.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    phdr,
                    style: const TextStyle(color: P4Colors.dim, fontSize: 14),
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
                '🕌 Azan',
                style: TextStyle(
                  color: P4Colors.teal,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              P4FieldRow(
                label: const Text('Azan Fajr'),
                control: Checkbox(
                  value: _az[0],
                  onChanged: (v) {
                    setState(() {
                      ctrl.dirtyPray = true;
                      _az[0] = v ?? false;
                    });
                  },
                ),
              ),
              P4FieldRow(
                label: const Text('Azan Dhuhr'),
                control: Checkbox(
                  value: _az[1],
                  onChanged: (v) {
                    setState(() {
                      ctrl.dirtyPray = true;
                      _az[1] = v ?? false;
                    });
                  },
                ),
              ),
              P4FieldRow(
                label: const Text('Azan Maghrib'),
                control: Checkbox(
                  value: _az[2],
                  onChanged: (v) {
                    setState(() {
                      ctrl.dirtyPray = true;
                      _az[2] = v ?? false;
                    });
                  },
                ),
              ),
              P4FieldRow(
                label: const Text('Fajr azan sound'),
                control: buildSoundDropdown(
                  _azFajr,
                  (v) => setState(() => _azFajr = v),
                ),
              ),
              P4FieldRow(
                label: const Text('Dhuhr azan sound'),
                control: buildSoundDropdown(
                  _azFile,
                  (v) => setState(() => _azFile = v),
                ),
              ),
              P4FieldRow(
                label: const Text('Maghrib azan sound'),
                control: buildSoundDropdown(
                  _azMag,
                  (v) => setState(() => _azMag = v),
                ),
              ),
              P4FieldRow(
                label: const Text('Azan volume (0-21)'),
                control: TextField(
                  controller: _azVolCtrl,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => ctrl.dirtyPray = true,
                ),
              ),
              P4FieldRow(
                label: const Text('Start azan early (0-500 s)'),
                control: TextField(
                  controller: _leadCtrl,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => ctrl.dirtyPray = true,
                ),
              ),
              P4FieldRow(
                label: Text(
                  'Fajr angle: method default (${defAngle.toStringAsFixed(1)})',
                ),
                control: Checkbox(
                  value: _fDefChecked,
                  onChanged: (v) {
                    setState(() {
                      ctrl.dirtyPray = true;
                      _fDefChecked = v ?? true;
                    });
                  },
                ),
              ),
              if (!_fDefChecked)
                P4FieldRow(
                  label: const Text('Custom Fajr angle (14.0 - 19.9)'),
                  control: TextField(
                    controller: _fAngleCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (_) => ctrl.dirtyPray = true,
                  ),
                ),
              P4FieldRow(
                label: const Text('Maghrib = sunset + min (0-30)'),
                control: TextField(
                  controller: _maghCtrl,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => ctrl.dirtyPray = true,
                ),
              ),
              P4FieldRow(
                label: const Text('Azan picture on the clock screen'),
                control: Checkbox(
                  value: _azBg,
                  onChanged: (v) {
                    setState(() {
                      ctrl.dirtyPray = true;
                      _azBg = v ?? false;
                    });
                  },
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 6),
                child: Text(
                  'Pictures: .bin files in /images (Files tab). A name with fajr / dhuhr / maghrib is used for that azan, other names for any azan. Random if there are several.',
                  style: TextStyle(color: P4Colors.dim, fontSize: 13),
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  P4Button(
                    label: '▶ Test Fajr',
                    small: true,
                    onPressed: () =>
                        ctrl.testAzan(0, _azFajr, _azVolCtrl.text),
                  ),
                  P4Button(
                    label: '▶ Test Dhuhr',
                    small: true,
                    onPressed: () =>
                        ctrl.testAzan(1, _azFile, _azVolCtrl.text),
                  ),
                  P4Button(
                    label: '▶ Test Maghrib',
                    small: true,
                    onPressed: () =>
                        ctrl.testAzan(2, _azMag, _azVolCtrl.text),
                  ),
                  P4Button(
                    label: '■ Stop',
                    small: true,
                    color: P4Colors.slate,
                    onPressed: () => ctrl.sendCmd('stop'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Center(
                child: P4Button(
                  key: const Key('btn_save_prayer'),
                  label: '✔ Save prayer settings',
                  onPressed: () => ctrl.savePrayerSettings(
                    azEnabled: _az,
                    azFajrFile: _azFajr,
                    azDhuhrFile: _azFile,
                    azMaghribFile: _azMag,
                    azVol: _azVolCtrl.text,
                    lead: _leadCtrl.text,
                    useMethodDefaultFajr: _fDefChecked,
                    customFajrAngle: _fAngleCtrl.text,
                    magh: _maghCtrl.text,
                    azbg: _azBg,
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


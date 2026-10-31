import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/clock_controller.dart';
import '../../transport/p4_transport.dart';
import '../theme/p4_theme.dart';

/// Tab 3: Alarms (`#t-alarms`, lines 207-267 & 1535-1703).
///
/// Includes the alarms list + enable checkboxes + count (`<on> of <total> alarms on.`),
/// and the full alarm editor card (`#aed`) with fixed/relative prayer offset modes,
/// live prayer ring time preview (`#e_prev`), 7 day checkboxes (`Sun`..`Sat`),
/// mutually exclusive `Ramadan only` and `Specific date` (validated 2000-2099),
/// `/alarms` sound picker, volume slider (`0..21`), Test/Stop, Save, Cancel, and Delete.
class AlarmsTab extends StatefulWidget {
  const AlarmsTab({super.key});

  @override
  State<AlarmsTab> createState() => _AlarmsTabState();
}

class _AlarmsTabState extends State<AlarmsTab> {
  int _loadedAlarmIdx = -1;

  final TextEditingController _lblCtrl = TextEditingController();
  int _mode = -1; // -1 Fixed, 0 Fajr, 1 Dhuhr, 2 Maghrib
  final TextEditingController _timeCtrl = TextEditingController(text: '07:00');
  int _dir = -1; // -1 Before, 1 After
  final TextEditingController _offCtrl = TextEditingController(text: '0');
  List<bool> _days = List<bool>.filled(7, false);
  bool _ram = false;
  bool _useDate = false;
  final TextEditingController _dateCtrl = TextEditingController();
  String _sound = '';
  int _vol = 15;

  @override
  void dispose() {
    _lblCtrl.dispose();
    _timeCtrl.dispose();
    _offCtrl.dispose();
    _dateCtrl.dispose();
    super.dispose();
  }

  void _populateEditorFromAlarm(int idx, Map<String, dynamic> x) {
    _loadedAlarmIdx = idx;
    _lblCtrl.text = x['label']?.toString() ?? '';
    _mode = (x['rel'] is num) ? (x['rel'] as num).toInt() : -1;
    final hour = (x['hour'] is num) ? (x['hour'] as num).toInt() : 7;
    final min = (x['min'] is num) ? (x['min'] as num).toInt() : 0;
    _timeCtrl.text = '${p2(hour)}:${p2(min)}';

    final offset = (x['offset'] is num) ? (x['offset'] as num).toInt() : 0;
    _dir = offset < 0 ? -1 : 1;
    _offCtrl.text = offset.abs().toString();

    final daysMask = (x['days'] is num) ? (x['days'] as num).toInt() : 0;
    _days = List<bool>.generate(7, (d) => ((daysMask >> d) & 1) == 1);

    final useDt = x['useDate'] == true || x['useDate'] == 1;
    final isRam = (x['ram'] == true || x['ram'] == 1) && !useDt;
    _ram = isRam;
    _useDate = useDt;

    final now = DateTime.now();
    if (useDt && x['year'] is num && x['month'] is num && x['day'] is num) {
      _dateCtrl.text =
          '${(x['year'] as num).toInt()}-${p2((x['month'] as num).toInt())}-${p2((x['day'] as num).toInt())}';
    } else {
      _dateCtrl.text = '${now.year}-${p2(now.month)}-${p2(now.day)}';
    }

    _vol = (x['vol'] is num) ? (x['vol'] as num).toInt().clamp(0, 21) : 15;
    _sound = x['sound']?.toString() ?? '';
  }

  /// `function ePrev()` (lines 1580-1594).
  String _computeRelativePreview(ClockController ctrl) {
    if (_mode < 0 || _mode >= azanPrayerIndices.length) return '';
    final ptRaw = ctrl.lastSt?['pt'];
    final ptIdx = azanPrayerIndices[_mode];
    int? prayerMin;
    if (ptRaw is List && ptIdx < ptRaw.length && ptRaw[ptIdx] is num) {
      prayerMin = (ptRaw[ptIdx] as num).toInt();
    }
    if (prayerMin == null || prayerMin < 0) {
      return 'This prayer time is not available';
    }
    final rawOff = int.tryParse(_offCtrl.text) ?? 0;
    final clampedOff = rawOff.clamp(0, 180) * _dir;
    final ringMin = ((prayerMin + clampedOff) % 1440 + 1440) % 1440;
    return 'Today it rings at ${formatHm(ringMin, h24: ctrl.is24Hour)}  (${prayerNames[ptIdx]} is at ${formatHm(prayerMin, h24: ctrl.is24Hour)})';
  }

  /// `function eSave()` (lines 1662-1694).
  Future<void> _onSave(ClockController ctrl) async {
    final idx = ctrl.editingAlarmIndex;
    if (idx < 0) return;

    final timeParts =
        (_timeCtrl.text.isNotEmpty ? _timeCtrl.text : '07:00').split(':');
    final int hour = timeParts.isNotEmpty ? (int.tryParse(timeParts[0]) ?? 0) : 0;
    final int min = timeParts.length > 1 ? (int.tryParse(timeParts[1]) ?? 0) : 0;

    int daysMask = 0;
    for (int d = 0; d < 7; d++) {
      if (_days[d]) daysMask |= (1 << d);
    }

    final offVal = (int.tryParse(_offCtrl.text) ?? 0).clamp(0, 180) * _dir;
    final payload = <String, dynamic>{
      'i': idx,
      'on': 1,
      'label': _lblCtrl.text.trim(),
      'hour': hour,
      'min': min,
      'days': daysMask,
      'rel': _mode,
      'offset': _mode >= 0 ? offVal : 0,
      'ram': _ram ? 1 : 0,
      'useDate': _useDate ? 1 : 0,
      'sound': _sound,
      'vol': _vol,
    };

    if (_useDate) {
      final p = _dateCtrl.text.trim().split('-');
      if (p.length != 3) {
        ctrl.showMsg('Choose a date');
        return;
      }
      final year = int.tryParse(p[0]);
      final month = int.tryParse(p[1]);
      final day = int.tryParse(p[2]);
      if (year == null || month == null || day == null) {
        ctrl.showMsg('Choose a date');
        return;
      }
      if (year < 2000 || year > 2099) {
        ctrl.showMsg('Alarm date must be between 2000 and 2099');
        return;
      }
      payload['year'] = year;
      payload['month'] = month;
      payload['day'] = day;
    }

    await ctrl.saveAlarm(payload);
  }

  Future<void> _onDelete(ClockController ctrl) async {
    final idx = ctrl.editingAlarmIndex;
    if (idx < 0) return;
    final confirmed = await showP4ConfirmDialog(
      context,
      title: 'Delete alarm',
      message: 'Delete alarm ${idx + 1}?',
      confirmLabel: 'Delete',
    );
    if (confirmed) {
      await ctrl.deleteEditingAlarm();
    }
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<ClockController>();
    final alarms = ctrl.rawAlarms;
    final onCount =
        alarms.where((x) => x['on'] == true || x['on'] == 1).length;

    final editIdx = ctrl.editingAlarmIndex;
    if (editIdx >= 0 &&
        editIdx < alarms.length &&
        _loadedAlarmIdx != editIdx) {
      _populateEditorFromAlarm(editIdx, alarms[editIdx]);
    } else if (editIdx < 0) {
      _loadedAlarmIdx = -1;
    }

    // Match sound dropdown options (`loadSounds`, lines 1596-1612)
    final soundOptions = <String>['', ...ctrl.alarmSounds];
    String effectiveSound = '';
    if (soundOptions.contains(_sound)) {
      effectiveSound = _sound;
    } else if (_sound.isNotEmpty) {
      final wantBase = baseName(_sound).toLowerCase();
      final match = soundOptions.firstWhere(
        (s) => s.isNotEmpty && baseName(s).toLowerCase() == wantBase,
        orElse: () => '',
      );
      effectiveSound = match;
    }

    final previewText = _computeRelativePreview(ctrl);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        P4Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '🔔 Alarms',
                style: TextStyle(
                  color: P4Colors.teal,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Tap an alarm to edit it. $onCount of ${alarms.length} alarms on.',
                key: const Key('alarms_count_text'),
                style: const TextStyle(color: P4Colors.dim, fontSize: 14),
              ),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 360),
                child: ListView.builder(
                  shrinkWrap: true,
                  physics: const ClampingScrollPhysics(),
                  itemCount: alarms.length,
                  itemBuilder: (ctx, i) {
                    final x = alarms[i];
                    final isOn = x['on'] == true || x['on'] == 1;
                    final tStr = x['t']?.toString() ?? '--:--';
                    final lbl = x['l']?.toString() ?? '';
                    final desc = x['d']?.toString() ?? '';
                    return Container(
                      key: Key('alarm_row_$i'),
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
                        children: [
                          Checkbox(
                            key: Key('alarm_cb_$i'),
                            value: isOn,
                            onChanged: (v) =>
                                ctrl.toggleAlarm(i, v ?? false),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: InkWell(
                              key: Key('alarm_tap_$i'),
                              onTap: () => ctrl.openAlarmEditor(i),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '$tStr   $lbl',
                                    style: const TextStyle(
                                      color: P4Colors.text,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                    ),
                                  ),
                                  if (desc.isNotEmpty)
                                    Text(
                                      desc,
                                      style: const TextStyle(
                                        color: P4Colors.dim,
                                        fontSize: 13,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        if (editIdx >= 0)
          P4Card(
            key: const Key('alarm_edit_card'),
            borderColor: P4Colors.teal,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Edit alarm #${editIdx + 1}',
                  key: const Key('alarm_edit_heading'),
                  style: const TextStyle(
                    color: P4Colors.teal,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                P4FieldRow(
                  label: const Text('Title'),
                  control: TextField(
                    key: const Key('alarm_edit_title'),
                    controller: _lblCtrl,
                    maxLength: 30,
                    decoration: const InputDecoration(
                      hintText: 'e.g. Suhoor',
                      counterText: '',
                    ),
                  ),
                ),
                P4FieldRow(
                  label: const Text('When'),
                  control: DropdownButtonFormField<int>(
                    key: const Key('alarm_edit_mode'),
                    initialValue: _mode,
                    isExpanded: true,
                    items: const [
                      DropdownMenuItem(value: -1, child: Text('Fixed time')),
                      DropdownMenuItem(
                        value: 0,
                        child: Text('Before / after Fajr'),
                      ),
                      DropdownMenuItem(
                        value: 1,
                        child: Text('Before / after Dhuhr'),
                      ),
                      DropdownMenuItem(
                        value: 2,
                        child: Text('Before / after Maghrib'),
                      ),
                    ],
                    onChanged: (v) {
                      if (v != null) {
                        setState(() => _mode = v);
                      }
                    },
                  ),
                ),
                if (_mode < 0)
                  P4FieldRow(
                    label: const Text('Time'),
                    control: TextField(
                      key: const Key('alarm_edit_time'),
                      controller: _timeCtrl,
                      decoration: const InputDecoration(hintText: 'HH:MM'),
                    ),
                  )
                else ...[
                  P4FieldRow(
                    label: const Text('Before / after'),
                    control: DropdownButtonFormField<int>(
                      key: const Key('alarm_edit_dir'),
                      initialValue: _dir,
                      isExpanded: true,
                      items: const [
                        DropdownMenuItem(value: -1, child: Text('Before')),
                        DropdownMenuItem(value: 1, child: Text('After')),
                      ],
                      onChanged: (v) {
                        if (v != null) {
                          setState(() => _dir = v);
                        }
                      },
                    ),
                  ),
                  P4FieldRow(
                    label: const Text('Minutes (0-180)'),
                    control: TextField(
                      key: const Key('alarm_edit_offset'),
                      controller: _offCtrl,
                      keyboardType: TextInputType.number,
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ],
                if (previewText.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      previewText,
                      key: const Key('alarm_edit_preview'),
                      style: const TextStyle(
                        color: P4Colors.amber,
                        fontSize: 14,
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                const Text(
                  'Repeat on (none selected = ring once)',
                  style: TextStyle(
                    color: P4Colors.dim,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 10,
                  runSpacing: 4,
                  children: List<Widget>.generate(7, (d) {
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Checkbox(
                          key: Key('alarm_day_$d'),
                          value: _days[d],
                          onChanged: (v) {
                            setState(() => _days[d] = v ?? false);
                          },
                        ),
                        Text(dayNames[d]),
                      ],
                    );
                  }),
                ),
                P4FieldRow(
                  label: const Text('Ramadan only (works with the days)'),
                  control: Checkbox(
                    key: const Key('alarm_edit_ramadan'),
                    value: _ram,
                    onChanged: (v) {
                      setState(() {
                        _ram = v ?? false;
                        if (_ram) _useDate = false;
                      });
                    },
                  ),
                ),
                P4FieldRow(
                  label: const Text('Specific date (ignores days + Ramadan)'),
                  control: Checkbox(
                    key: const Key('alarm_edit_usedate'),
                    value: _useDate,
                    onChanged: (v) {
                      setState(() {
                        _useDate = v ?? false;
                        if (_useDate) _ram = false;
                      });
                    },
                  ),
                ),
                if (_useDate)
                  P4FieldRow(
                    label: const Text('Date'),
                    control: TextField(
                      key: const Key('alarm_edit_date'),
                      controller: _dateCtrl,
                      decoration: const InputDecoration(
                        hintText: 'YYYY-MM-DD',
                      ),
                    ),
                  ),
                P4FieldRow(
                  label: const Text('Sound (/alarms)'),
                  control: DropdownButtonFormField<String>(
                    key: const Key('alarm_edit_sound'),
                    initialValue: effectiveSound,
                    isExpanded: true,
                    items: [
                      const DropdownMenuItem(
                        value: '',
                        child: Text('Default (alarm.mp3)'),
                      ),
                      ...ctrl.alarmSounds.map(
                        (s) => DropdownMenuItem(
                          value: s,
                          child: Text(
                            baseName(s),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                    onChanged: (v) {
                      if (v != null) {
                        setState(() => _sound = v);
                      }
                    },
                  ),
                ),
                P4FieldRow(
                  label: Text('Volume $_vol'),
                  control: Slider(
                    key: const Key('alarm_edit_vol'),
                    min: 0,
                    max: 21,
                    divisions: 21,
                    value: _vol.toDouble(),
                    onChanged: (v) {
                      final nextVol = v.round();
                      setState(() => _vol = nextVol);
                      ctrl.setAlarmTestVolumeDebounced(nextVol);
                    },
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    P4Button(
                      key: const Key('btn_alarm_test'),
                      label: '▶ Test',
                      small: true,
                      onPressed: () => ctrl.testAlarmPlay(effectiveSound, _vol),
                    ),
                    const SizedBox(width: 8),
                    P4Button(
                      key: const Key('btn_alarm_stop'),
                      label: '■ Stop',
                      small: true,
                      color: P4Colors.slate,
                      onPressed: ctrl.testAlarmStop,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    P4Button(
                      key: const Key('btn_alarm_save'),
                      label: '✔ Save',
                      onPressed: () => _onSave(ctrl),
                    ),
                    P4Button(
                      key: const Key('btn_alarm_cancel'),
                      label: 'Cancel',
                      color: P4Colors.slate,
                      onPressed: ctrl.closeAlarmEditor,
                    ),
                    P4Button(
                      key: const Key('btn_alarm_delete'),
                      label: '🗑 Delete',
                      color: P4Colors.red,
                      onPressed: () => _onDelete(ctrl),
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


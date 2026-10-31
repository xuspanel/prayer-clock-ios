import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/clock_controller.dart';
import '../theme/p4_theme.dart';

/// Tab 4: Location (`#t-loc`, lines 269-292 & 1363-1453).
class LocationTab extends StatefulWidget {
  const LocationTab({super.key});

  @override
  State<LocationTab> createState() => _LocationTabState();
}

class _LocationTabState extends State<LocationTab> {
  int _syncedVersion = -1;

  final TextEditingController _searchCtrl = TextEditingController();
  final TextEditingController _cityCtrl = TextEditingController();
  final TextEditingController _latCtrl = TextEditingController();
  final TextEditingController _lonCtrl = TextEditingController();
  int _tzSel = 0;
  final TextEditingController _tzValCtrl = TextEditingController();
  bool _saveCity = true;

  @override
  void dispose() {
    _searchCtrl.dispose();
    _cityCtrl.dispose();
    _latCtrl.dispose();
    _lonCtrl.dispose();
    _tzValCtrl.dispose();
    super.dispose();
  }

  void _syncFromSettings(ClockController ctrl) {
    final d = ctrl.setD;
    if (d == null) return;
    if (ctrl.dirtyLoc && _syncedVersion >= 0) return;
    _syncedVersion = ctrl.settingsFormVersion;

    _cityCtrl.text = d['city']?.toString() ?? '';
    final lat = double.tryParse(d['lat']?.toString() ?? '0') ?? 0.0;
    final lon = double.tryParse(d['lon']?.toString() ?? '0') ?? 0.0;
    _latCtrl.text = lat.toStringAsFixed(4);
    _lonCtrl.text = lon.toStringAsFixed(4);
    _tzSel = (d['tzsel'] is num) ? (d['tzsel'] as num).toInt() : 0;
    _tzValCtrl.text = d['tzval']?.toString() ?? '';
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<ClockController>();
    if (_syncedVersion != ctrl.settingsFormVersion) {
      _syncFromSettings(ctrl);
    }

    final d = ctrl.setD;
    final double curLat = double.tryParse(d?['lat']?.toString() ?? '0') ?? 0.0;
    final double curLon = double.tryParse(d?['lon']?.toString() ?? '0') ?? 0.0;
    final String locSummary = d != null
        ? 'Now: ${d['city'] ?? ''}   ${curLat.toStringAsFixed(4)}, ${curLon.toStringAsFixed(4)}   |   ${d['tz'] ?? ''}'
        : '';

    final ntz = ctrl.tzList.length;
    final tzOptions = <DropdownMenuItem<int>>[
      ...List<DropdownMenuItem<int>>.generate(
        ntz,
        (i) => DropdownMenuItem(
          value: i,
          child: Text(ctrl.tzList[i], overflow: TextOverflow.ellipsis),
        ),
      ),
      DropdownMenuItem(value: ntz, child: const Text('Custom UTC offset')),
      DropdownMenuItem(value: ntz + 1, child: const Text('Custom POSIX rule')),
    ];
    final effectiveTzSel =
        (_tzSel >= 0 && _tzSel <= ntz + 1) ? _tzSel : 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        P4Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '📍 Location',
                style: TextStyle(
                  color: P4Colors.teal,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (locSummary.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 8),
                  child: Text(
                    locSummary,
                    style: const TextStyle(color: P4Colors.dim, fontSize: 14),
                  ),
                ),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const Key('input_city_query'),
                      controller: _searchCtrl,
                      decoration: const InputDecoration(hintText: 'City name'),
                      onSubmitted: (q) => ctrl.searchCities(q),
                    ),
                  ),
                  const SizedBox(width: 6),
                  P4Button(
                    key: const Key('btn_city_list'),
                    label: '☰ List',
                    small: true,
                    onPressed: () => ctrl.searchCities(_searchCtrl.text),
                  ),
                  const SizedBox(width: 6),
                  P4Button(
                    key: const Key('btn_city_online'),
                    label: '🌐 Online',
                    small: true,
                    onPressed: () => ctrl.startOnlineGeo(_searchCtrl.text),
                  ),
                ],
              ),
              if (ctrl.citySearchMessage.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    ctrl.citySearchMessage,
                    style: const TextStyle(color: P4Colors.amber, fontSize: 14),
                  ),
                ),
              if (ctrl.cityResults.isNotEmpty)
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 280),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: ctrl.cityResults.length,
                    itemBuilder: (ctx, i) {
                      final x = ctrl.cityResults[i];
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
                          children: [
                            Expanded(
                              child: InkWell(
                                onTap: () => ctrl.useCity(x.name),
                                child: Text(
                                  '${x.name}   ${x.lat.toStringAsFixed(4)}, ${x.lon.toStringAsFixed(4)}   ${x.tz}',
                                  style: const TextStyle(color: P4Colors.text),
                                ),
                              ),
                            ),
                            P4Button(
                              label: '🗑',
                              small: true,
                              color: P4Colors.red,
                              onPressed: () async {
                                final ok = await showP4ConfirmDialog(
                                  context,
                                  title: 'Delete city',
                                  message:
                                      'Delete "${x.name}" from the cities list?',
                                  confirmLabel: 'Delete',
                                );
                                if (ok) {
                                  await ctrl.deleteCity(
                                    x.name,
                                    _searchCtrl.text,
                                  );
                                }
                              },
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              if (ctrl.geoResults.isNotEmpty)
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 280),
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      ...List<Widget>.generate(ctrl.geoResults.length, (i) {
                        final r = ctrl.geoResults[i];
                        return InkWell(
                          onTap: () => ctrl.useOnlineGeo(i),
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
                              '${r.label}   ${r.lat.toStringAsFixed(4)}, ${r.lon.toStringAsFixed(4)}   ${r.tz}',
                              style: const TextStyle(color: P4Colors.text),
                            ),
                          ),
                        );
                      }),
                      InkWell(
                        onTap: ctrl.cancelOnlineGeo,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            vertical: 10,
                            horizontal: 4,
                          ),
                          child: const Text(
                            '✕ Cancel',
                            style: TextStyle(color: P4Colors.amber),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 14),
              const Text(
                'Or enter it yourself',
                style: TextStyle(
                  color: P4Colors.dim,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              P4FieldRow(
                label: const Text('City name'),
                control: TextField(
                  controller: _cityCtrl,
                  maxLength: 31,
                  decoration: const InputDecoration(counterText: ''),
                  onChanged: (_) => ctrl.dirtyLoc = true,
                ),
              ),
              P4FieldRow(
                label: const Text('Latitude (South -)'),
                control: TextField(
                  controller: _latCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  ),
                  onChanged: (_) => ctrl.dirtyLoc = true,
                ),
              ),
              P4FieldRow(
                label: const Text('Longitude (West -)'),
                control: TextField(
                  controller: _lonCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  ),
                  onChanged: (_) => ctrl.dirtyLoc = true,
                ),
              ),
              P4FieldRow(
                label: const Text('Time zone'),
                control: DropdownButtonFormField<int>(
                  initialValue: effectiveTzSel,
                  isExpanded: true,
                  items: tzOptions,
                  onChanged: (v) {
                    if (v != null) {
                      setState(() {
                        ctrl.dirtyLoc = true;
                        _tzSel = v;
                      });
                    }
                  },
                ),
              ),
              if (effectiveTzSel >= ntz)
                P4FieldRow(
                  label: Text(
                    effectiveTzSel == ntz
                        ? 'UTC offset (e.g. +3, -5:30)'
                        : 'POSIX rule',
                  ),
                  control: TextField(
                    controller: _tzValCtrl,
                    onChanged: (_) => ctrl.dirtyLoc = true,
                  ),
                ),
              P4FieldRow(
                label: const Text('Also save in the cities list'),
                control: Checkbox(
                  value: _saveCity,
                  onChanged: (v) => setState(() => _saveCity = v ?? true),
                ),
              ),
              const SizedBox(height: 10),
              Center(
                child: P4Button(
                  key: const Key('btn_save_location'),
                  label: '✔ Save location',
                  onPressed: () => ctrl.saveLocationSettings(
                    city: _cityCtrl.text,
                    lat: _latCtrl.text,
                    lon: _lonCtrl.text,
                    tzsel: effectiveTzSel,
                    tzval: _tzValCtrl.text,
                    savecity: _saveCity,
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


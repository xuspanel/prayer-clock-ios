import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/clock_controller.dart';
import 'tabs/alarms_tab.dart';
import 'tabs/files_tab.dart';
import 'tabs/location_tab.dart';
import 'tabs/prayer_tab.dart';
import 'tabs/remote_tab.dart';
import 'tabs/settings_tab.dart';
import 'tabs/system_tab.dart';
import 'tabs/wifi_tab.dart';
import 'theme/p4_theme.dart';
import 'widgets/connection_card.dart';
import 'widgets/pin_overlay.dart';

const List<String> _tabLabels = <String>[
  'Remote',
  'Prayer',
  'Alarms',
  'Location',
  'Settings',
  'WiFi',
  'Files',
  'System',
];

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final ctrl = context.read<ClockController>();
    final isForeground = state == AppLifecycleState.resumed;
    ctrl.onAppLifecycleChanged(isForeground);
  }

  String _buildClockLine(Map<String, dynamic>? d) {
    if (d == null) return '--:--';
    final clock = d['clock']?.toString();
    final base = (clock != null && clock.isNotEmpty)
        ? clock
        : 'Board clock not set';
    final date = d['date']?.toString() ?? '';
    final hijri = d['hijri']?.toString() ?? '';
    final bat = (d['bat'] is num) ? (d['bat'] as num).toInt() : -1;
    final wifi = d['wifi']?.toString() ?? '';

    final buf = StringBuffer(base);
    if (date.isNotEmpty) buf.write('  •  $date');
    if (hijri.isNotEmpty) buf.write('  •  $hijri');
    if (bat >= 0) buf.write('  •  🔋$bat%');
    if (wifi.isNotEmpty) buf.write('  •  📶 $wifi');
    return buf.toString();
  }

  Widget _buildActiveTab(int index) {
    switch (index) {
      case 0:
        return const RemoteTab();
      case 1:
        return const PrayerTab();
      case 2:
        return const AlarmsTab();
      case 3:
        return const LocationTab();
      case 4:
        return const SettingsTab();
      case 5:
        return const WifiTab();
      case 6:
        return const FilesTab();
      case 7:
        return const SystemTab();
      default:
        return const RemoteTab();
    }
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<ClockController>();
    final st = ctrl.lastSt;

    final clockLine = _buildClockLine(st);
    final nextStr = st?['next']?.toString() ?? '';
    final src = st?['src']?.toString() ?? 'none';
    final isTest = st?['test'] == true || st?['test'] == 1;
    final isAlarmActive = (src == 'alarm' || src == 'azan') && !isTest;
    final activeTitle = st?['title']?.toString() ?? '';
    final snoozeStr = st?['snooze']?.toString() ?? '';
    final isSnoozed = snoozeStr.isNotEmpty && !isAlarmActive;

    return Scaffold(
      backgroundColor: P4Colors.bg,
      body: Stack(
        children: [
          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: Column(
                  children: [
                    // Sticky top message banner (#msg)
                    if (ctrl.toastMessage.isNotEmpty)
                      Container(
                        key: const Key('toast_banner'),
                        width: double.infinity,
                        color: P4Colors.bg,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                ctrl.toastMessage,
                                style: const TextStyle(
                                  color: P4Colors.amber,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.close,
                                size: 18,
                                color: P4Colors.dim,
                              ),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              onPressed: ctrl.dismissMsg,
                            ),
                          ],
                        ),
                      ),
                    if (ctrl.lifecycleBanner.isNotEmpty)
                      Container(
                        key: const Key('lifecycle_banner'),
                        width: double.infinity,
                        color: P4Colors.tabBarBg,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                ctrl.lifecycleBanner,
                                style: const TextStyle(
                                  color: P4Colors.amber,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.close,
                                size: 16,
                                color: P4Colors.dim,
                              ),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              onPressed: ctrl.dismissLifecycleBanner,
                            ),
                          ],
                        ),
                      ),
                    Expanded(
                      child: SingleChildScrollView(
                        key: const Key('main_vertical_scroll'),
                        padding: EdgeInsets.only(
                          left: 12,
                          right: 12,
                          top: 8,
                          bottom: MediaQuery.of(context).viewInsets.bottom + 24,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              ctrl.headingTitle,
                              key: const Key('app_heading'),
                              style: const TextStyle(
                                color: P4Colors.teal,
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            const ConnectionCard(),
                            const SizedBox(height: 4),
                            Text(
                              clockLine,
                              key: const Key('status_clock_line'),
                              style: const TextStyle(
                                color: P4Colors.dim,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 2),
                            SizedBox(
                              height: 20,
                              child: Text(
                                nextStr.isNotEmpty ? 'Next: $nextStr' : '',
                                key: const Key('status_next_line'),
                                style: const TextStyle(
                                  color: P4Colors.amber,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                            if (ctrl.boardUnreachable)
                              const Padding(
                                padding: EdgeInsets.only(bottom: 6),
                                child: Text(
                                  'Board not reachable...',
                                  key: Key('error_unreachable'),
                                  style: TextStyle(
                                    color: P4Colors.red,
                                    fontSize: 14,
                                  ),
                                ),
                              ),

                            // Active alarm / azan banner (#alarm)
                            if (isAlarmActive)
                              P4Card(
                                key: const Key('active_alarm_card'),
                                borderColor: P4Colors.amber,
                                borderWidth: 3,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${src == 'alarm' ? '🔔 Alarm: ' : '🕌 Azan: '}$activeTitle',
                                      style: const TextStyle(
                                        color: P4Colors.amber,
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        if (src == 'alarm') ...[
                                          P4Button(
                                            key: const Key('btn_alarm_snooze'),
                                            label: 'Snooze',
                                            color: P4Colors.orange,
                                            onPressed: () =>
                                                ctrl.sendCmd('snooze'),
                                          ),
                                          const SizedBox(width: 8),
                                        ],
                                        P4Button(
                                          key: const Key(
                                            'btn_active_alarm_stop',
                                          ),
                                          label: '■ Stop',
                                          color: P4Colors.red,
                                          onPressed: () => ctrl.sendCmd('stop'),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),

                            // Snooze banner (#sn)
                            if (isSnoozed)
                              P4Card(
                                key: const Key('snooze_card'),
                                borderColor: P4Colors.orange,
                                borderWidth: 2,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '🔔 Snoozed until $snoozeStr',
                                      style: const TextStyle(
                                        color: P4Colors.amber,
                                        fontSize: 15,
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    Center(
                                      child: P4Button(
                                        key: const Key('btn_cancel_snooze'),
                                        label: 'Cancel snooze',
                                        color: P4Colors.red,
                                        onPressed: () =>
                                            ctrl.sendCmd('nosnooze'),
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                            // Horizontal tab bar (.tabs)
                            Container(
                              margin: const EdgeInsets.symmetric(vertical: 8),
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: P4Colors.tabBarBg,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                  children: List<Widget>.generate(
                                    _tabLabels.length,
                                    (i) {
                                      final active =
                                          i == ctrl.activeTabIndex;
                                      return Padding(
                                        padding: EdgeInsets.only(
                                          right: i < _tabLabels.length - 1
                                              ? 4
                                              : 0,
                                        ),
                                        child: InkWell(
                                          key: Key('tab_btn_$i'),
                                          borderRadius:
                                              BorderRadius.circular(8),
                                          onTap: () => ctrl.switchTab(i),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 8,
                                            ),
                                            decoration: BoxDecoration(
                                              color: active
                                                  ? P4Colors.teal
                                                  : P4Colors.card,
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            child: Text(
                                              _tabLabels[i],
                                              style: TextStyle(
                                                color: active
                                                    ? Colors.white
                                                    : P4Colors.dim,
                                                fontSize: 15,
                                                fontWeight: active
                                                    ? FontWeight.bold
                                                    : FontWeight.normal,
                                              ),
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ),
                            ),

                            // Active tab pane
                            _buildActiveTab(ctrl.activeTabIndex),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const PinOverlay(),
        ],
      ),
    );
  }
}


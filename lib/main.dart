import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'state/clock_controller.dart';
import 'ui/home_shell.dart';
import 'ui/theme/p4_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = ClockController();
  controller.initialize();
  runApp(PrayerClockApp(controller: controller));
}

class PrayerClockApp extends StatelessWidget {
  final ClockController controller;

  const PrayerClockApp({
    super.key,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<ClockController>.value(
      value: controller,
      child: MaterialApp(
        title: 'Prayer Clock Remote',
        debugShowCheckedModeBanner: false,
        theme: buildP4Theme(),
        home: const HomeShell(),
      ),
    );
  }
}

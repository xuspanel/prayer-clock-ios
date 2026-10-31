import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Handles foreground local notifications when the P4 board fires an Alarm or Azan
/// while the app is open (§2.4).
///
/// Never requests notification permission at app launch; requests permission only
/// when an alarm/azan event actually occurs or when explicitly triggered by the user.
class NotificationService {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  bool _permissionRequested = false;

  Future<void> _ensureInitializedAndPermitted() async {
    if (kIsWeb) return;
    if (!_initialized) {
      const darwinSettings = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );
      const linuxSettings = LinuxInitializationSettings(
        defaultActionName: 'Open',
      );
      const initSettings = InitializationSettings(
        iOS: darwinSettings,
        macOS: darwinSettings,
        linux: linuxSettings,
      );
      try {
        await _plugin.initialize(initSettings);
        _initialized = true;
      } catch (_) {
        return;
      }
    }

    if (!_permissionRequested) {
      _permissionRequested = true;
      try {
        final iosImpl = _plugin.resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>();
        await iosImpl?.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        );
      } catch (_) {}
    }
  }

  Future<void> showBoardEventNotification({
    required bool isAlarm,
    required String title,
  }) async {
    if (kIsWeb) return;
    await _ensureInitializedAndPermitted();
    if (!_initialized) return;

    const darwinDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: false,
      presentSound: true,
    );
    const details = NotificationDetails(
      iOS: darwinDetails,
      macOS: darwinDetails,
    );

    final heading = isAlarm ? '🔔 Prayer Clock Alarm' : '🕌 Prayer Clock Azan';
    try {
      await _plugin.show(
        isAlarm ? 1001 : 1002,
        heading,
        title.isNotEmpty ? title : (isAlarm ? 'Alarm ringing on board' : 'Azan playing on board'),
        details,
      );
    } catch (_) {}
  }
}


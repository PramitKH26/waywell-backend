import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// Local notification service. Owns:
///   • A scheduled "daily check-in" reminder at a user-chosen time.
///   • A persistent (ongoing) "Safe Space" shortcut sitting in the tray.
///
/// Notification tap routing is handled by [pendingLaunchPayload] which is set
/// from the cold-start details in main(), and from [_onTap] for warm taps.
/// MainShell reads it via [consumeLaunchPayload].
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static const int    _checkInId         = 1001;
  static const int    _panicId           = 1002;
  static const String _timeKeyHour       = 'checkin_notification_hour';
  static const String _timeKeyMinute     = 'checkin_notification_minute';
  static const String _enabledKey        = 'checkin_notification_enabled';
  static const String _panicEnabledKey   = 'panic_shortcut_enabled';

  /// Set from a tap on a notification (warm) OR from the cold-start launch
  /// details. Consumed by MainShell after it builds.
  String? pendingLaunchPayload;

  /// Listener used by MainShell to react to warm-taps that arrive while the
  /// app is already running.
  void Function(String payload)? onWarmTap;

  Future<void> initialize() async {
    tz_data.initializeTimeZones();
    try {
      tz.setLocalLocation(tz.getLocation('Asia/Kolkata'));
    } catch (_) {
      // Fallback if tz database doesn't have it for some reason.
    }

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    await _plugin.initialize(
      const InitializationSettings(android: android, iOS: ios),
      onDidReceiveNotificationResponse: _onTap,
    );

    await _createChannels();
  }

  Future<void> _createChannels() async {
    const checkIn = AndroidNotificationChannel(
      'waywell_checkin',
      'Daily Check-in',
      description: 'Daily wellbeing check-in from Waywell',
      importance: Importance.high,
    );
    const panic = AndroidNotificationChannel(
      'waywell_panic',
      'Safe Space Access',
      description: 'Quick access to Safe Space',
      importance: Importance.low,
    );
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(checkIn);
    await android?.createNotificationChannel(panic);
  }

  void _onTap(NotificationResponse r) {
    final p = r.payload;
    if (p == null) return;
    pendingLaunchPayload = p;
    onWarmTap?.call(p);
  }

  /// Cold-start: read the payload of the notification that launched the app.
  Future<void> loadColdStartPayload() async {
    final details = await _plugin.getNotificationAppLaunchDetails();
    if (details?.didNotificationLaunchApp == true) {
      pendingLaunchPayload = details?.notificationResponse?.payload;
    }
  }

  /// Read and clear the pending payload. Returns null if nothing pending.
  String? consumeLaunchPayload() {
    final p = pendingLaunchPayload;
    pendingLaunchPayload = null;
    return p;
  }

  // ── Permission ─────────────────────────────────────────────────────────────

  Future<bool> requestPermission() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    final granted = await android?.requestNotificationsPermission();
    return granted ?? false;
  }

  // ── Daily check-in ─────────────────────────────────────────────────────────

  Future<void> scheduleCheckIn(int hour, int minute) async {
    await _plugin.cancel(_checkInId);

    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(
      tz.local, now.year, now.month, now.day, hour, minute,
    );
    if (!scheduled.isAfter(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }

    try {
      await _plugin.zonedSchedule(
        _checkInId,
        'Hey, how are you doing? 🌿',
        'Take a moment. Your companion is here.',
        scheduled,
        NotificationDetails(
          android: AndroidNotificationDetails(
            'waywell_checkin',
            'Daily Check-in',
            channelDescription: 'Daily wellbeing check-in',
            importance: Importance.high,
            priority:   Priority.high,
            icon:       '@mipmap/ic_launcher',
            color:      const Color(0xFF4A7C59),
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentSound: true,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        payload: 'checkin',
      );
    } catch (e) {
      // Devices without exact-alarm permission fall back to inexact.
      debugPrint('[NotificationService] exact schedule failed: $e — '
          'falling back to inexact');
      await _plugin.zonedSchedule(
        _checkInId,
        'Hey, how are you doing? 🌿',
        'Take a moment. Your companion is here.',
        scheduled,
        NotificationDetails(
          android: AndroidNotificationDetails(
            'waywell_checkin',
            'Daily Check-in',
            channelDescription: 'Daily wellbeing check-in',
            importance: Importance.high,
            priority:   Priority.high,
            icon:       '@mipmap/ic_launcher',
            color:      const Color(0xFF4A7C59),
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        payload: 'checkin',
      );
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_timeKeyHour,   hour);
    await prefs.setInt(_timeKeyMinute, minute);
    await prefs.setBool(_enabledKey,   true);
  }

  Future<void> cancelCheckIn() async {
    await _plugin.cancel(_checkInId);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, false);
  }

  /// Returns {enabled, hour, minute}. Defaults: off, 20:00.
  Future<Map<String, dynamic>> getCheckInSettings() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'enabled': prefs.getBool(_enabledKey) ?? false,
      'hour':    prefs.getInt(_timeKeyHour)   ?? 20,
      'minute':  prefs.getInt(_timeKeyMinute) ?? 0,
    };
  }

  // ── Safe Space persistent shortcut ─────────────────────────────────────────

  Future<bool> isPanicShortcutEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_panicEnabledKey) ?? true;
  }

  Future<void> setPanicShortcutEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_panicEnabledKey, enabled);
    if (enabled) {
      await showPanicShortcut();
    } else {
      await hidePanicShortcut();
    }
  }

  Future<void> showPanicShortcut() async {
    await _plugin.show(
      _panicId,
      'Your Safe Space is here 🌿',
      'Breathing and grounding, whenever you need it.',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'waywell_panic',
          'Safe Space Access',
          channelDescription: 'Quick access to Safe Space',
          importance: Importance.low,
          priority:   Priority.low,
          ongoing:    true,
          autoCancel: false,
          icon:       '@mipmap/ic_launcher',
          color:      Color(0xFF1A2530),
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: false,
        ),
      ),
      payload: 'panic',
    );
  }

  Future<void> hidePanicShortcut() async {
    await _plugin.cancel(_panicId);
  }
}

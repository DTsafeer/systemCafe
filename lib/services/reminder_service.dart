import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform;
import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../pages/NotificationService.dart';

class ReminderService {
  static final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();
  
  static List<Map<String, dynamic>> _webTasks = [];
  static Timer? _webHeartbeat;

  static Future<void> init() async {
    tz_data.initializeTimeZones();
    
    try {
      if (!kIsWeb) {
        final String timeZoneName = await FlutterTimezone.getLocalTimezone();
        tz.setLocalLocation(tz.getLocation(timeZoneName));
      }
    } catch (e) {
      debugPrint("TimeZone Error: $e");
    }

    if (kIsWeb) {
      await _loadPersistedWebTasks();
      _startWebHeartbeat();
      return;
    }

    const AndroidInitializationSettings initializationSettingsAndroid = 
        AndroidInitializationSettings('@mipmap/ic_launcher');
    
    final InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: const DarwinInitializationSettings(),
    );

    await _notificationsPlugin.initialize(initializationSettings);
  }

  static void _startWebHeartbeat() {
    _webBackgroundPulse();
    _webHeartbeat?.cancel();
    _webHeartbeat = Timer.periodic(const Duration(seconds: 30), (timer) {
      _webBackgroundPulse();
    });
  }

  static void _webBackgroundPulse() {
    if (!kIsWeb) return;
    
    final now = DateTime.now();
    bool updated = false;

    for (var i = _webTasks.length - 1; i >= 0; i--) {
      final task = _webTasks[i];
      final scheduledDate = DateTime.parse(task['nextDate']);
      
      if (now.isAfter(scheduledDate)) {
        _showInstantNotification(task['title'], task['body']);
        final nextWeek = scheduledDate.add(const Duration(days: 7));
        _webTasks[i]['nextDate'] = nextWeek.toIso8601String();
        updated = true;
      }
    }

    if (updated) _saveWebTasks();
  }

  static Future<void> _saveWebTasks() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('web_reminders_v3', jsonEncode(_webTasks));
  }

  static Future<void> _loadPersistedWebTasks() async {
    final prefs = await SharedPreferences.getInstance();
    final String? data = prefs.getString('web_reminders_v3');
    if (data != null) {
      _webTasks = List<Map<String, dynamic>>.from(jsonDecode(data));
    }
  }

  static Future<bool> hasExactAlarmPermission() async {
    if (kIsWeb) return true;
    if (defaultTargetPlatform == TargetPlatform.android) {
      try {
        final androidImplementation = _notificationsPlugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
        if (androidImplementation != null) {
          // استخدام dynamic لتجاوز خطأ التحقق من وجود الدالة أثناء التجميع
          return await (androidImplementation as dynamic).canScheduleExactAlarms() ?? false;
        }
      } catch (e) {
        return true; 
      }
    }
    return true;
  }

  static Future<void> requestExactAlarmPermission() async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      final androidImplementation = _notificationsPlugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (androidImplementation != null) {
        // استخدام dynamic لتجاوز خطأ التحقق من وجود الدالة أثناء التجميع
        await (androidImplementation as dynamic).requestExactAlarmsPermission();
      }
    }
  }

  static Future<void> showTestNow() async {
    if (kIsWeb) {
      NotificationBell.showLocalHint("⚙️ تجربة", "سيظهر التنبيه خلال 5 ثوانٍ...");
    }
    Timer(const Duration(seconds: 5), () {
      _showInstantNotification("⏰ تجربة ناجحة", "نظام التنبيهات يعمل!");
    });
  }

  static Future<void> _showInstantNotification(String title, String body) async {
    if (kIsWeb) {
      NotificationBell.showLocalHint(title, body);
      return;
    }
    await _notificationsPlugin.show(
      DateTime.now().millisecond % 10000,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'reminders_channel', 
          'Reminders', 
          importance: Importance.max, 
          priority: Priority.high,
          playSound: true,
        ),
      ),
    );
  }

  static Future<void> scheduleNotification({
    required int id,
    required String title,
    required String body,
    required TimeOfDay time,
    required List<int> days,
  }) async {
    if (kIsWeb) {
      for (int day in days) {
        DateTime nextDate = _calculateNextLocalInstance(day, time);
        String taskId = "${id}_$day";
        _webTasks.removeWhere((t) => t['id'] == taskId);
        _webTasks.add({
          'id': taskId,
          'title': title,
          'body': body,
          'nextDate': nextDate.toIso8601String(),
          'day': day,
        });
      }
      await _saveWebTasks();
      return;
    }

    for (int day in days) {
      await _notificationsPlugin.zonedSchedule(
        (id.abs() % 100000) * 10 + day,
        title,
        body,
        _nextInstanceOfDayAndTime(day, time),
        const NotificationDetails(
          android: AndroidNotificationDetails('reminders_channel', 'Reminders', importance: Importance.max, priority: Priority.high),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
      );
    }
  }

  static DateTime _calculateNextLocalInstance(int targetDay, TimeOfDay time) {
    DateTime now = DateTime.now();
    DateTime scheduledDate = DateTime(now.year, now.month, now.day, time.hour, time.minute);
    if (scheduledDate.isBefore(now)) scheduledDate = scheduledDate.add(const Duration(days: 1));
    while (scheduledDate.weekday != targetDay) scheduledDate = scheduledDate.add(const Duration(days: 1));
    return scheduledDate;
  }

  static tz.TZDateTime _nextInstanceOfDayAndTime(int day, TimeOfDay time) {
    tz.TZDateTime scheduledDate = _nextInstanceOfTime(time.hour, time.minute);
    while (scheduledDate.weekday != day) scheduledDate = scheduledDate.add(const Duration(days: 1));
    return scheduledDate;
  }

  static tz.TZDateTime _nextInstanceOfTime(int hour, int minute) {
    final tz.TZDateTime now = tz.TZDateTime.now(tz.local);
    tz.TZDateTime scheduledDate = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (scheduledDate.isBefore(now)) scheduledDate = scheduledDate.add(const Duration(days: 1));
    return scheduledDate;
  }

  static Future<void> cancelAll() async {
    if (kIsWeb) {
      _webTasks.clear();
      await _saveWebTasks();
      return;
    }
    await _notificationsPlugin.cancelAll();
  }
}

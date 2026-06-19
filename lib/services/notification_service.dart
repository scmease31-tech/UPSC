import 'dart:math';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

/// Handles local notifications for daily current affairs and quiz reminders.
class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  /// Global navigator key for handling notification taps.
  static GlobalKey<NavigatorState>? navigatorKey;

  /// Pending notification payload to process after app is ready.
  static String? pendingPayload;

  /// Initialize the notification plugin with tap handling.
  static Future<void> initialize(GlobalKey<NavigatorState> navKey) async {
    navigatorKey = navKey;
    if (kIsWeb) return;
    tz.initializeTimeZones();

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);

    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTap,
    );

    // Check if app was launched from a notification
    final launchDetails = await _plugin.getNotificationAppLaunchDetails();
    if (launchDetails?.didNotificationLaunchApp == true &&
        launchDetails!.notificationResponse?.payload != null) {
      pendingPayload = launchDetails.notificationResponse!.payload;
    }

    // Request notification permission on Android 13+
    _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  /// Handle notification tap — navigate to the relevant screen.
  static void _onNotificationTap(NotificationResponse response) {
    final payload = response.payload;
    if (payload == null || navigatorKey?.currentState == null) return;

    if (payload.startsWith('article:')) {
      final articleId = payload.substring(8);
      navigatorKey!.currentState!.pushNamed('/article-detail', arguments: articleId);
    } else if (payload == 'quiz') {
      navigatorKey!.currentState!.pushNamed('/daily-challenge');
    } else if (payload == 'flashcards') {
      navigatorKey!.currentState!.pushNamed('/flashcards');
    } else if (payload == 'study') {
      navigatorKey!.currentState!.pushNamed('/explore');
    } else if (payload == 'streak') {
      navigatorKey!.currentState!.pushNamed('/content-tracker');
    } else {
      navigatorKey!.currentState!.pushNamed('/main');
    }
  }

  /// Process any pending notification payload (call after app is fully loaded).
  static void processPendingPayload() {
    if (pendingPayload != null) {
      _onNotificationTap(NotificationResponse(
        notificationResponseType: NotificationResponseType.selectedNotification,
        payload: pendingPayload,
      ));
      pendingPayload = null;
    }
  }

  /// Schedule daily current affairs notification at 8:00 AM.
  static Future<void> scheduleDailyNotification({
    String? articleTitle,
    String? articleId,
  }) async {
    if (kIsWeb) return;
    const androidDetails = AndroidNotificationDetails(
      'daily_affairs',
      'Daily Current Affairs',
      channelDescription: 'Daily current affairs update notification',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
    );
    const details = NotificationDetails(android: androidDetails);

    final title = 'Today\'s Current Affairs Ready!';
    final body = articleTitle != null
        ? '$articleTitle — Tap to read the full analysis.'
        : 'Check out the latest UPSC-relevant news and updates.';
    final payload = articleId != null ? 'article:$articleId' : 'news';

    // Schedule for next 8:00 AM
    final scheduledDate = _nextInstanceOfTime(8, 0);
    await _plugin.zonedSchedule(
      0,
      title,
      body,
      scheduledDate,
      details,
      payload: payload,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  /// Schedule a quiz reminder notification at 6:00 PM.
  static Future<void> scheduleQuizReminder() async {
    if (kIsWeb) return;
    const androidDetails = AndroidNotificationDetails(
      'quiz_reminder',
      'Quiz Reminder',
      channelDescription: 'Daily quiz reminder notification',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      icon: '@mipmap/ic_launcher',
    );
    const details = NotificationDetails(android: androidDetails);

    final scheduledDate = _nextInstanceOfTime(18, 0);
    await _plugin.zonedSchedule(
      1,
      'Time for Your Daily Quiz!',
      'Test your knowledge with today\'s UPSC questions. Keep your streak alive!',
      scheduledDate,
      details,
      payload: 'quiz',
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  /// Show an instant notification for breaking/latest news.
  static Future<void> showBreakingNews({
    required String title,
    required String articleId,
  }) async {
    if (kIsWeb) return;
    const androidDetails = AndroidNotificationDetails(
      'breaking_news',
      'Breaking News',
      channelDescription: 'Important breaking news alerts',
      importance: Importance.max,
      priority: Priority.max,
      icon: '@mipmap/ic_launcher',
    );
    const details = NotificationDetails(android: androidDetails);

    await _plugin.show(
      Random().nextInt(10000) + 100,
      'Breaking: $title',
      'Tap to read the full UPSC analysis.',
      details,
      payload: 'article:$articleId',
    );
  }

  /// Get the next occurrence of a specific time.
  static tz.TZDateTime _nextInstanceOfTime(int hour, int minute) {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }

  /// Schedule a morning flashcard reminder at 7:30 AM.
  static Future<void> scheduleFlashcardReminder() async {
    if (kIsWeb) return;
    const androidDetails = AndroidNotificationDetails(
      'flashcard_reminder',
      'Flashcard Reminder',
      channelDescription: 'Daily flashcard revision reminder',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      icon: '@mipmap/ic_launcher',
    );
    const details = NotificationDetails(android: androidDetails);

    final scheduledDate = _nextInstanceOfTime(7, 30);
    await _plugin.zonedSchedule(
      2,
      'New Flashcards Ready!',
      '15 fresh UPSC flashcards are waiting. Start your day with a quick revision!',
      scheduledDate,
      details,
      payload: 'flashcards',
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  /// Schedule an evening study reminder at 9:00 PM.
  static Future<void> scheduleStudyReminder() async {
    if (kIsWeb) return;
    const androidDetails = AndroidNotificationDetails(
      'study_reminder',
      'Study Reminder',
      channelDescription: 'Evening study session reminder',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      icon: '@mipmap/ic_launcher',
    );
    const details = NotificationDetails(android: androidDetails);

    final scheduledDate = _nextInstanceOfTime(21, 0);
    await _plugin.zonedSchedule(
      3,
      'Evening Study Session',
      'Wrap up your day with a focused study session. Consistency builds toppers!',
      scheduledDate,
      details,
      payload: 'study',
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  /// Schedule a streak warning notification at 8:00 PM — reminds user if streak is at risk.
  static Future<void> scheduleStreakReminder({required int currentStreak}) async {
    if (kIsWeb) return;
    if (currentStreak < 2) return; // Only for users with active streaks

    const androidDetails = AndroidNotificationDetails(
      'streak_reminder',
      'Streak Reminder',
      channelDescription: 'Reminder to maintain your study streak',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
    );
    const details = NotificationDetails(android: androidDetails);

    final scheduledDate = _nextInstanceOfTime(20, 0);
    await _plugin.zonedSchedule(
      4,
      'Don\'t Break Your $currentStreak-Day Streak!',
      'Complete at least one activity today to keep your streak alive!',
      scheduledDate,
      details,
      payload: 'streak',
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  /// Schedule all daily notifications at once.
  static Future<void> scheduleAllDailyNotifications({int currentStreak = 0}) async {
    await scheduleDailyNotification();
    await scheduleQuizReminder();
    await scheduleFlashcardReminder();
    await scheduleStudyReminder();
    await scheduleStreakReminder(currentStreak: currentStreak);
  }

  /// Cancel all scheduled notifications.
  static Future<void> cancelAll() async {
    if (kIsWeb) return;
    await _plugin.cancelAll();
  }
}

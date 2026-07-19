import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/material.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
    );

    await _notificationsPlugin.initialize(
      settings: initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        // Handle notification tap if needed
      },
    );
  }

  Future<void> requestPermissions() async {
    final AndroidFlutterLocalNotificationsPlugin? androidImplementation =
        _notificationsPlugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    await androidImplementation?.requestNotificationsPermission();
  }

  Future<void> showLimitExceededNotification({
    required int limitMinutes,
    required int currentMinutes,
  }) async {
    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'digital_wellness_limit_channel',
      'Screen Time Limit Alerts',
      channelDescription: 'Alerts when daily screen time limits are exceeded',
      importance: Importance.max,
      priority: Priority.high,
      ticker: 'ticker',
      icon: '@mipmap/ic_launcher',
      color: const Color(0xFFD32F2F), // Red
    );
    const NotificationDetails platformChannelSpecifics =
        NotificationDetails(android: androidPlatformChannelSpecifics);

    int overMinutes = currentMinutes - limitMinutes;

    await _notificationsPlugin.show(
      id: 0,
      title: '⚠️ Screen Time Limit Exceeded!',
      body: 'You are $overMinutes minutes over your ${limitMinutes ~/ 60}h ${limitMinutes % 60}m limit. Please lock your phone.',
      notificationDetails: platformChannelSpecifics,
    );
  }

  Future<void> showRiskAssessmentNotification({
    required String riskLevel,
    required String recommendation,
    required int riskScore,
  }) async {
    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'digital_wellness_risk_channel',
      'AI Risk Assessments',
      channelDescription: 'Daily AI analysis of your screen time addiction risk',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      icon: '@mipmap/ic_launcher',
    );
    const NotificationDetails platformChannelSpecifics =
        NotificationDetails(android: androidPlatformChannelSpecifics);

    String emoji = '✅';
    if (riskLevel == 'High') emoji = '🚨';
    else if (riskLevel == 'Medium') emoji = '⚠️';

    await _notificationsPlugin.show(
      id: 1, // Separate ID from the limit alert
      title: '$emoji AI Risk: $riskLevel ($riskScore/100)',
      body: recommendation,
      notificationDetails: platformChannelSpecifics,
    );
  }
}

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest_all.dart' as tz_data;

class NotificationService {
  static final notifications = FlutterLocalNotificationsPlugin();

  static Future<void> initialize() async {
    tz_data.initializeTimeZones();

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: android);
    await notifications.initialize(settings);

    await notifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  static const _confirmChannel = AndroidNotificationDetails(
    'booking_confirmed',
    'Booking Confirmations',
    channelDescription: 'Sent immediately when a class is booked',
    importance: Importance.max,
    priority: Priority.high,
  );

  static const _reminderChannel = AndroidNotificationDetails(
    'class_reminders',
    'Class Reminders',
    channelDescription: 'Reminders for upcoming classes',
    importance: Importance.high,
    priority: Priority.high,
  );

  static Future<void> showBookingConfirmed(String className) async {
    await notifications.show(
      DateTime.now().millisecondsSinceEpoch.remainder(100000),
      'Booking Confirmed!',
      'You are booked for $className',
      const NotificationDetails(android: _confirmChannel),
    );
  }

  static Future<void> scheduleClassNotifications(
    String className,
    DateTime bookingDate,
    String bookingTime,
  ) async {
    final timeParts = bookingTime.split(':');
    if (timeParts.length < 2) return;
    final hour = int.tryParse(timeParts[0]) ?? 0;
    final minute = int.tryParse(timeParts[1]) ?? 0;

    final classDateTime = tz.TZDateTime(
      tz.local,
      bookingDate.year,
      bookingDate.month,
      bookingDate.day,
      hour,
      minute,
    );

    final now = tz.TZDateTime.now(tz.local);
    final baseId = DateTime.now().millisecondsSinceEpoch.remainder(50000);

    // Notification 1: 8am on the day of the class
    final morningReminder = tz.TZDateTime(
      tz.local,
      bookingDate.year,
      bookingDate.month,
      bookingDate.day,
      8,
      0,
    );

    if (morningReminder.isAfter(now)) {
      await notifications.zonedSchedule(
        baseId,
        'Class Today!',
        '$className is scheduled for today at $bookingTime',
        morningReminder,
        const NotificationDetails(android: _reminderChannel),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    }

    // Notification 2: 60 minutes before class
    final preClassReminder = classDateTime.subtract(const Duration(minutes: 60));
    if (preClassReminder.isAfter(now)) {
      await notifications.zonedSchedule(
        baseId + 1,
        'Class in 60 Minutes!',
        '$className starts at $bookingTime — get ready!',
        preClassReminder,
        const NotificationDetails(android: _reminderChannel),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    }
  }

  static Future<void> showTestNotification() async {
    await notifications.show(
      1,
      'Fitness Booking',
      'Notification system working',
      const NotificationDetails(android: _confirmChannel),
    );
  }
}

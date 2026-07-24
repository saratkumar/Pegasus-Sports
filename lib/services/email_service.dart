import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/ics_builder.dart';
import '../utils/time_utils.dart';

/// Booking confirmation email — queues a document for the Firebase
/// "Trigger Email" Extension (watches the `mail` collection, sends via
/// Gmail SMTP) instead of calling EmailJS directly.
///
/// Success here only means the document was queued, not that the email was
/// actually delivered — the Extension sends asynchronously a few seconds
/// later. Check the doc's `delivery.state` field for actual send status.
class EmailService {
  /// [classDate] + [classTime] are optional — when both are given and
  /// parse cleanly, a calendar (.ics) invite is attached. Omit them for
  /// waiting-list-join type emails that aren't a confirmed slot yet.
  static Future<void> sendBookingEmail({
    required String email,
    required String className,
    required String classTime,
    DateTime? classDate,
    String location = '',
    int durationMinutes = 60,
  }) async {
    final sessionStart =
        classDate != null ? combineDateAndTime(classDate, classTime) : null;

    await FirebaseFirestore.instance.collection('mail').add({
      'to': [email],
      'message': {
        'subject': 'Booking Confirmed — $className',
        'html': '''
          <div style="font-family: sans-serif; color: #0A0A0A;">
            <h2 style="color: #FF7A00;">Booking Confirmed</h2>
            <p>Your booking for <strong>$className</strong> at <strong>$classTime</strong> is confirmed.</p>
            <p>See you there!</p>
          </div>
        ''',
        if (sessionStart != null)
          'attachments': [
            {
              'filename': 'invite.ics',
              'content': base64Encode(utf8.encode(IcsBuilder.build(
                summary: className,
                start: sessionStart,
                durationMinutes: durationMinutes,
                location: location,
              ))),
              'encoding': 'base64',
              'contentType': 'text/calendar; charset=utf-8; method=REQUEST',
            },
          ],
      },
    });
  }

  /// Sent when an admin cancels a single session or an entire class series
  /// (see ClassCancellationService) — the credit refund already happened by
  /// the time this queues, so the copy states it as fact, not a promise.
  static Future<void> sendCancellationEmail({
    required String email,
    required String clientName,
    required String className,
    required DateTime classDate,
    required String classTime,
    required int creditsRefunded,
    bool wholeClassCancelled = false,
  }) async {
    final dateStr =
        '${classDate.day.toString().padLeft(2, '0')}/${classDate.month.toString().padLeft(2, '0')}/${classDate.year}';
    final subject = wholeClassCancelled
        ? 'Class Cancelled — $className'
        : 'Session Cancelled — $className ($dateStr)';
    final body = wholeClassCancelled
        ? '<strong>$className</strong> has been cancelled and will no longer run.'
        : 'Your <strong>$className</strong> session on <strong>$dateStr</strong> at <strong>$classTime</strong> has been cancelled.';

    await FirebaseFirestore.instance.collection('mail').add({
      'to': [email],
      'message': {
        'subject': subject,
        'html': '''
          <div style="font-family: sans-serif; color: #0A0A0A;">
            <h2 style="color: #FF7A00;">Session Cancelled</h2>
            <p>Hi $clientName,</p>
            <p>$body</p>
            ${creditsRefunded > 0 ? '<p>$creditsRefunded credit${creditsRefunded != 1 ? 's have' : ' has'} been refunded to your account.</p>' : ''}
            <p>We apologise for the inconvenience.</p>
          </div>
        ''',
      },
    });
  }
}

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/class_model.dart';
import 'config_service.dart';
import 'email_service.dart';
import 'user_service.dart';
import 'waiting_list_service.dart';

/// Result of a direct admin cancellation — how many bookings/waitlist
/// entries were touched, for the confirmation toast.
typedef CancelResult = ({int bookingsCancelled, int waitlistCleared});

/// Direct admin "cancel this class" actions — as opposed to
/// `_approveSessionCancel` in admin_requests_screen.dart, which cancels one
/// session but only as the resolution of a trainer's submitted request.
/// This follows the same cascade (cancel bookings → refund credits → log
/// activity → mark the class doc) plus closes two gaps that flow left open:
/// clearing/refunding the waiting list, and emailing affected clients
/// (previously only a same-device local notification, which doesn't
/// reliably reach anyone else's device).
class ClassCancellationService {
  static final _bookingsCol = FirebaseFirestore.instance.collection('bookings');
  static final _classesCol = FirebaseFirestore.instance.collection('classes');
  static final _usersCol = FirebaseFirestore.instance.collection('users');

  static Future<List<QueryDocumentSnapshot>> _activeBookingsFor(
    String classId, {
    required bool Function(DateTime bookingDate) matches,
  }) async {
    final snap =
        await _bookingsCol.where('classId', isEqualTo: classId).get();
    return snap.docs.where((d) {
      final data = d.data();
      if (data['status'] == 'cancelled_by_trainer') return false;
      final bd = data['bookingDate'];
      if (bd == null) return false;
      return matches((bd as Timestamp).toDate());
    }).toList();
  }

  /// Cancels every booking for [cls] on [date]: refunds credits, emails and
  /// logs each affected client, clears that date's waiting list, and marks
  /// the date cancelled on the class (or deactivates it entirely if it's a
  /// one-off with no other occurrence).
  static Future<CancelResult> cancelSession(
      ClassModel cls, DateTime date) async {
    final classId = cls.effectiveId;
    final start = DateTime(date.year, date.month, date.day);
    final end = start.add(const Duration(days: 1));

    final targets = await _activeBookingsFor(classId,
        matches: (bd) => !bd.isBefore(start) && bd.isBefore(end));

    await _cancelAndNotify(targets, classId: classId, className: cls.mode);

    final waitlistCleared =
        await WaitingListService.expireWaitingListForDate(classId, date);

    if (cls.occurrence == 'once') {
      await _classesCol.doc(cls.id).update(
          {'isActive': false, 'updatedAt': FieldValue.serverTimestamp()});
    } else {
      await _classesCol.doc(cls.id).update({
        'cancelledDates': FieldValue.arrayUnion([_dateKey(date)]),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }

    await FirebaseFirestore.instance.collection('sessionLogs').add({
      'type': 'session_cancelled',
      'classId': classId,
      'className': cls.mode,
      'sessionDate': _dateKey(date),
      'cancelledAt': Timestamp.now(),
      'reason': 'admin_direct',
      'classDeactivated': cls.occurrence == 'once',
    });

    return (bookingsCancelled: targets.length, waitlistCleared: waitlistCleared);
  }

  /// Cancels every FUTURE booking for [cls] (past bookings are left alone —
  /// they already happened) and deactivates the class so it stops appearing
  /// on the timetable. Unlike ClassService.deleteClass, the class document
  /// itself is kept (preserves cancelledDates/history) — only its active
  /// flag changes.
  static Future<CancelResult> cancelWholeClass(ClassModel cls) async {
    final classId = cls.effectiveId;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final targets = await _activeBookingsFor(classId,
        matches: (bd) => !bd.isBefore(today));

    await _cancelAndNotify(targets, classId: classId, className: cls.mode);

    final waitlistCleared =
        await WaitingListService.expireFutureWaitingList(classId, today);

    await _classesCol
        .doc(cls.id)
        .update({'isActive': false, 'updatedAt': FieldValue.serverTimestamp()});

    await FirebaseFirestore.instance.collection('sessionLogs').add({
      'type': 'class_cancelled',
      'classId': classId,
      'className': cls.mode,
      'cancelledAt': Timestamp.now(),
      'reason': 'admin_direct',
      'bookingsCancelled': targets.length,
    });

    return (bookingsCancelled: targets.length, waitlistCleared: waitlistCleared);
  }

  /// Marks each booking cancelled (batched), then — per booking — refunds
  /// credits, logs the Activity Log event, and emails the client. The
  /// per-client lookups/emails run after the batch commits so a slow email
  /// send can never block the (fast, all-or-nothing) status update.
  static Future<void> _cancelAndNotify(
    List<QueryDocumentSnapshot> targets, {
    required String classId,
    required String className,
  }) async {
    if (targets.isEmpty) return;

    final batch = FirebaseFirestore.instance.batch();
    for (final doc in targets) {
      batch.update(doc.reference, {'status': 'cancelled_by_trainer'});
    }
    await batch.commit();

    await Future.wait(targets.map((doc) async {
      final data = doc.data() as Map<String, dynamic>;
      final uid = data['userId']?.toString() ?? '';
      final bookingDate = (data['bookingDate'] as Timestamp).toDate();
      final bookingTime = data['bookingTime']?.toString() ?? '';
      final credits = (data['creditsUsed'] as int?) ?? 1;
      if (uid.isEmpty) return;

      final userDoc = await _usersCol.doc(uid).get();
      final userName = userDoc.data()?['name']?.toString() ?? uid;
      final userEmail = userDoc.data()?['email']?.toString() ?? '';

      if (credits > 0) {
        await UserService.addCredits(uid, credits);
      }

      unawaited(ConfigService.logActivityEvent(
        eventType: 'Session Cancelled by Admin',
        classId: classId,
        className: className,
        sessionDate: bookingDate,
        sessionTime: bookingTime,
        userId: uid,
        userName: userName,
        bookedByRole: data['bookedByRole']?.toString() ?? 'client',
        creditsUsed: credits,
        bookingId: doc.id,
      ));

      if (userEmail.isNotEmpty) {
        try {
          await EmailService.sendCancellationEmail(
            email: userEmail,
            clientName: userName,
            className: className,
            classDate: bookingDate,
            classTime: bookingTime,
            creditsRefunded: credits,
          );
        } catch (_) {
          // Best-effort — the cancellation/refund itself already succeeded.
        }
      }
    }));
  }

  static String _dateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Count of future bookings a whole-class cancellation would affect —
  /// used to show the admin a real number before they confirm.
  static Future<int> previewFutureBookingsCount(String classId) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final targets =
        await _activeBookingsFor(classId, matches: (bd) => !bd.isBefore(today));
    return targets.length;
  }
}

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/class_model.dart';
import 'class_service.dart';
import 'config_service.dart';
import 'user_service.dart';

/// Why [BookingService.bookClass] refused to book — callers map each reason
/// to their own user-facing text (self-booking and admin-on-behalf-of-client
/// need different wording for the same failure).
enum BookingFailureReason {
  alreadyBooked,
  planNotAllowed,
  noCredits,
  classFull,
  unknown,
}

/// Outcome of [BookingService.bookClass].
class BookingResult {
  final bool success;
  final BookingFailureReason? reason;
  final String? errorDetail; // set only for BookingFailureReason.unknown
  final String? bookingId;

  const BookingResult.ok(this.bookingId)
      : success = true,
        reason = null,
        errorDetail = null;
  const BookingResult.failure(this.reason, {this.errorDetail})
      : success = false,
        bookingId = null;
}

/// Guard + write logic shared by every path that creates a class booking —
/// a client booking for themselves, or an admin booking on behalf of a
/// client. Centralized so admin bookings are guaranteed to enforce the same
/// credit/capacity/plan-whitelist rules as self-booking, rather than two
/// copies drifting apart over time. Deliberately excludes local-notification
/// scheduling (NotificationService) — those fire on whichever device runs
/// this code, so bundling them here would incorrectly notify an admin's
/// device instead of the client's; callers own that concern themselves.
class BookingService {
  /// See classes_screen.dart's original `_canBookClass` doc comment: an
  /// empty [ClassModel.allowedPlanNames] is unrestricted; otherwise [uid]
  /// must hold an eligible plan (active or queued) or have unrestricted
  /// admin-granted access.
  static Future<bool> canBookClass(ClassModel cls, String uid) async {
    if (cls.allowedPlanNames.isEmpty) return true;
    final user = await UserService.getUser(uid);
    if (user == null) return false;
    if (user.hasUnrestrictedAccess) return true;
    final now = DateTime.now();
    return user.memberships.any((m) =>
        cls.allowedPlanNames.contains(m.planName) &&
        ((m.isActive && m.endDate.isAfter(now)) || m.isQueued));
  }

  static const _dayNames = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday',
    'Friday', 'Saturday', 'Sunday',
  ];

  /// Creates a booking for [targetUid] on [cls]/[date], deducting one credit
  /// from them. [bookedByUid]/[bookedByRole] record who actually initiated
  /// it ('client' for self-booking, 'admin' for admin-on-behalf-of-client).
  /// Runs the same duplicate/plan-whitelist/credit/capacity guards
  /// regardless of who's booking for whom.
  static Future<BookingResult> bookClass({
    required ClassModel cls,
    required DateTime date,
    required String targetUid,
    required String bookedByUid,
    required String bookedByRole,
    String? targetUserName,
  }) async {
    final classId = cls.effectiveId;

    try {
      // Duplicate check — no date range in Firestore to avoid composite index; filter in Dart
      final existingSnap = await FirebaseFirestore.instance
          .collection('bookings')
          .where('userId', isEqualTo: targetUid)
          .where('classId', isEqualTo: classId)
          .get();

      final alreadyBooked = existingSnap.docs.any((d) {
        final bd = d['bookingDate'];
        if (bd == null) return false;
        final dt = (bd as Timestamp).toDate();
        return dt.year == date.year &&
            dt.month == date.month &&
            dt.day == date.day;
      });
      if (alreadyBooked) {
        return const BookingResult.failure(BookingFailureReason.alreadyBooked);
      }

      if (!await canBookClass(cls, targetUid)) {
        return const BookingResult.failure(BookingFailureReason.planNotAllowed);
      }

      // Credit check + capacity check in parallel
      final results = await Future.wait([
        UserService.hasEnoughCredits(targetUid,
            allowedPlanNames: cls.allowedPlanNames),
        ClassService.getBookingCount(classId, date),
      ]);
      final hasCredits = results[0] as bool;
      final booked = results[1] as int;

      if (!hasCredits) {
        return const BookingResult.failure(BookingFailureReason.noCredits);
      }

      final capacity = cls.effectiveCapacity(date);
      if (capacity > 0 && booked >= capacity) {
        return const BookingResult.failure(BookingFailureReason.classFull);
      }

      // Create booking + deduct credit atomically — a booking is never left
      // orphaned without its credit actually being deducted, or vice versa.
      final bookingRef =
          FirebaseFirestore.instance.collection('bookings').doc();
      await UserService.deductCreditAndWrite(targetUid, (tx, sourceEntryId) {
        tx.set(bookingRef, {
          'userId': targetUid,
          'classId': classId,
          'displayName': cls.mode,
          'bookingType': 'class',
          'bookingDay': _dayNames[date.weekday - 1],
          'bookingDate': Timestamp.fromDate(date),
          'bookingTime': cls.startTime,
          'createdAt': Timestamp.now(),
          'bookedBy': bookedByUid,
          'bookedByRole': bookedByRole,
          'creditsUsed': 1,
          'creditSourceEntryId': sourceEntryId,
        });
      }, allowedPlanNames: cls.allowedPlanNames);

      unawaited(ConfigService.logActivityEvent(
        eventType: 'Booked',
        classId: classId,
        className: cls.mode,
        sessionDate: date,
        sessionTime: cls.startTime,
        userId: targetUid,
        userName: targetUserName ?? targetUid,
        bookedByRole: bookedByRole,
        bookingId: bookingRef.id,
      ));

      return BookingResult.ok(bookingRef.id);
    } catch (e) {
      return BookingResult.failure(BookingFailureReason.unknown,
          errorDetail: e.toString());
    }
  }
}

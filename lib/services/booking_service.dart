import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/class_model.dart';
import '../models/dependent_model.dart';
import 'class_service.dart';
import 'config_service.dart';
import 'membership_plan_service.dart';
import 'user_service.dart';
import '../utils/crash_log.dart';

/// Why [BookingService.bookClass] refused to book — callers map each reason
/// to their own user-facing text (self-booking and admin-on-behalf-of-client
/// need different wording for the same failure).
enum BookingFailureReason {
  alreadyBooked,
  planNotAllowed,
  noCredits,
  classFull,
  /// The child attendee is outside the 6–17 age range on the session date.
  attendeeIneligible,
  unknown,
}

/// Which of the account holder's plans a booking may draw credit from,
/// depending on who attends — see [BookingService.creditRulesFor].
typedef CreditRules = ({Set<String> excluded, Set<String> preferred});

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
  /// Junior packages ([MembershipPlanModel.isJunior]) are for children only:
  /// when the account holder attends ([attendee] null) they're excluded
  /// outright; when a child attends they're drawn from first, falling back
  /// to the parent's other plans (parents may spend their own credits on
  /// their children).
  static Future<CreditRules> creditRulesFor(DependentModel? attendee) async {
    final junior = await MembershipPlanService.getJuniorPlanNames();
    return attendee == null
        ? (excluded: junior, preferred: const <String>{})
        : (excluded: const <String>{}, preferred: junior);
  }

  /// Name recorded in the activity log / roster for a booking — the child's
  /// name tagged with the parent's when a child attends, so trainers see who
  /// is actually in the room and whom to contact.
  static String attendeeLogName(String? attendeeName, String parentName) =>
      attendeeName == null ? parentName : '$attendeeName (Junior · $parentName)';

  /// See classes_screen.dart's original `_canBookClass` doc comment: an
  /// empty [ClassModel.allowedPlanNames] is unrestricted; otherwise [uid]
  /// must hold an eligible plan (active or queued), other than any in
  /// [excludedPlanNames], or have unrestricted admin-granted access.
  static Future<bool> canBookClass(
    ClassModel cls,
    String uid, {
    Set<String> excludedPlanNames = const {},
  }) async {
    if (cls.allowedPlanNames.isEmpty) return true;
    final user = await UserService.getUser(uid);
    if (user == null) return false;
    if (user.hasUnrestrictedAccess) return true;
    final now = DateTime.now();
    return user.memberships.any((m) =>
        cls.allowedPlanNames.contains(m.planName) &&
        !excludedPlanNames.contains(m.planName) &&
        ((m.isActive && m.endDate.isAfter(now)) || m.isQueued));
  }

  static const _dayNames = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday',
    'Friday', 'Saturday', 'Sunday',
  ];

  /// Creates a booking for [targetUid] on [cls]/[date], deducting one credit
  /// from them. [bookedByUid]/[bookedByRole] record who actually initiated
  /// it ('client' for self-booking, 'admin' for admin-on-behalf-of-client).
  /// [attendee] is one of [targetUid]'s child profiles when booking for a
  /// child (null = the account holder attends). Runs the same
  /// duplicate/plan-whitelist/credit/capacity guards regardless of who's
  /// booking for whom.
  static Future<BookingResult> bookClass({
    required ClassModel cls,
    required DateTime date,
    required String targetUid,
    required String bookedByUid,
    required String bookedByRole,
    String? targetUserName,
    DependentModel? attendee,
  }) async {
    final classId = cls.effectiveId;

    if (attendee != null && !attendee.isEligibleJuniorOn(date)) {
      return const BookingResult.failure(
          BookingFailureReason.attendeeIneligible);
    }

    try {
      // Duplicate check — no date range in Firestore to avoid composite index; filter in Dart
      final existingSnap = await FirebaseFirestore.instance
          .collection('bookings')
          .where('userId', isEqualTo: targetUid)
          .where('classId', isEqualTo: classId)
          .get();

      // Per attendee — a parent may book themselves and each child into the
      // same session.
      final alreadyBooked = existingSnap.docs.any((d) {
        if (d.data()['attendeeId'] != attendee?.id) return false;
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

      final rules = await creditRulesFor(attendee);
      if (!await canBookClass(cls, targetUid,
          excludedPlanNames: rules.excluded)) {
        return const BookingResult.failure(BookingFailureReason.planNotAllowed);
      }

      // Credit check + capacity check in parallel
      final results = await Future.wait([
        UserService.hasEnoughCredits(targetUid,
            allowedPlanNames: cls.allowedPlanNames,
            excludedPlanNames: rules.excluded),
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
          if (attendee != null) 'attendeeId': attendee.id,
          if (attendee != null) 'attendeeName': attendee.name,
        });
      },
          allowedPlanNames: cls.allowedPlanNames,
          excludedPlanNames: rules.excluded,
          preferredPlanNames: rules.preferred);

      unawaited(ConfigService.logActivityEvent(
        eventType: 'Booked',
        classId: classId,
        className: cls.mode,
        sessionDate: date,
        sessionTime: cls.startTime,
        userId: targetUid,
        userName: attendeeLogName(attendee?.name, targetUserName ?? targetUid),
        bookedByRole: bookedByRole,
        bookingId: bookingRef.id,
      ));

      return BookingResult.ok(bookingRef.id);
    } catch (e, st) {
      crashRecord(e, st, reason: 'Class booking failed', fatal: false);
      return BookingResult.failure(BookingFailureReason.unknown,
          errorDetail: e.toString());
    }
  }
}

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
  /// Rules for the ACCOUNT HOLDER's wallet. Junior packages
  /// ([MembershipPlanModel.isJunior]) live on the child they were bought for
  /// (users/{uid}/dependents/{childId}.memberships) and are drawn from there
  /// first whenever that child attends — see
  /// [UserService.deductCreditAndWrite]'s `childId`. Junior plan names stay
  /// excluded from the holder's own wallet regardless, so a junior package
  /// that ever lands there (e.g. one bought before packages were per-child)
  /// still can't be spent on an adult.
  static Future<CreditRules> creditRulesFor(DependentModel? attendee) async {
    final junior = await MembershipPlanService.getJuniorPlanNames();
    return (excluded: junior, preferred: const <String>{});
  }

  /// Name recorded in the activity log / roster for a booking — the child's
  /// name tagged with the parent's when a child attends, so trainers see who
  /// is actually in the room and whom to contact.
  /// A guest brought on the member's credits is tagged the same way.
  static String attendeeLogName(String? attendeeName, String parentName,
          {String? guestName}) =>
      guestName != null
          ? '$guestName (Guest · $parentName)'
          : attendeeName == null
              ? parentName
              : '$attendeeName (Junior · $parentName)';

  /// See classes_screen.dart's original `_canBookClass` doc comment: an
  /// empty [ClassModel.allowedPlanNames] is unrestricted; otherwise [uid]
  /// must hold an eligible plan (active or queued), other than any in
  /// [excludedPlanNames], or have unrestricted admin-granted access.
  ///
  /// [child] attending: their own junior packages count too, and the
  /// holder's plans only if [parentFallback] (a parent booking for their
  /// child, not a child booking for themselves).
  static Future<bool> canBookClass(
    ClassModel cls,
    String uid, {
    Set<String> excludedPlanNames = const {},
    DependentModel? child,
    bool parentFallback = true,
  }) async {
    if (cls.allowedPlanNames.isEmpty) return true;
    if (child != null) {
      final now = DateTime.now();
      if (child.memberships.any((m) =>
          cls.allowedPlanNames.contains(m.planName) &&
          ((m.isActive && m.endDate.isAfter(now)) || m.isQueued))) {
        return true;
      }
      if (!parentFallback) return false;
    }
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
    bool parentCreditsAllowed = true,
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
        // Guests brought on this member's credits aren't the member.
        if (d.data()['guestName'] != null) return false;
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
          excludedPlanNames: rules.excluded,
          child: attendee,
          parentFallback: parentCreditsAllowed)) {
        return const BookingResult.failure(BookingFailureReason.planNotAllowed);
      }

      // Credit check + capacity check in parallel
      final results = await Future.wait([
        UserService.hasEnoughCredits(targetUid,
            allowedPlanNames: cls.allowedPlanNames,
            excludedPlanNames: rules.excluded,
            childId: attendee?.id,
            parentFallback: parentCreditsAllowed),
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
      await UserService.deductCreditAndWrite(targetUid,
          (tx, sourceEntryId, fromChild) {
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
          if (fromChild) 'creditWallet': 'child',
          if (attendee != null) 'attendeeId': attendee.id,
          if (attendee != null) 'attendeeName': attendee.name,
        });
      },
          allowedPlanNames: cls.allowedPlanNames,
          excludedPlanNames: rules.excluded,
          preferredPlanNames: rules.preferred,
          childId: attendee?.id,
          parentFallback: parentCreditsAllowed);

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

  /// How many guests [uid] can still bring to [cls] on [date]: one credit
  /// per guest from the member's own (non-junior) credits, after keeping
  /// one for themselves unless [memberAlreadyBooked], and never more than
  /// the spots left.
  static Future<int> maxGuests({
    required ClassModel cls,
    required DateTime date,
    required String uid,
    required bool memberAlreadyBooked,
  }) async {
    final rules = await creditRulesFor(null);
    final results = await Future.wait([
      UserService.usableCreditCount(uid,
          allowedPlanNames: cls.allowedPlanNames,
          excludedPlanNames: rules.excluded),
      ClassService.getBookingCount(cls.effectiveId, date),
    ]);
    final credits = results[0] - (memberAlreadyBooked ? 0 : 1);
    final capacity = cls.effectiveCapacity(date);
    final spotsLeft = capacity > 0
        ? capacity - results[1] - (memberAlreadyBooked ? 0 : 1)
        : credits;
    final max = credits < spotsLeft ? credits : spotsLeft;
    return max > 0 ? max : 0;
  }

  /// Books [guestNames] into [cls]/[date] on [targetUid]'s credits — one
  /// booking and one credit per guest, all in one transaction, so either
  /// every guest is booked or none are. Uses the member's own credit rules
  /// (junior packages are for the member's children, not guests). Guest
  /// bookings carry `guestName` and no `attendeeId`, so capacity counts,
  /// cancellations and refunds treat each guest like any other booking.
  static Future<BookingResult> bookGuests({
    required ClassModel cls,
    required DateTime date,
    required String targetUid,
    required String bookedByUid,
    required String bookedByRole,
    required List<String> guestNames,
    String? targetUserName,
  }) async {
    final classId = cls.effectiveId;
    final names = guestNames.map((n) => n.trim()).where((n) => n.isNotEmpty).toList();
    if (names.isEmpty) return const BookingResult.ok(null);

    try {
      final rules = await creditRulesFor(null);
      if (!await canBookClass(cls, targetUid,
          excludedPlanNames: rules.excluded)) {
        return const BookingResult.failure(BookingFailureReason.planNotAllowed);
      }

      final results = await Future.wait([
        UserService.usableCreditCount(targetUid,
            allowedPlanNames: cls.allowedPlanNames,
            excludedPlanNames: rules.excluded),
        ClassService.getBookingCount(classId, date),
      ]);
      if (results[0] < names.length) {
        return const BookingResult.failure(BookingFailureReason.noCredits);
      }
      final capacity = cls.effectiveCapacity(date);
      if (capacity > 0 && results[1] + names.length > capacity) {
        return const BookingResult.failure(BookingFailureReason.classFull);
      }

      final refs = [
        for (var i = 0; i < names.length; i++)
          FirebaseFirestore.instance.collection('bookings').doc(),
      ];
      await UserService.deductCreditsAndWrite(targetUid, names.length,
          (tx, sourceEntryIds) {
        for (var i = 0; i < names.length; i++) {
          tx.set(refs[i], {
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
            'creditSourceEntryId': sourceEntryIds[i],
            'guestName': names[i],
          });
        }
      },
          allowedPlanNames: cls.allowedPlanNames,
          excludedPlanNames: rules.excluded);

      for (var i = 0; i < names.length; i++) {
        unawaited(ConfigService.logActivityEvent(
          eventType: 'Booked',
          classId: classId,
          className: cls.mode,
          sessionDate: date,
          sessionTime: cls.startTime,
          userId: targetUid,
          userName: attendeeLogName(null, targetUserName ?? targetUid,
              guestName: names[i]),
          bookedByRole: bookedByRole,
          bookingId: refs[i].id,
        ));
      }

      return BookingResult.ok(refs.first.id);
    } catch (e, st) {
      crashRecord(e, st, reason: 'Guest booking failed', fatal: false);
      final noCredits = e is StateError && '$e'.contains('No credits');
      return noCredits
          ? const BookingResult.failure(BookingFailureReason.noCredits)
          : BookingResult.failure(BookingFailureReason.unknown,
              errorDetail: e.toString());
    }
  }
}

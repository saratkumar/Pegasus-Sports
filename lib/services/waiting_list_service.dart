import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/waiting_list_model.dart';
import 'config_service.dart';
import 'email_service.dart';
import 'user_service.dart';

class WaitingListService {
  static final _col = FirebaseFirestore.instance.collection('waitingList');

  static Future<bool> isOnWaitingList(
      String classId, String userId, DateTime date) async {
    final snap = await _col
        .where('classId', isEqualTo: classId)
        .where('userId', isEqualTo: userId)
        .where('status', isEqualTo: 'waiting')
        .get();

    return snap.docs.any((doc) {
      final d = (doc['bookingDate'] as Timestamp).toDate();
      return d.year == date.year && d.month == date.month && d.day == date.day;
    });
  }

  static Future<int> getWaitingCount(
      String classId, DateTime date) async {
    final snap = await _col
        .where('classId', isEqualTo: classId)
        .where('status', isEqualTo: 'waiting')
        .get();

    return snap.docs.where((doc) {
      final d = (doc['bookingDate'] as Timestamp).toDate();
      return d.year == date.year && d.month == date.month && d.day == date.day;
    }).length;
  }

  /// Joins the waiting list; deducts 1 credit from the user.
  static Future<void> joinWaitingList({
    required String classId,
    required String userId,
    required String userName,
    required DateTime bookingDate,
    required String bookingTime,
    required String className,
  }) async {
    final entry = WaitingListModel(
      classId: classId,
      userId: userId,
      userName: userName,
      bookingDate: bookingDate,
      bookingTime: bookingTime,
      className: className,
      requestedAt: DateTime.now(),
      status: 'waiting',
    );
    await _col.add(entry.toFirestore());
    await UserService.deductCredit(userId);
    unawaited(ConfigService.logActivityEvent(
      eventType: 'Joined Waitlist',
      classId: classId,
      className: className,
      sessionDate: bookingDate,
      sessionTime: bookingTime,
      userId: userId,
      userName: userName,
      bookedByRole: 'client',
    ));
  }

  static Future<void> leaveWaitingList(String entryId, String userId) async {
    final doc = await _col.doc(entryId).get();
    if (!doc.exists) return;
    if (doc['status'] != 'waiting') return;
    await _col.doc(entryId).update({'status': 'expired'});
    await UserService.addCredits(userId, 1);
    final entry = WaitingListModel.fromFirestore(doc);
    unawaited(ConfigService.logActivityEvent(
      eventType: 'Left Waitlist',
      classId: entry.classId,
      className: entry.className,
      sessionDate: entry.bookingDate,
      sessionTime: entry.bookingTime,
      userId: userId,
      userName: entry.userName,
      bookedByRole: 'client',
    ));
  }

  /// Called when a booking is cancelled — admits the next person on the waiting list (FIFO).
  static Future<void> admitNextFromWaitingList({
    required String classId,
    required DateTime bookingDate,
    required String bookingTime,
    required String className,
  }) =>
      admitFromWaitingList(
        classId: classId,
        bookingDate: bookingDate,
        bookingTime: bookingTime,
        className: className,
        count: 1,
      );

  /// Admits up to [count] people (FIFO) from the waiting list for a session —
  /// used for single-cancellation backfill and for approved slot increases.
  static Future<void> admitFromWaitingList({
    required String classId,
    required DateTime bookingDate,
    required String bookingTime,
    required String className,
    required int count,
  }) async {
    if (count <= 0) return;

    final sessionStart = DateTime(
      bookingDate.year,
      bookingDate.month,
      bookingDate.day,
      int.tryParse(bookingTime.split(':')[0]) ?? 0,
      int.tryParse(bookingTime.split(':')[1].split(' ')[0]) ?? 0,
    );

    // Don't admit if within 6 hours of session start
    if (DateTime.now()
        .isAfter(sessionStart.subtract(const Duration(hours: 6)))) {
      await expireWaitingListForDate(classId, bookingDate);
      return;
    }

    final snap = await _col
        .where('classId', isEqualTo: classId)
        .where('status', isEqualTo: 'waiting')
        .orderBy('requestedAt')
        .get();

    final matching = snap.docs.where((doc) {
      final entry = WaitingListModel.fromFirestore(doc);
      return entry.bookingDate.year == bookingDate.year &&
          entry.bookingDate.month == bookingDate.month &&
          entry.bookingDate.day == bookingDate.day;
    }).take(count);

    for (final doc in matching) {
      final entry = WaitingListModel.fromFirestore(doc);

      // Admit: create booking for this user
      final bookingRef =
          await FirebaseFirestore.instance.collection('bookings').add({
        'userId': entry.userId,
        'classId': classId,
        'displayName': className,
        'bookingType': 'class',
        'bookingDay': _dayName(bookingDate.weekday),
        'bookingDate': Timestamp.fromDate(bookingDate),
        'bookingTime': bookingTime,
        'createdAt': Timestamp.now(),
        'bookedBy': entry.userId,
        'bookedByRole': 'client',
        'creditsUsed': 0, // credit already deducted when joining waiting list
        'admittedFromWaitingList': true,
      });

      await doc.reference.update({'status': 'admitted'});
      unawaited(ConfigService.logActivityEvent(
        eventType: 'Admitted from Waitlist',
        classId: classId,
        className: className,
        sessionDate: bookingDate,
        sessionTime: bookingTime,
        userId: entry.userId,
        userName: entry.userName,
        bookedByRole: 'client',
        creditsUsed: 0,
        bookingId: bookingRef.id,
      ));

      // Waiting-list JOIN never gets a calendar invite (no confirmed slot
      // yet) — only admission does, once the seat is actually theirs.
      unawaited(() async {
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(entry.userId)
            .get();
        final email = userDoc.data()?['email']?.toString() ?? '';
        if (email.isEmpty) return;
        try {
          await EmailService.sendBookingEmail(
            email: email,
            className: className,
            classTime: bookingTime,
            classDate: bookingDate,
          );
        } catch (_) {
          // Best-effort — admission itself already succeeded.
        }
      }());
    }
  }

  /// Expires all still-waiting entries for a session and refunds credits.
  /// Returns the number of entries expired.
  static Future<int> expireWaitingListForDate(
      String classId, DateTime bookingDate) async {
    final snap = await _col
        .where('classId', isEqualTo: classId)
        .where('status', isEqualTo: 'waiting')
        .get();

    final matching = snap.docs.where((doc) {
      final d = (doc['bookingDate'] as Timestamp).toDate();
      return d.year == bookingDate.year &&
          d.month == bookingDate.month &&
          d.day == bookingDate.day;
    }).toList();
    await _expireEntries(matching);
    return matching.length;
  }

  /// Expires every still-waiting entry for [classId] from [from] onward
  /// (inclusive) — used when cancelling an entire class series, where every
  /// future date's waiting list needs clearing, not just one day's. Returns
  /// the number of entries expired.
  static Future<int> expireFutureWaitingList(
      String classId, DateTime from) async {
    final snap = await _col
        .where('classId', isEqualTo: classId)
        .where('status', isEqualTo: 'waiting')
        .get();

    final start = DateTime(from.year, from.month, from.day);
    final matching = snap.docs.where((doc) {
      final d = (doc['bookingDate'] as Timestamp).toDate();
      return !d.isBefore(start);
    }).toList();
    await _expireEntries(matching);
    return matching.length;
  }

  static Future<void> _expireEntries(List<QueryDocumentSnapshot> docs) async {
    if (docs.isEmpty) return;
    final batch = FirebaseFirestore.instance.batch();
    for (final doc in docs) {
      batch.update(doc.reference, {'status': 'expired'});
    }
    await batch.commit();
    for (final doc in docs) {
      // Refund credit asynchronously
      unawaited(UserService.addCredits(doc['userId'] as String, 1));
      final entry = WaitingListModel.fromFirestore(doc);
      unawaited(ConfigService.logActivityEvent(
        eventType: 'Waitlist Expired',
        classId: entry.classId,
        className: entry.className,
        sessionDate: entry.bookingDate,
        sessionTime: entry.bookingTime,
        userId: entry.userId,
        userName: entry.userName,
        bookedByRole: 'client',
      ));
    }
  }

  static String _dayName(int weekday) {
    const names = [
      'Monday', 'Tuesday', 'Wednesday', 'Thursday',
      'Friday', 'Saturday', 'Sunday'
    ];
    return names[weekday - 1];
  }

  static Stream<List<WaitingListModel>> userWaitingListStream(String userId) {
    return _col
        .where('userId', isEqualTo: userId)
        .where('status', isEqualTo: 'waiting')
        .snapshots()
        .map((snap) =>
            snap.docs.map(WaitingListModel.fromFirestore).toList());
  }
}

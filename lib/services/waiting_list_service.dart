import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/waiting_list_model.dart';
import 'config_service.dart';
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
      await _expireWaitingList(classId, bookingDate);
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
    }
  }

  /// Expires all still-waiting entries for a session and refunds credits.
  static Future<void> _expireWaitingList(
      String classId, DateTime bookingDate) async {
    final snap = await _col
        .where('classId', isEqualTo: classId)
        .where('status', isEqualTo: 'waiting')
        .get();

    final batch = FirebaseFirestore.instance.batch();
    for (final doc in snap.docs) {
      final d = (doc['bookingDate'] as Timestamp).toDate();
      if (d.year == bookingDate.year &&
          d.month == bookingDate.month &&
          d.day == bookingDate.day) {
        batch.update(doc.reference, {'status': 'expired'});
        // Refund credit asynchronously
        UserService.addCredits(doc['userId'] as String, 1);
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
    await batch.commit();
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

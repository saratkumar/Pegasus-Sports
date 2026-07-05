import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/waiting_list_model.dart';
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
  }

  static Future<void> leaveWaitingList(String entryId, String userId) async {
    final doc = await _col.doc(entryId).get();
    if (!doc.exists) return;
    if (doc['status'] != 'waiting') return;
    await _col.doc(entryId).update({'status': 'expired'});
    await UserService.addCredits(userId, 1);
  }

  /// Called when a booking is cancelled — admits the next person on the waiting list (FIFO).
  static Future<void> admitNextFromWaitingList({
    required String classId,
    required DateTime bookingDate,
    required String bookingTime,
    required String className,
  }) async {
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
        .limit(1)
        .get();

    if (snap.docs.isEmpty) return;

    final nextDoc = snap.docs.first;
    final entry = WaitingListModel.fromFirestore(nextDoc);

    // Check date match
    if (entry.bookingDate.year != bookingDate.year ||
        entry.bookingDate.month != bookingDate.month ||
        entry.bookingDate.day != bookingDate.day) {
      return;
    }

    // Admit: create booking for this user
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

    await nextDoc.reference.update({'status': 'admitted'});
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

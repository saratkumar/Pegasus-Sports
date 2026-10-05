import 'package:cloud_firestore/cloud_firestore.dart';

class WaitingListModel {
  final String? id;
  final String classId;
  final String userId;
  final String userName;
  final DateTime bookingDate;
  final String bookingTime;
  final String className;
  final DateTime requestedAt;
  final String status; // 'waiting', 'admitted', 'expired'
  // Set when a parent queues one of their child profiles — see
  // DependentModel. [userId] stays the parent (whose credit is held).
  final String? attendeeId;
  final String? attendeeName;

  WaitingListModel({
    this.id,
    required this.classId,
    required this.userId,
    required this.userName,
    required this.bookingDate,
    required this.bookingTime,
    required this.className,
    required this.requestedAt,
    this.status = 'waiting',
    this.attendeeId,
    this.attendeeName,
  });

  factory WaitingListModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return WaitingListModel(
      id: doc.id,
      classId: data['classId'] ?? '',
      userId: data['userId'] ?? '',
      userName: data['userName'] ?? '',
      bookingDate: (data['bookingDate'] as Timestamp).toDate(),
      bookingTime: data['bookingTime'] ?? '',
      className: data['className'] ?? '',
      requestedAt: (data['requestedAt'] as Timestamp).toDate(),
      status: data['status'] ?? 'waiting',
      attendeeId: data['attendeeId'],
      attendeeName: data['attendeeName'],
    );
  }

  Map<String, dynamic> toFirestore() => {
        'classId': classId,
        'userId': userId,
        'userName': userName,
        'bookingDate': Timestamp.fromDate(bookingDate),
        'bookingTime': bookingTime,
        'className': className,
        'requestedAt': Timestamp.fromDate(requestedAt),
        'status': status,
        if (attendeeId != null) 'attendeeId': attendeeId,
        if (attendeeName != null) 'attendeeName': attendeeName,
      };
}

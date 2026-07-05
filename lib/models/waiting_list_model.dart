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
      };
}

import 'package:cloud_firestore/cloud_firestore.dart';

class AdminRequestModel {
  final String? id;
  final String type; // 'credit_request' | 'slot_increase' | 'session_cancel'
  final String requestedBy;
  final String requestedByName;
  final String? targetUserId;
  final String? targetUserName;
  final String? classId;
  final String? className;
  final String? sessionDate; // 'YYYY-MM-DD' — used for session_cancel
  final int amount; // credits or additional slots (0 for session_cancel)
  final String status; // 'pending' | 'approved' | 'rejected' | 'approved_cancel' | 'reassigned'
  final String note;
  final DateTime createdAt;
  final DateTime? resolvedAt;
  final String? resolvedBy;
  final String? newTrainer; // set when status == 'reassigned'
  // appointment_booking made by a parent for one of their child profiles
  // (users/{requestedBy}/dependents/{attendeeId}).
  final String? attendeeId;
  final String? attendeeName;

  AdminRequestModel({
    this.id,
    required this.type,
    required this.requestedBy,
    required this.requestedByName,
    this.targetUserId,
    this.targetUserName,
    this.classId,
    this.className,
    this.sessionDate,
    required this.amount,
    this.status = 'pending',
    this.note = '',
    required this.createdAt,
    this.resolvedAt,
    this.resolvedBy,
    this.newTrainer,
    this.attendeeId,
    this.attendeeName,
  });

  factory AdminRequestModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return AdminRequestModel(
      id: doc.id,
      type: data['type'] ?? '',
      requestedBy: data['requestedBy'] ?? '',
      requestedByName: data['requestedByName'] ?? '',
      targetUserId: data['targetUserId'],
      targetUserName: data['targetUserName'],
      classId: data['classId'],
      className: data['className'],
      sessionDate: data['sessionDate'],
      amount: data['amount'] ?? 0,
      status: data['status'] ?? 'pending',
      note: data['note'] ?? '',
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      resolvedAt: (data['resolvedAt'] as Timestamp?)?.toDate(),
      resolvedBy: data['resolvedBy'],
      newTrainer: data['newTrainer'],
      attendeeId: data['attendeeId'],
      attendeeName: data['attendeeName'],
    );
  }

  Map<String, dynamic> toFirestore() => {
        'type': type,
        'requestedBy': requestedBy,
        'requestedByName': requestedByName,
        if (targetUserId != null) 'targetUserId': targetUserId,
        if (targetUserName != null) 'targetUserName': targetUserName,
        if (classId != null) 'classId': classId,
        if (className != null) 'className': className,
        if (sessionDate != null) 'sessionDate': sessionDate,
        'amount': amount,
        'status': status,
        'note': note,
        'createdAt': Timestamp.fromDate(createdAt),
        if (resolvedAt != null) 'resolvedAt': Timestamp.fromDate(resolvedAt!),
        if (resolvedBy != null) 'resolvedBy': resolvedBy,
        if (newTrainer != null) 'newTrainer': newTrainer,
        if (attendeeId != null) 'attendeeId': attendeeId,
        if (attendeeName != null) 'attendeeName': attendeeName,
      };
}

import 'package:cloud_firestore/cloud_firestore.dart';

class AdminRequestModel {
  final String? id;
  final String type; // 'credit_request', 'slot_increase'
  final String requestedBy;
  final String requestedByName;
  final String? targetUserId;
  final String? targetUserName;
  final String? classId;
  final String? className;
  final int amount; // credits or additional slots
  final String status; // 'pending', 'approved', 'rejected'
  final String note;
  final DateTime createdAt;
  final DateTime? resolvedAt;
  final String? resolvedBy;

  AdminRequestModel({
    this.id,
    required this.type,
    required this.requestedBy,
    required this.requestedByName,
    this.targetUserId,
    this.targetUserName,
    this.classId,
    this.className,
    required this.amount,
    this.status = 'pending',
    this.note = '',
    required this.createdAt,
    this.resolvedAt,
    this.resolvedBy,
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
      amount: data['amount'] ?? 0,
      status: data['status'] ?? 'pending',
      note: data['note'] ?? '',
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      resolvedAt: (data['resolvedAt'] as Timestamp?)?.toDate(),
      resolvedBy: data['resolvedBy'],
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
        'amount': amount,
        'status': status,
        'note': note,
        'createdAt': Timestamp.fromDate(createdAt),
        if (resolvedAt != null) 'resolvedAt': Timestamp.fromDate(resolvedAt!),
        if (resolvedBy != null) 'resolvedBy': resolvedBy,
      };
}

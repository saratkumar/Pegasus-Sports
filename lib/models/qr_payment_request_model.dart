import 'package:cloud_firestore/cloud_firestore.dart';

/// A user-initiated "I paid via the business QR code" request — pending
/// until an admin manually confirms the money actually arrived and
/// approves it. Deliberately its own collection rather than folded into
/// adminRequests: this represents a real payment event (needs plan/price/
/// credits/validity data and produces an invoice), not a scheduling-style
/// approval, so giving it a purpose-built shape avoids repurposing fields
/// that mean something different for other request types.
class QrPaymentRequestModel {
  final String? id;
  final String userId;
  final String userName;
  final String userEmail;
  final String planName;
  final int credits;
  final double amount;
  final String currency;
  final int validityDays;
  final String status; // 'pending' | 'approved' | 'rejected'
  final String note;
  final DateTime createdAt;
  final DateTime? resolvedAt;
  final String? resolvedBy;
  final String? paymentRef; // filled in by admin at approval time, optional
  /// Junior package: the child it's for — approval puts the package on that
  /// child (users/{userId}/dependents/{dependentId}). Null = adult plan.
  final String? dependentId;
  final String? dependentName;

  /// Plan name with the child it's for, for admin lists and receipts.
  String get planLabel =>
      dependentName == null ? planName : '$planName (for $dependentName)';

  QrPaymentRequestModel({
    this.id,
    required this.userId,
    required this.userName,
    required this.userEmail,
    required this.planName,
    required this.credits,
    required this.amount,
    this.currency = 'SGD',
    required this.validityDays,
    this.status = 'pending',
    this.note = '',
    required this.createdAt,
    this.resolvedAt,
    this.resolvedBy,
    this.paymentRef,
    this.dependentId,
    this.dependentName,
  });

  factory QrPaymentRequestModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return QrPaymentRequestModel(
      id: doc.id,
      userId: data['userId'] ?? '',
      userName: data['userName'] ?? '',
      userEmail: data['userEmail'] ?? '',
      planName: data['planName'] ?? '',
      credits: data['credits'] ?? 0,
      amount: (data['amount'] as num?)?.toDouble() ?? 0,
      currency: data['currency'] ?? 'SGD',
      validityDays: data['validityDays'] ?? 0,
      status: data['status'] ?? 'pending',
      note: data['note'] ?? '',
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      resolvedAt: (data['resolvedAt'] as Timestamp?)?.toDate(),
      resolvedBy: data['resolvedBy'],
      paymentRef: data['paymentRef'],
      dependentId: data['dependentId'] as String?,
      dependentName: data['dependentName'] as String?,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'userId': userId,
        'userName': userName,
        'userEmail': userEmail,
        'planName': planName,
        'credits': credits,
        'amount': amount,
        'currency': currency,
        'validityDays': validityDays,
        'status': status,
        'note': note,
        'createdAt': Timestamp.fromDate(createdAt),
        if (resolvedAt != null) 'resolvedAt': Timestamp.fromDate(resolvedAt!),
        if (resolvedBy != null) 'resolvedBy': resolvedBy,
        if (paymentRef != null) 'paymentRef': paymentRef,
        if (dependentId != null) 'dependentId': dependentId,
        if (dependentName != null) 'dependentName': dependentName,
      };
}

import 'package:cloud_firestore/cloud_firestore.dart';

class CouponModel {
  final String? id;
  final String code;
  final String discountType; // 'percent' | 'fixed'
  final double value;
  final bool isActive;
  final int? maxRedemptions; // null = unlimited
  final int redeemedCount;
  final DateTime? expiresAt;

  const CouponModel({
    this.id,
    required this.code,
    required this.discountType,
    required this.value,
    this.isActive = true,
    this.maxRedemptions,
    this.redeemedCount = 0,
    this.expiresAt,
  });

  bool get isExpired => expiresAt != null && DateTime.now().isAfter(expiresAt!);
  bool get isExhausted =>
      maxRedemptions != null && redeemedCount >= maxRedemptions!;
  bool get isValidNow => isActive && !isExpired && !isExhausted;

  double applyTo(double amount) {
    final discounted = discountType == 'percent'
        ? amount * (1 - value / 100)
        : amount - value;
    return discounted < 0 ? 0 : discounted;
  }

  factory CouponModel.fromFirestore(String id, Map<String, dynamic> data) {
    return CouponModel(
      id: id,
      code: data['code'] ?? '',
      discountType: data['discountType'] ?? 'percent',
      value: (data['value'] as num?)?.toDouble() ?? 0,
      isActive: data['isActive'] ?? true,
      maxRedemptions: (data['maxRedemptions'] as num?)?.toInt(),
      redeemedCount: (data['redeemedCount'] as num?)?.toInt() ?? 0,
      expiresAt: (data['expiresAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toFirestore() => {
        'code': code,
        'discountType': discountType,
        'value': value,
        'isActive': isActive,
        if (maxRedemptions != null) 'maxRedemptions': maxRedemptions,
        'redeemedCount': redeemedCount,
        if (expiresAt != null) 'expiresAt': Timestamp.fromDate(expiresAt!),
      };
}

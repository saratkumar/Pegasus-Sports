import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/coupon_model.dart';

class CouponService {
  static final _col = FirebaseFirestore.instance.collection('coupons');

  static String _normalize(String code) => code.trim().toUpperCase();

  static Stream<List<CouponModel>> streamCoupons() {
    return _col.snapshots().map((snap) => snap.docs
        .map((d) => CouponModel.fromFirestore(d.id, d.data()))
        .toList()
      ..sort((a, b) => a.code.compareTo(b.code)));
  }

  /// Coupon codes are used as the document ID so lookups are a single get
  /// and codes are inherently unique.
  static Future<void> createCoupon(CouponModel coupon) async {
    final id = _normalize(coupon.code);
    final doc = await _col.doc(id).get();
    if (doc.exists) {
      throw Exception('A coupon with code "$id" already exists');
    }
    await _col.doc(id).set(coupon.toFirestore());
  }

  static Future<void> updateCoupon(String id, CouponModel coupon) async {
    await _col.doc(id).update(coupon.toFirestore());
  }

  static Future<void> deleteCoupon(String id) async {
    await _col.doc(id).delete();
  }

  /// Looks up a coupon by code and throws a user-facing message if it can't
  /// be applied right now (not found / inactive / expired / redemption cap).
  static Future<CouponModel> validate(String code) async {
    final doc = await _col.doc(_normalize(code)).get();
    if (!doc.exists) {
      throw Exception('Coupon code not found');
    }
    final coupon = CouponModel.fromFirestore(doc.id, doc.data()!);
    if (!coupon.isActive) throw Exception('This coupon is no longer active');
    if (coupon.isExpired) throw Exception('This coupon has expired');
    if (coupon.isExhausted) {
      throw Exception('This coupon has reached its redemption limit');
    }
    return coupon;
  }

  /// Atomically increments the redemption count, re-checking the cap inside
  /// the transaction so concurrent redemptions can't exceed maxRedemptions.
  static Future<void> redeem(String couponId) async {
    final ref = _col.doc(couponId);
    await FirebaseFirestore.instance.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) return;
      final coupon = CouponModel.fromFirestore(snap.id, snap.data()!);
      if (coupon.isExhausted) {
        throw Exception('This coupon has reached its redemption limit');
      }
      tx.update(ref, {'redeemedCount': FieldValue.increment(1)});
    });
  }
}

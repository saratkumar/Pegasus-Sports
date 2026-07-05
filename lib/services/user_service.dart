import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/user_model.dart';

class UserService {
  static final _db = FirebaseFirestore.instance;

  static Future<UserModel?> getCurrentUser() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    return getUser(uid);
  }

  static Future<UserModel?> getUser(String uid) async {
    final doc = await _db.collection('users').doc(uid).get();
    if (!doc.exists) return null;
    return UserModel.fromFirestore(doc.data()!, uid);
  }

  static Stream<UserModel?> currentUserStream() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return Stream.value(null);
    return _db.collection('users').doc(uid).snapshots().map((doc) {
      if (!doc.exists) return null;
      return UserModel.fromFirestore(doc.data()!, uid);
    });
  }

  static Future<List<UserModel>> getAllUsers() async {
    final snap = await _db.collection('users').get();
    return snap.docs
        .map((d) => UserModel.fromFirestore(d.data(), d.id))
        .toList();
  }

  static Future<List<UserModel>> getUsersByRole(String role) async {
    final snap =
        await _db.collection('users').where('role', isEqualTo: role).get();
    return snap.docs
        .map((d) => UserModel.fromFirestore(d.data(), d.id))
        .toList();
  }

  static Future<void> updateRole(
    String uid,
    String role, {
    String? adminLevel,
    List<String>? adminPermissions,
  }) async {
    final data = <String, dynamic>{'role': role};
    if (adminLevel != null) data['adminLevel'] = adminLevel;
    if (adminPermissions != null) data['adminPermissions'] = adminPermissions;
    await _db.collection('users').doc(uid).update(data);
  }

  static Future<void> addCredits(String uid, int amount) async {
    await _db.collection('users').doc(uid).update({
      'credits': FieldValue.increment(amount),
    });
  }

  static Future<void> deductCredit(String uid) async {
    await _db.collection('users').doc(uid).update({
      'credits': FieldValue.increment(-1),
    });
  }

  static Future<bool> hasEnoughCredits(String uid) async {
    final user = await getUser(uid);
    return (user?.credits ?? 0) > 0;
  }

  /// Adds a membership plan; enforces max 2 active plans.
  static Future<void> purchaseMembership(
    String uid,
    MembershipEntry entry,
  ) async {
    final user = await getUser(uid);
    if (user == null) return;

    final activePlans = user.memberships.where((m) => m.isActive).toList();
    if (activePlans.length >= 2) {
      throw Exception(
          'You already have 2 active membership plans. Cancel one before purchasing another.');
    }

    await _db.collection('users').doc(uid).update({
      'memberships': FieldValue.arrayUnion([entry.toMap()]),
      'credits': FieldValue.increment(entry.credits),
    });
  }
}

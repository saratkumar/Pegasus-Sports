import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/dependent_model.dart';

/// CRUD for a parent's child profiles (users/{uid}/dependents). Removal is a
/// soft delete ([DependentModel.isActive] = false) so past bookings that
/// reference the child's id keep resolving.
class DependentService {
  static CollectionReference<Map<String, dynamic>> _col(String parentUid) =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(parentUid)
          .collection('dependents');

  /// Active children, sorted by name. Sorted in Dart — an equality filter
  /// plus orderBy on another field would need a composite index.
  static Stream<List<DependentModel>> streamActive(String parentUid) {
    return _col(parentUid)
        .where('isActive', isEqualTo: true)
        .snapshots()
        .map((snap) => snap.docs.map(DependentModel.fromFirestore).toList()
          ..sort((a, b) => a.name.compareTo(b.name)));
  }

  static Future<List<DependentModel>> getActive(String parentUid) =>
      streamActive(parentUid).first;

  /// A parent's new child starts 'pending' — the onDependentCreated Cloud
  /// Function then files a Child Verification request for admins. A child
  /// added by staff ([addedByStaff]) is approved on the spot.
  static Future<void> add(String parentUid, DependentModel child,
      {bool addedByStaff = false}) =>
      _col(parentUid).add({
        ...child.toFirestore(),
        'createdAt': FieldValue.serverTimestamp(),
        ..._verificationFields(addedByStaff ? 'verified' : 'pending'),
      });

  /// Admin approval/rejection of a child profile (see AdminRequestsScreen).
  static Future<void> setVerification(
          String parentUid, String childId, {required bool approved}) =>
      _col(parentUid).doc(childId).update(
          _verificationFields(approved ? 'verified' : 'rejected'));

  static Map<String, dynamic> _verificationFields(String status) => {
        'verificationStatus': status,
        if (status != 'pending') ...{
          'verifiedAt': FieldValue.serverTimestamp(),
          'verifiedBy': FirebaseAuth.instance.currentUser?.uid,
        },
      };

  static Future<void> update(String parentUid, DependentModel child) =>
      _col(parentUid).doc(child.id).update(child.toFirestore());

  static Future<void> deactivate(String parentUid, String childId) =>
      _col(parentUid).doc(childId).update({
        'isActive': false,
        'updatedAt': FieldValue.serverTimestamp(),
      });
}

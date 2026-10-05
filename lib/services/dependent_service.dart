import 'package:cloud_firestore/cloud_firestore.dart';
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

  static Future<void> add(String parentUid, DependentModel child) =>
      _col(parentUid).add({
        ...child.toFirestore(),
        'createdAt': FieldValue.serverTimestamp(),
      });

  static Future<void> update(String parentUid, DependentModel child) =>
      _col(parentUid).doc(child.id).update(child.toFirestore());

  static Future<void> deactivate(String parentUid, String childId) =>
      _col(parentUid).doc(childId).update({
        'isActive': false,
        'updatedAt': FieldValue.serverTimestamp(),
      });
}

import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/class_model.dart';
import '../models/user_model.dart';

class ClassService {
  static final _col = FirebaseFirestore.instance.collection('classes');
  static final _facilitiesCol =
      FirebaseFirestore.instance.collection('facilities');
  static final _typesCol =
      FirebaseFirestore.instance.collection('classTypes');

  // ── Classes ────────────────────────────────────────────────────────────────

  static Stream<List<ClassModel>> streamClasses() {
    return _col
        .snapshots()
        .map((s) => s.docs.map(ClassModel.fromFirestore).toList());
  }

  static Future<List<ClassModel>> getClasses() async {
    final snap = await _col.get();
    return snap.docs.map(ClassModel.fromFirestore).toList();
  }

  static Future<ClassModel?> getClass(String id) async {
    final doc = await _col.doc(id).get();
    if (!doc.exists) return null;
    return ClassModel.fromFirestore(doc);
  }

  static Future<String> createClass(ClassModel cls) async {
    final ref = await _col.add({
      ...cls.toFirestore(),
      'createdAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  static Future<void> updateClass(String id, ClassModel cls) async {
    await _col.doc(id).update(cls.toFirestore());
  }

  static Future<void> deleteClass(String id) async {
    await _col.doc(id).delete();
  }

  static Future<void> updateGroupSize(String id, int newSize) async {
    await _col.doc(id).update({
      'groupSize': newSize.toString(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<int> getBookingCount(String classId, DateTime date) async {
    // Query by classId only — filter by date in Dart to avoid composite index requirement
    final snap = await FirebaseFirestore.instance
        .collection('bookings')
        .where('classId', isEqualTo: classId)
        .get();
    final start = DateTime(date.year, date.month, date.day);
    final end = start.add(const Duration(days: 1));
    return snap.docs.where((d) {
      final bd = d['bookingDate'];
      if (bd == null) return false;
      final dt = (bd as Timestamp).toDate();
      return !dt.isBefore(start) && dt.isBefore(end);
    }).length;
  }

  // ── Facilities ─────────────────────────────────────────────────────────────

  static Stream<List<Map<String, dynamic>>> streamFacilities() {
    return _facilitiesCol.orderBy('name').snapshots().map((s) => s.docs
        .map((d) => <String, dynamic>{'id': d.id, ...d.data()})
        .toList());
  }

  static Future<List<Map<String, dynamic>>> getFacilities() async {
    final snap = await _facilitiesCol.orderBy('name').get();
    return snap.docs
        .map((d) => <String, dynamic>{'id': d.id, ...d.data()})
        .toList();
  }

  static Future<void> addFacility(String name, String address) async {
    await _facilitiesCol.add({
      'name': name,
      'address': address,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> updateFacility(
      String id, String name, String address) async {
    await _facilitiesCol.doc(id).update({'name': name, 'address': address});
  }

  static Future<void> deleteFacility(String id) async {
    await _facilitiesCol.doc(id).delete();
  }

  // ── Class Types ────────────────────────────────────────────────────────────

  static Stream<List<Map<String, dynamic>>> streamClassTypes() {
    return _typesCol.orderBy('name').snapshots().map((s) => s.docs
        .map((d) => <String, dynamic>{'id': d.id, ...d.data()})
        .toList());
  }

  static Future<List<Map<String, dynamic>>> getClassTypes() async {
    final snap = await _typesCol.orderBy('name').get();
    return snap.docs
        .map((d) => <String, dynamic>{'id': d.id, ...d.data()})
        .toList();
  }

  static Future<void> addClassType(String name, String imageUrl) async {
    await _typesCol.add({
      'name': name,
      'imageUrl': imageUrl,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> updateClassType(
      String id, String name, String imageUrl) async {
    await _typesCol.doc(id).update({'name': name, 'imageUrl': imageUrl});
  }

  static Future<void> deleteClassType(String id) async {
    await _typesCol.doc(id).delete();
  }

  // ── Coaches (trainers + admins shown in coach dropdown) ────────────────────

  static Future<List<UserModel>> getCoaches() async {
    final snap = await FirebaseFirestore.instance
        .collection('users')
        .where('role', whereIn: ['trainer', 'admin'])
        .get();
    return snap.docs
        .map((d) => UserModel.fromFirestore(d.data(), d.id))
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  }
}

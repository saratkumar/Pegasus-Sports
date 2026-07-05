import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/class_model.dart';

class ClassService {
  static final _col = FirebaseFirestore.instance.collection('classes');

  static Stream<List<ClassModel>> streamClasses() {
    return _col
        .where('isActive', isEqualTo: true)
        .snapshots()
        .map((snap) => snap.docs.map(ClassModel.fromFirestore).toList());
  }

  static Future<List<ClassModel>> getClasses() async {
    final snap = await _col.where('isActive', isEqualTo: true).get();
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
    await _col.doc(id).update({'isActive': false});
  }

  static Future<void> updateGroupSize(String id, int newSize) async {
    await _col.doc(id).update({
      'groupSize': newSize.toString(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Returns current booking count for a class on a given date.
  static Future<int> getBookingCount(String classId, DateTime date) async {
    final startOfDay = DateTime(date.year, date.month, date.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));
    final snap = await FirebaseFirestore.instance
        .collection('bookings')
        .where('classId', isEqualTo: classId)
        .where('bookingDate',
            isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
        .where('bookingDate', isLessThan: Timestamp.fromDate(endOfDay))
        .get();
    return snap.docs.length;
  }
}

import 'package:cloud_firestore/cloud_firestore.dart';

class ClassModel {
  final String? id; // Firestore document ID; null for Google Sheets fallback
  final String day;
  final String mode; // class display name
  final String coach;
  final String location;
  final String? facilityId;
  final String groupSize;
  final String duration;
  final String detailLocation;
  final String startTime;
  final String type;
  final String image;
  final bool isActive;

  ClassModel({
    this.id,
    required this.day,
    required this.mode,
    required this.coach,
    required this.location,
    this.facilityId,
    required this.groupSize,
    required this.duration,
    required this.detailLocation,
    required this.startTime,
    required this.type,
    required this.image,
    this.isActive = true,
  });

  String get effectiveId => id ?? '${day}_${mode}_$startTime';

  factory ClassModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return ClassModel(
      id: doc.id,
      day: data['day'] ?? '',
      mode: data['mode'] ?? '',
      coach: data['coach'] ?? '',
      location: data['location'] ?? '',
      facilityId: data['facilityId'],
      groupSize: data['groupSize']?.toString() ?? '0',
      duration: data['duration'] ?? '',
      detailLocation: data['detailLocation'] ?? '',
      startTime: data['startTime'] ?? '',
      type: data['type'] ?? '',
      image: data['image'] ?? '',
      isActive: data['isActive'] ?? true,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'day': day,
        'mode': mode,
        'coach': coach,
        'location': location,
        if (facilityId != null) 'facilityId': facilityId,
        'groupSize': groupSize,
        'duration': duration,
        'detailLocation': detailLocation,
        'startTime': startTime,
        'type': type,
        'image': image,
        'isActive': isActive,
        'updatedAt': FieldValue.serverTimestamp(),
      };
}

import 'package:cloud_firestore/cloud_firestore.dart';

class FacilityModel {
  final String? id;
  final String name;
  final String address;
  final String description;
  final bool isActive;
  final DateTime? createdAt;

  FacilityModel({
    this.id,
    required this.name,
    required this.address,
    this.description = '',
    this.isActive = true,
    this.createdAt,
  });

  factory FacilityModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return FacilityModel(
      id: doc.id,
      name: data['name'] ?? '',
      address: data['address'] ?? '',
      description: data['description'] ?? '',
      isActive: data['isActive'] ?? true,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toFirestore() => {
        'name': name,
        'address': address,
        'description': description,
        'isActive': isActive,
        'createdAt': createdAt != null
            ? Timestamp.fromDate(createdAt!)
            : FieldValue.serverTimestamp(),
      };
}

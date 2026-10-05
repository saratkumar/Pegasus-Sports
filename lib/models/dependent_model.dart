import 'package:cloud_firestore/cloud_firestore.dart';

/// A child (under 18) managed by a parent/guardian account, stored at
/// users/{parentUid}/dependents/{id}. Children never sign in themselves —
/// the parent books on their behalf, and bookings stay under the parent's
/// `userId` (credits, history and refunds all keep working unchanged) with
/// `attendeeId`/`attendeeName` recording who actually attends.
class DependentModel {
  /// Youngest age accepted for a junior attendee.
  static const minAge = 6;

  /// At 18 a child must sign up with their own account (Terms: 18+ only).
  static const maxAgeExclusive = 18;

  /// Bumped whenever the parental consent wording in FamilyScreen changes,
  /// so it's known which version each parent agreed to.
  static const consentVersion = '2026-10-05';

  final String? id;
  final String name;
  final DateTime dateOfBirth;
  final String relationship; // 'Parent' | 'Legal guardian'
  final String emergencyContactName;
  final String emergencyContactPhone;
  final String medicalNotes;
  final DateTime? consentAcceptedAt;
  final String consentTermsVersion;
  final bool isActive;

  const DependentModel({
    this.id,
    required this.name,
    required this.dateOfBirth,
    this.relationship = 'Parent',
    this.emergencyContactName = '',
    this.emergencyContactPhone = '',
    this.medicalNotes = '',
    this.consentAcceptedAt,
    this.consentTermsVersion = consentVersion,
    this.isActive = true,
  });

  /// Age in whole years on [on] (defaults to today).
  int ageOn([DateTime? on]) {
    final d = on ?? DateTime.now();
    var age = d.year - dateOfBirth.year;
    if (d.month < dateOfBirth.month ||
        (d.month == dateOfBirth.month && d.day < dateOfBirth.day)) {
      age--;
    }
    return age;
  }

  /// Whether this child can attend a session on [on] — 6 to 17 inclusive.
  bool isEligibleJuniorOn([DateTime? on]) {
    final age = ageOn(on);
    return age >= minAge && age < maxAgeExclusive;
  }

  bool get hasMedicalNotes => medicalNotes.trim().isNotEmpty;

  factory DependentModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return DependentModel(
      id: doc.id,
      name: data['name'] ?? '',
      dateOfBirth: (data['dateOfBirth'] as Timestamp).toDate(),
      relationship: data['relationship'] ?? 'Parent',
      emergencyContactName: data['emergencyContactName'] ?? '',
      emergencyContactPhone: data['emergencyContactPhone'] ?? '',
      medicalNotes: data['medicalNotes'] ?? '',
      consentAcceptedAt: (data['consentAcceptedAt'] as Timestamp?)?.toDate(),
      consentTermsVersion: data['consentTermsVersion'] ?? '',
      isActive: data['isActive'] ?? true,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'name': name,
        'dateOfBirth': Timestamp.fromDate(dateOfBirth),
        'relationship': relationship,
        'emergencyContactName': emergencyContactName,
        'emergencyContactPhone': emergencyContactPhone,
        'medicalNotes': medicalNotes,
        if (consentAcceptedAt != null)
          'consentAcceptedAt': Timestamp.fromDate(consentAcceptedAt!),
        'consentTermsVersion': consentTermsVersion,
        'isActive': isActive,
        'updatedAt': FieldValue.serverTimestamp(),
      };
}

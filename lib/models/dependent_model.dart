import 'package:cloud_firestore/cloud_firestore.dart';
import 'user_model.dart';

/// A child (under 18) managed by a parent/guardian account, stored at
/// users/{parentUid}/dependents/{id}. Bookings for the child stay under the
/// parent's `userId` with `attendeeId`/`attendeeName` recording who
/// actually attends.
///
/// Junior packages are bought by the parent (who pays and gets the receipt)
/// but assigned to one specific child: they live in this doc's own
/// [memberships], so only that child's bookings can draw on them — never the
/// parent's own bookings or a sibling's.
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
  // Staff approval: 'pending' | 'verified' | 'rejected'. Junior packages can
  // only be bought/used for a verified child; once verified the parent can
  // no longer change name or date of birth (firestore.rules). Set only via
  // DependentService.add/setVerification — never by toFirestore().
  final String verificationStatus;

  /// Junior packages assigned to this child — same shape and lifecycle
  /// (active/queued/expired, nightly rollover) as an adult's plans. Written
  /// only by the purchase flow, credit deduction/refund and admin plan
  /// edits, never by [toFirestore] (a profile edit must not clobber them).
  final List<MembershipEntry> memberships;

  /// The child's own email for signing in (optional, set by the parent or
  /// staff). Once the child is approved, an invitation goes to it; on first
  /// sign-in a junior account is created and its uid stored in [linkedUid]
  /// (server-side only — see onDependentWritten / onUserCreated).
  final String loginEmail;
  final String? linkedUid;

  bool get hasLogin => linkedUid != null;

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
    this.verificationStatus = 'pending',
    this.memberships = const [],
    this.loginEmail = '',
    this.linkedUid,
  });

  /// Active junior packages whose date window is still open.
  List<MembershipEntry> get activeMemberships {
    final now = DateTime.now();
    return memberships
        .where((m) => m.isActive && m.endDate.isAfter(now))
        .toList();
  }

  /// Junior packages waiting for the current one of the same plan to end.
  List<MembershipEntry> get queuedMemberships =>
      memberships.where((m) => m.isQueued).toList()
        ..sort((a, b) => a.startDate.compareTo(b.startDate));

  /// Credits this child can use right now (active packages only).
  int get usableCredits => activeMemberships.fold(
      0, (total, m) => total + (m.creditsRemaining > 0 ? m.creditsRemaining : 0));

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

  bool get isVerified => verificationStatus == 'verified';
  bool get isRejected => verificationStatus == 'rejected';

  /// Short status for parents/staff, e.g. "Pending approval".
  String get verificationLabel => isVerified
      ? 'Approved'
      : isRejected
          ? 'Not approved'
          : 'Pending approval';

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
      // Profiles created before verification existed count as pending.
      verificationStatus: data['verificationStatus'] ?? 'pending',
      memberships: (data['memberships'] as List<dynamic>? ?? [])
          .map((e) => MembershipEntry.fromMap(e as Map<String, dynamic>))
          .toList(),
      loginEmail: data['loginEmail'] as String? ?? '',
      linkedUid: data['linkedUid'] as String?,
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
        'loginEmail': loginEmail.trim().toLowerCase(),
        'updatedAt': FieldValue.serverTimestamp(),
      };
}

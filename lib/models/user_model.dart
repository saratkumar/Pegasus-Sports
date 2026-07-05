import 'package:cloud_firestore/cloud_firestore.dart';

class MembershipEntry {
  final String planName;
  final int credits;
  final DateTime startDate;
  final DateTime endDate;
  final DateTime purchasedAt;

  MembershipEntry({
    required this.planName,
    required this.credits,
    required this.startDate,
    required this.endDate,
    required this.purchasedAt,
  });

  factory MembershipEntry.fromMap(Map<String, dynamic> map) {
    return MembershipEntry(
      planName: map['planName'] ?? '',
      credits: map['credits'] ?? 0,
      startDate: (map['startDate'] as Timestamp).toDate(),
      endDate: (map['endDate'] as Timestamp).toDate(),
      purchasedAt: (map['purchasedAt'] as Timestamp).toDate(),
    );
  }

  Map<String, dynamic> toMap() => {
        'planName': planName,
        'credits': credits,
        'startDate': Timestamp.fromDate(startDate),
        'endDate': Timestamp.fromDate(endDate),
        'purchasedAt': Timestamp.fromDate(purchasedAt),
      };

  bool get isActive => endDate.isAfter(DateTime.now());
}

class UserModel {
  final String uid;
  final String email;
  final String name;
  final String? photoUrl;
  final String role; // 'client', 'trainer', 'admin'
  final String? adminLevel; // 'super_admin', 'admin' — only for admin role
  final List<String> adminPermissions;
  final int credits;
  final List<MembershipEntry> memberships;

  UserModel({
    required this.uid,
    required this.email,
    required this.name,
    this.photoUrl,
    this.role = 'client',
    this.adminLevel,
    this.adminPermissions = const [],
    this.credits = 0,
    this.memberships = const [],
  });

  bool get isClient => role == 'client';
  bool get isTrainer => role == 'trainer';
  bool get isAdmin => role == 'admin';
  bool get isSuperAdmin => role == 'admin' && adminLevel == 'super_admin';

  bool hasPermission(String permission) {
    if (isSuperAdmin) return true;
    return adminPermissions.contains(permission);
  }

  // The active membership is the one with the latest end date that hasn't expired.
  MembershipEntry? get activeMembership {
    final active = memberships.where((m) => m.isActive).toList();
    if (active.isEmpty) return null;
    active.sort((a, b) => b.endDate.compareTo(a.endDate));
    return active.first;
  }

  factory UserModel.fromFirestore(Map<String, dynamic> data, String uid) {
    final rawMemberships = data['memberships'] as List<dynamic>? ?? [];
    return UserModel(
      uid: uid,
      email: data['email'] ?? '',
      name: data['name'] ?? '',
      photoUrl: data['photoUrl'],
      role: data['role'] ?? 'client',
      adminLevel: data['adminLevel'],
      adminPermissions: List<String>.from(data['adminPermissions'] ?? []),
      credits: data['credits'] ?? 0,
      memberships: rawMemberships
          .map((e) => MembershipEntry.fromMap(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toFirestore() => {
        'email': email,
        'name': name,
        if (photoUrl != null) 'photoUrl': photoUrl,
        'role': role,
        if (adminLevel != null) 'adminLevel': adminLevel,
        'adminPermissions': adminPermissions,
        'credits': credits,
        'memberships': memberships.map((m) => m.toMap()).toList(),
      };
}

import 'package:cloud_firestore/cloud_firestore.dart';

/// An admin-granted credit award — tracked on its own field, deliberately
/// kept separate from [MembershipEntry]/memberships. It isn't a real
/// purchased plan, so it shouldn't be forced through the same
/// plan-name-matching machinery: whether it unlocks unrestricted class
/// access is an explicit flag here ([unlocksAnyClass]), not an implicit
/// behavior baked into a magic plan name. If that policy ever needs to
/// change (e.g. admin credits should stop bypassing the Personal Training
/// gate), it's a one-place change here rather than a rewrite of how
/// memberships/plans are matched.
class AdminCreditGrant {
  final int credits;
  final DateTime expiryDate;
  final DateTime grantedAt;
  final bool unlocksAnyClass;

  const AdminCreditGrant({
    required this.credits,
    required this.expiryDate,
    required this.grantedAt,
    this.unlocksAnyClass = true,
  });

  bool get isActive => expiryDate.isAfter(DateTime.now());

  factory AdminCreditGrant.fromMap(Map<String, dynamic> map) {
    return AdminCreditGrant(
      credits: map['credits'] ?? 0,
      expiryDate: (map['expiryDate'] as Timestamp).toDate(),
      grantedAt: (map['grantedAt'] as Timestamp).toDate(),
      unlocksAnyClass: map['unlocksAnyClass'] ?? true,
    );
  }

  Map<String, dynamic> toMap() => {
        'credits': credits,
        'expiryDate': Timestamp.fromDate(expiryDate),
        'grantedAt': Timestamp.fromDate(grantedAt),
        'unlocksAnyClass': unlocksAnyClass,
      };
}

class MembershipEntry {
  final String id;
  final String planName;
  final int credits; // original amount granted at purchase — immutable
  final int creditsRemaining; // mutable per-plan bucket, decremented on booking
  final String status; // 'queued' | 'active' | 'expired'
  final DateTime startDate;
  final DateTime endDate;
  final DateTime purchasedAt;
  final DateTime? reminderSentAt; // renewal-reminder idempotency marker

  MembershipEntry({
    required this.id,
    required this.planName,
    required this.credits,
    required this.creditsRemaining,
    required this.status,
    required this.startDate,
    required this.endDate,
    required this.purchasedAt,
    this.reminderSentAt,
  });

  factory MembershipEntry.fromMap(Map<String, dynamic> map) {
    final purchasedAt = (map['purchasedAt'] as Timestamp).toDate();
    final hasStatus = map['status'] is String;
    return MembershipEntry(
      id: map['id'] as String? ??
          '${map['planName']}_${purchasedAt.millisecondsSinceEpoch}',
      planName: map['planName'] ?? '',
      credits: map['credits'] ?? 0,
      // Pre-rework entries never tracked a per-plan bucket/status — treat
      // them as void rather than guessing a balance from the old pooled
      // `credits` field (test data, no migration performed).
      creditsRemaining: hasStatus ? (map['creditsRemaining'] ?? 0) : 0,
      status: hasStatus ? map['status'] as String : 'expired',
      startDate: (map['startDate'] as Timestamp).toDate(),
      endDate: (map['endDate'] as Timestamp).toDate(),
      purchasedAt: purchasedAt,
      reminderSentAt: (map['reminderSentAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'planName': planName,
        'credits': credits,
        'creditsRemaining': creditsRemaining,
        'status': status,
        'startDate': Timestamp.fromDate(startDate),
        'endDate': Timestamp.fromDate(endDate),
        'purchasedAt': Timestamp.fromDate(purchasedAt),
        if (reminderSentAt != null)
          'reminderSentAt': Timestamp.fromDate(reminderSentAt!),
      };

  /// Returns a copy with mutable fields replaced — used by the
  /// transactional purchase/deduction/rollover logic to swap an entry in
  /// place within the memberships array (Firestore arrays have no
  /// per-element patch, so the whole array gets rewritten).
  MembershipEntry copyWith({
    int? creditsRemaining,
    String? status,
    DateTime? startDate,
    DateTime? endDate,
    DateTime? reminderSentAt,
  }) {
    return MembershipEntry(
      id: id,
      planName: planName,
      credits: credits,
      creditsRemaining: creditsRemaining ?? this.creditsRemaining,
      status: status ?? this.status,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      purchasedAt: purchasedAt,
      reminderSentAt: reminderSentAt ?? this.reminderSentAt,
    );
  }

  bool get isActive => status == 'active';
  bool get isQueued => status == 'queued';
  bool get isExpired => status == 'expired';

  /// Pure date check — whether "now" falls within this entry's scheduled
  /// window. Used only by the scheduled rollover job to decide status
  /// transitions; never used for credit/access gating (status is
  /// authoritative there, see [UserModel.activeMemberships]).
  bool get isDateWindowOpen =>
      !startDate.isAfter(DateTime.now()) && endDate.isAfter(DateTime.now());
}

class UserModel {
  final String uid;
  final String email;
  final String name;
  final String? photoUrl;
  final String? phone;
  final String role; // 'client', 'trainer', 'admin'
  final String? adminLevel; // 'super_admin', 'admin' — only for admin role
  final List<String> adminPermissions;
  final int credits; // admin-granted credit pool only — see AdminCreditGrant.
  // Plan credits live per-entry in memberships[].creditsRemaining.
  final List<MembershipEntry> memberships;
  final AdminCreditGrant? adminCreditGrant;

  UserModel({
    required this.uid,
    required this.email,
    required this.name,
    this.photoUrl,
    this.phone,
    this.role = 'client',
    this.adminLevel,
    this.adminPermissions = const [],
    this.credits = 0,
    this.memberships = const [],
    this.adminCreditGrant,
  });

  bool get isClient => role == 'client';
  bool get isTrainer => role == 'trainer';
  bool get isAdmin => role == 'admin';
  bool get isSuperAdmin => role == 'admin' && adminLevel == 'super_admin';

  bool hasPermission(String permission) {
    if (isSuperAdmin) return true;
    return adminPermissions.contains(permission);
  }

  /// At most one membership entry is ever `active` *per distinct planName*
  /// (an invariant maintained by the purchase flow, credit deduction, and
  /// the daily rollover job, each scoped to a single plan's own chain) —
  /// but a user can hold several different plans concurrently, each with
  /// its own active entry. So this is a list, not a single lookup.
  List<MembershipEntry> get activeMemberships =>
      memberships.where((m) => m.isActive).toList();

  /// The active entry for a specific plan, if the user holds one.
  MembershipEntry? activeMembershipFor(String planName) {
    for (final m in activeMemberships) {
      if (m.planName == planName) return m;
    }
    return null;
  }

  /// Plans purchased while another entry of the *same* plan was still
  /// active — queued to activate once their predecessor's date window ends
  /// (or pulled forward early if the active entry runs out of credits
  /// first). Different plans never queue behind each other.
  List<MembershipEntry> get queuedMemberships {
    final queued = memberships.where((m) => m.isQueued).toList();
    queued.sort((a, b) => a.startDate.compareTo(b.startDate));
    return queued;
  }

  /// Credits usable right now: every active plan's remaining bucket, summed,
  /// plus any admin-granted pool. Queued plans' credits aren't usable yet.
  int get totalUsableCredits =>
      activeMemberships.fold(0, (total, m) => total + m.creditsRemaining) +
      credits;

  /// The active admin-granted credit award, if any.
  AdminCreditGrant? get activeAdminGrant =>
      (adminCreditGrant != null && adminCreditGrant!.isActive)
          ? adminCreditGrant
          : null;

  /// True while an unexpired admin-granted credit award that's flagged to
  /// unlock unrestricted access exists — bypasses the Personal Training
  /// gate regardless of the user's actual plan(s).
  bool get hasUnrestrictedAccess =>
      activeAdminGrant?.unlocksAnyClass ?? false;

  factory UserModel.fromFirestore(Map<String, dynamic> data, String uid) {
    final rawMemberships = data['memberships'] as List<dynamic>? ?? [];
    final rawGrant = data['adminCreditGrant'] as Map<String, dynamic>?;
    return UserModel(
      uid: uid,
      email: data['email'] ?? '',
      name: data['name'] ?? '',
      photoUrl: data['photoUrl'],
      phone: data['phone'],
      role: data['role'] ?? 'client',
      adminLevel: data['adminLevel'],
      adminPermissions: List<String>.from(data['adminPermissions'] ?? []),
      credits: data['credits'] ?? 0,
      memberships: rawMemberships
          .map((e) => MembershipEntry.fromMap(e as Map<String, dynamic>))
          .toList(),
      adminCreditGrant:
          rawGrant != null ? AdminCreditGrant.fromMap(rawGrant) : null,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'email': email,
        'name': name,
        if (photoUrl != null) 'photoUrl': photoUrl,
        if (phone != null && phone!.isNotEmpty) 'phone': phone,
        'role': role,
        if (adminLevel != null) 'adminLevel': adminLevel,
        'adminPermissions': adminPermissions,
        'credits': credits,
        'memberships': memberships.map((m) => m.toMap()).toList(),
        if (adminCreditGrant != null)
          'adminCreditGrant': adminCreditGrant!.toMap(),
      };
}

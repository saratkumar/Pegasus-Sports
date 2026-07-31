import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/user_model.dart';

/// One plan's outcome from [UserService.sendRenewalReminderNow] — a user
/// can hold several concurrently-active plans, so a single button tap can
/// yield one result per plan. [reason] is null on success, otherwise one
/// of: already-queued, no-email.
class ReminderResult {
  final String planName;
  final bool sent;
  final String? reason;

  ReminderResult({required this.planName, required this.sent, this.reason});
}

class UserService {
  static final _db = FirebaseFirestore.instance;
  // Cloud Functions are deployed to asia-southeast1 (see functions/index.js
  // setGlobalOptions) — the default FirebaseFunctions.instance targets
  // us-central1 and would silently fail to find the function.
  static final _functions =
      FirebaseFunctions.instanceFor(region: 'asia-southeast1');

  static Future<UserModel?> getCurrentUser() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    return getUser(uid);
  }

  static Future<UserModel?> getUser(String uid) async {
    final doc = await _db.collection('users').doc(uid).get();
    if (!doc.exists) return null;
    return UserModel.fromFirestore(doc.data()!, uid);
  }

  static Stream<UserModel?> currentUserStream() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return Stream.value(null);
    return _db.collection('users').doc(uid).snapshots().map((doc) {
      if (!doc.exists) return null;
      return UserModel.fromFirestore(doc.data()!, uid);
    });
  }

  static Future<List<UserModel>> getAllUsers() async {
    final snap = await _db.collection('users').get();
    return snap.docs
        .map((d) => UserModel.fromFirestore(d.data(), d.id))
        .toList();
  }

  static Future<List<UserModel>> getUsersByRole(String role) async {
    final snap =
        await _db.collection('users').where('role', isEqualTo: role).get();
    return snap.docs
        .map((d) => UserModel.fromFirestore(d.data(), d.id))
        .toList();
  }

  static Future<void> updateRole(
    String uid,
    String role, {
    String? adminLevel,
    List<String>? adminPermissions,
  }) async {
    final data = <String, dynamic>{'role': role};
    if (adminLevel != null) data['adminLevel'] = adminLevel;
    if (adminPermissions != null) data['adminPermissions'] = adminPermissions;
    await _db.collection('users').doc(uid).update(data);
  }

  static Future<void> addCredits(String uid, int amount) async {
    await _db.collection('users').doc(uid).update({
      'credits': FieldValue.increment(amount),
    });
  }

  /// Self-service profile edit — name and phone only. Email is intentionally
  /// not editable here (it's tied to the sign-in identity).
  static Future<void> updateProfile({
    required String uid,
    required String name,
    String? phone,
  }) async {
    await _db.collection('users').doc(uid).update({
      'name': name,
      'phone': phone,
    });
  }

  /// Creates a pre-registration invitation. When the invited email first
  /// signs in via Google, the login flow consumes this and applies the
  /// pre-set role, phone, and initial credits.
  static Future<void> createInvitation({
    required String email,
    required String name,
    required String phone,
    required String role,
    required int initialCredits,
    String? adminLevel,
  }) async {
    await _db
        .collection('invitations')
        .doc(email.toLowerCase().trim())
        .set({
      'email': email.toLowerCase().trim(),
      'name': name,
      'phone': phone,
      'role': role,
      if (adminLevel != null && adminLevel.isNotEmpty) 'adminLevel': adminLevel,
      'initialCredits': initialCredits,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Reads and deletes the invitation for this email (one-time use).
  static Future<Map<String, dynamic>?> consumeInvitation(String email) async {
    final doc = await _db
        .collection('invitations')
        .doc(email.toLowerCase().trim())
        .get();
    if (!doc.exists) return null;
    final data = Map<String, dynamic>.from(doc.data()!);
    await doc.reference.delete();
    return data;
  }

  /// Deducts one credit for a booking. [allowedPlanNames] is the booked
  /// class's plan whitelist (empty = unrestricted, any plan/pool works).
  /// Draws from an eligible active plan's bucket first; if that's exhausted
  /// (but its date window hasn't ended — a rollover just hasn't run yet,
  /// that's handled separately), pulls the earliest eligible queued plan of
  /// the same chain forward early to cover it; finally falls back to the
  /// admin-granted pool, which is always unrestricted regardless of
  /// [allowedPlanNames] (mirrors [UserModel.hasUnrestrictedAccess]). Returns
  /// the membership entry id the credit was drawn from, or null if it came
  /// from the admin pool — callers should store this on the booking/
  /// waiting-list doc (alongside `creditsUsed`) so a later refund can be
  /// routed back to the correct bucket via [refundCredit]. Runs as a
  /// transaction since, unlike a flat pooled decrement, this branches on
  /// which bucket to draw from and can flip a queued plan to active — not
  /// safe as a bare increment under concurrent bookings.
  static Future<String?> deductCredit(
    String uid, {
    List<String> allowedPlanNames = const [],
  }) {
    final userRef = _db.collection('users').doc(uid);
    return _db.runTransaction<String?>((tx) => _selectAndDeductWithinTx(
        tx, userRef,
        allowedPlanNames: allowedPlanNames));
  }

  /// Runs [writeDoc] (typically one `tx.set` for a new booking or
  /// waiting-list doc) inside the same transaction as the credit
  /// deduction, so the doc is never created without its credit actually
  /// being deducted, or vice versa — a plain "create doc, then deduct"
  /// sequence could otherwise leave an orphaned doc if the deduction later
  /// fails (e.g. a race lost the last credit to a concurrent booking).
  /// [writeDoc] is handed the resolved credit source entry id (null =
  /// drawn from the admin pool) to store alongside `creditsUsed` on the
  /// doc, so a later cancellation can refund it via [refundCredit].
  /// [allowedPlanNames] — see [deductCredit].
  static Future<void> deductCreditAndWrite(
    String uid,
    void Function(Transaction tx, String? sourceEntryId) writeDoc, {
    List<String> allowedPlanNames = const [],
  }) async {
    final userRef = _db.collection('users').doc(uid);
    await _db.runTransaction((tx) async {
      final source = await _selectAndDeductWithinTx(tx, userRef,
          allowedPlanNames: allowedPlanNames);
      writeDoc(tx, source);
    });
  }

  static bool _isEligiblePlan(MembershipEntry m, List<String> allowedPlanNames) =>
      allowedPlanNames.isEmpty || allowedPlanNames.contains(m.planName);

  static Future<String?> _selectAndDeductWithinTx(
    Transaction tx,
    DocumentReference<Map<String, dynamic>> userRef, {
    List<String> allowedPlanNames = const [],
  }) async {
    final snap = await tx.get(userRef);
    final data = snap.data();
    if (data == null) throw StateError('User not found');
    final memberships = _parseMemberships(data);
    final pooledCredits = data['credits'] as int? ?? 0;
    final now = DateTime.now();

    // An eligible active entry whose date window is genuinely still open
    // (re-checked against `now`, not just `status`, since a rollover-lag
    // window can leave a stale 'active' entry past its endDate) and that
    // still has credit.
    final activeWithCreditsIdx = memberships.indexWhere((m) =>
        m.isActive &&
        m.endDate.isAfter(now) &&
        _isEligiblePlan(m, allowedPlanNames) &&
        m.creditsRemaining > 0);

    if (activeWithCreditsIdx != -1) {
      final entry = memberships[activeWithCreditsIdx];
      memberships[activeWithCreditsIdx] =
          entry.copyWith(creditsRemaining: entry.creditsRemaining - 1);
      tx.update(userRef, {'memberships': _toMaps(memberships)});
      return entry.id;
    }

    final queuedIdx = _earliestQueuedWithCredits(memberships, allowedPlanNames);
    if (queuedIdx != -1) {
      final promoted = memberships[queuedIdx];
      // Step down the entry this one chains behind — same planName only,
      // never an unrelated plan's active entry.
      final sameChainActiveIdx = memberships.indexWhere(
          (m) => m.isActive && m.planName == promoted.planName);
      if (sameChainActiveIdx != -1 &&
          memberships[sameChainActiveIdx].endDate.isAfter(now)) {
        memberships[sameChainActiveIdx] =
            memberships[sameChainActiveIdx].copyWith(status: 'expired');
      }
      memberships[queuedIdx] = promoted.copyWith(
        status: 'active',
        creditsRemaining: promoted.creditsRemaining - 1,
      );
      tx.update(userRef, {'memberships': _toMaps(memberships)});
      return promoted.id;
    }

    if (pooledCredits > 0) {
      tx.update(userRef, {'credits': FieldValue.increment(-1)});
      return null;
    }

    throw StateError('No credits available');
  }

  /// Read-only precheck mirroring [deductCredit]'s bucket-selection logic,
  /// used to short-circuit the "no credits" UI message before attempting a
  /// booking. The transaction in [deductCredit] remains authoritative.
  /// [allowedPlanNames] — see [deductCredit].
  static Future<bool> hasEnoughCredits(
    String uid, {
    List<String> allowedPlanNames = const [],
  }) async {
    final user = await getUser(uid);
    if (user == null) return false;
    final now = DateTime.now();

    final hasActiveCredit = user.activeMemberships.any((m) =>
        _isEligiblePlan(m, allowedPlanNames) &&
        m.endDate.isAfter(now) &&
        m.creditsRemaining > 0);
    if (hasActiveCredit) return true;

    final hasQueuedCredit = user.queuedMemberships.any(
        (m) => _isEligiblePlan(m, allowedPlanNames) && m.creditsRemaining > 0);
    if (hasQueuedCredit) return true;

    return user.credits > 0;
  }

  /// Refunds a credit from a cancelled booking/waiting-list entry back to
  /// the plan bucket it was drawn from ([sourceEntryId], as returned by
  /// [deductCredit]) — or to the admin-granted pool if [sourceEntryId] is
  /// null (never drawn from a plan) or that plan has since expired (its
  /// credits were already forfeited per the no-carryover rule; reviving
  /// them would let an old plan's credit leak into a new period).
  static Future<void> refundCredit(
    String uid, {
    required String? sourceEntryId,
    int amount = 1,
  }) async {
    final userRef = _db.collection('users').doc(uid);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(userRef);
      final data = snap.data();
      if (data == null) return;
      final memberships = _parseMemberships(data);

      final idx = sourceEntryId == null
          ? -1
          : memberships.indexWhere((m) => m.id == sourceEntryId && !m.isExpired);

      if (idx == -1) {
        tx.update(userRef, {'credits': FieldValue.increment(amount)});
        return;
      }

      final entry = memberships[idx];
      final restored =
          (entry.creditsRemaining + amount).clamp(0, entry.credits);
      memberships[idx] = entry.copyWith(creditsRemaining: restored);
      tx.update(userRef, {'memberships': _toMaps(memberships)});
    });
  }

  /// Queues or activates a newly purchased plan. If the user has no
  /// currently-usable plan (nothing active with a still-open date window,
  /// nothing already queued), the new plan activates immediately. Otherwise
  /// it queues behind the current "tail" of the chain — its startDate is
  /// set to the tail's endDate, so it only becomes usable once its
  /// predecessor's date window ends (or is pulled forward early by
  /// [deductCredit] if the predecessor runs out of credits first). Runs as
  /// a transaction since the decision depends on the current chain state.
  static Future<void> purchaseMembership(
    String uid, {
    required String planName,
    required int credits,
    required int validityDays,
  }) async {
    final userRef = _db.collection('users').doc(uid);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(userRef);
      final memberships = _parseMemberships(snap.data() ?? {});
      final now = DateTime.now();

      final tail = _resolveQueueTail(memberships, now, planName);
      final startDate = tail?.endDate ?? now;
      final status = tail == null ? 'active' : 'queued';
      final endDate =
          startDate.add(Duration(days: validityDays > 0 ? validityDays : 365));

      final newEntry = MembershipEntry(
        id: _db.collection('users').doc().id,
        planName: planName,
        credits: credits,
        creditsRemaining: credits,
        status: status,
        startDate: startDate,
        endDate: endDate,
        purchasedAt: now,
      );

      tx.update(userRef, {
        'memberships': _toMaps([...memberships, newEntry]),
      });
    });
  }

  static List<MembershipEntry> _parseMemberships(Map<String, dynamic> data) {
    final raw = data['memberships'] as List<dynamic>? ?? [];
    return raw
        .map((e) => MembershipEntry.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  static List<Map<String, dynamic>> _toMaps(List<MembershipEntry> entries) =>
      entries.map((m) => m.toMap()).toList();

  /// The entry a new purchase of [planName] should queue behind: the queued
  /// entry of the *same plan* with the latest startDate if one exists
  /// (chaining behind it), else that plan's currently active entry if its
  /// date window is still genuinely open (re-checked against `now`, not
  /// just its `status`, to cover the window where a plan's date has lapsed
  /// but the nightly rollover hasn't run yet), else null (nothing to queue
  /// behind — activate immediately). Every plan follows its own route:
  /// entries of other plan names never affect this chain.
  static MembershipEntry? _resolveQueueTail(
    List<MembershipEntry> memberships,
    DateTime now,
    String planName,
  ) {
    final sameChain = memberships.where((m) => m.planName == planName);
    final queued = sameChain.where((m) => m.isQueued).toList()
      ..sort((a, b) => a.startDate.compareTo(b.startDate));
    if (queued.isNotEmpty) return queued.last;

    for (final m in sameChain) {
      if (m.isActive && m.endDate.isAfter(now)) return m;
    }
    return null;
  }

  /// Index of the queued entry — restricted to [allowedPlanNames] if
  /// non-empty — with the earliest startDate that still has credits left,
  /// or -1 if none. Used by [deductCredit]'s pull-forward.
  static int _earliestQueuedWithCredits(
    List<MembershipEntry> memberships,
    List<String> allowedPlanNames,
  ) {
    final candidates = <MapEntry<int, MembershipEntry>>[];
    for (var i = 0; i < memberships.length; i++) {
      final m = memberships[i];
      if (m.isQueued &&
          m.creditsRemaining > 0 &&
          _isEligiblePlan(m, allowedPlanNames)) {
        candidates.add(MapEntry(i, m));
      }
    }
    if (candidates.isEmpty) return -1;
    candidates.sort((a, b) => a.value.startDate.compareTo(b.value.startDate));
    return candidates.first.key;
  }

  /// Overwrites a user's full memberships list — used by the admin "edit
  /// plan dates" UI. Firestore arrays have no per-entry key/id, so a single
  /// entry's dates can't be patched in place; the caller mutates its local
  /// copy of the list and this replaces the whole array with it.
  static Future<void> updateMemberships(
    String uid,
    List<MembershipEntry> memberships,
  ) async {
    await _db.collection('users').doc(uid).update({
      'memberships': memberships.map((m) => m.toMap()).toList(),
    });
  }

  /// Admin-only "Send Renewal Reminder" action — triggers the
  /// `sendRenewalReminderNow` Cloud Function, which sends the same email
  /// the nightly T-14 sweep would for every plan the user currently has
  /// active, immediately and regardless of how many days are actually left
  /// (an explicit manual trigger is its own confirmation). A plan is
  /// skipped individually if it already has a renewal queued behind it.
  /// Returns one `ReminderResult` per active plan the user holds (empty if
  /// they have no active plan at all).
  static Future<List<ReminderResult>> sendRenewalReminderNow(
      String uid) async {
    final result =
        await _functions.httpsCallable('sendRenewalReminderNow').call({
      'uid': uid,
    });
    final results = (result.data as Map)['results'] as List;
    return results
        .map((r) => ReminderResult(
              planName: r['planName'] as String,
              sent: r['sent'] as bool,
              reason: r['reason'] as String?,
            ))
        .toList();
  }

  /// Records an admin-granted credit increase — separate from
  /// [purchaseMembership] on purpose (see AdminCreditGrant's doc comment).
  /// Replaces any previous grant rather than accumulating a history; only
  /// the current one matters for access checks.
  static Future<void> grantAdminCredit(
    String uid, {
    required int creditDelta,
    required DateTime expiryDate,
    bool unlocksAnyClass = true,
  }) async {
    final grant = AdminCreditGrant(
      credits: creditDelta,
      expiryDate: expiryDate,
      grantedAt: DateTime.now(),
      unlocksAnyClass: unlocksAnyClass,
    );
    await _db.collection('users').doc(uid).update({
      'credits': FieldValue.increment(creditDelta),
      'adminCreditGrant': grant.toMap(),
    });
  }
}

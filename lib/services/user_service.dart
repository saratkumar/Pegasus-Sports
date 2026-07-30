import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/user_model.dart';

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

  /// Deducts one credit for a booking. Draws from the active plan's bucket
  /// first; if that's exhausted (but its date window hasn't ended — a
  /// rollover just hasn't run yet, that's handled separately), pulls the
  /// earliest queued plan forward early to cover it; finally falls back to
  /// the admin-granted pool. Returns the membership entry id the credit was
  /// drawn from, or null if it came from the admin pool — callers should
  /// store this on the booking/waiting-list doc (alongside `creditsUsed`)
  /// so a later refund can be routed back to the correct bucket via
  /// [refundCredit]. Runs as a transaction since, unlike a flat pooled
  /// decrement, this branches on which bucket to draw from and can flip a
  /// queued plan to active — not safe as a bare increment under concurrent
  /// bookings.
  static Future<String?> deductCredit(String uid) {
    final userRef = _db.collection('users').doc(uid);
    return _db.runTransaction<String?>(
        (tx) => _selectAndDeductWithinTx(tx, userRef));
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
  static Future<void> deductCreditAndWrite(
    String uid,
    void Function(Transaction tx, String? sourceEntryId) writeDoc,
  ) async {
    final userRef = _db.collection('users').doc(uid);
    await _db.runTransaction((tx) async {
      final source = await _selectAndDeductWithinTx(tx, userRef);
      writeDoc(tx, source);
    });
  }

  static Future<String?> _selectAndDeductWithinTx(
    Transaction tx,
    DocumentReference<Map<String, dynamic>> userRef,
  ) async {
    final snap = await tx.get(userRef);
    final data = snap.data();
    if (data == null) throw StateError('User not found');
    final memberships = _parseMemberships(data);
    final pooledCredits = data['credits'] as int? ?? 0;
    final now = DateTime.now();

    var activeIdx = memberships.indexWhere((m) => m.isActive);
    if (activeIdx != -1 && !memberships[activeIdx].endDate.isAfter(now)) {
      activeIdx = -1; // date window has actually lapsed; rollover hasn't run yet
    }

    if (activeIdx != -1 && memberships[activeIdx].creditsRemaining > 0) {
      final entry = memberships[activeIdx];
      memberships[activeIdx] =
          entry.copyWith(creditsRemaining: entry.creditsRemaining - 1);
      tx.update(userRef, {'memberships': _toMaps(memberships)});
      return entry.id;
    }

    final queuedIdx = _earliestQueuedWithCredits(memberships);
    if (queuedIdx != -1) {
      if (activeIdx != -1) {
        memberships[activeIdx] =
            memberships[activeIdx].copyWith(status: 'expired');
      }
      final entry = memberships[queuedIdx];
      memberships[queuedIdx] = entry.copyWith(
        status: 'active',
        creditsRemaining: entry.creditsRemaining - 1,
      );
      tx.update(userRef, {'memberships': _toMaps(memberships)});
      return entry.id;
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
  static Future<bool> hasEnoughCredits(String uid) async {
    final user = await getUser(uid);
    if (user == null) return false;
    final now = DateTime.now();
    final active = user.activeMembership;
    if (active != null &&
        active.endDate.isAfter(now) &&
        active.creditsRemaining > 0) {
      return true;
    }
    if (user.queuedMemberships.any((m) => m.creditsRemaining > 0)) return true;
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

      final tail = _resolveQueueTail(memberships, now);
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

  /// The entry a new purchase should queue behind: the queued entry with
  /// the latest startDate if one exists (chaining behind it), else the
  /// currently active entry if its date window is still genuinely open
  /// (re-checked against `now`, not just its `status`, to cover the window
  /// where a plan's date has lapsed but the nightly rollover hasn't run
  /// yet), else null (nothing to queue behind — activate immediately).
  static MembershipEntry? _resolveQueueTail(
    List<MembershipEntry> memberships,
    DateTime now,
  ) {
    final queued = memberships.where((m) => m.isQueued).toList()
      ..sort((a, b) => a.startDate.compareTo(b.startDate));
    if (queued.isNotEmpty) return queued.last;

    for (final m in memberships) {
      if (m.isActive && m.endDate.isAfter(now)) return m;
    }
    return null;
  }

  /// Index of the queued entry with the earliest startDate that still has
  /// credits left, or -1 if none. Used by [deductCredit]'s pull-forward.
  static int _earliestQueuedWithCredits(List<MembershipEntry> memberships) {
    final candidates = <MapEntry<int, MembershipEntry>>[];
    for (var i = 0; i < memberships.length; i++) {
      final m = memberships[i];
      if (m.isQueued && m.creditsRemaining > 0) candidates.add(MapEntry(i, m));
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
  /// the nightly T-14 sweep would, immediately and regardless of how many
  /// days are actually left (an explicit manual trigger is its own
  /// confirmation). Still skips if the user's already queued a renewal.
  /// Returns `(sent, reason)` — `reason` is null on success, otherwise one
  /// of: no-active-plan, already-queued, no-email.
  static Future<(bool sent, String? reason)> sendRenewalReminderNow(
      String uid) async {
    final result =
        await _functions.httpsCallable('sendRenewalReminderNow').call({
      'uid': uid,
    });
    final data = result.data as Map;
    return (data['sent'] as bool, data['reason'] as String?);
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

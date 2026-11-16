import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../models/user_model.dart';
import '../utils/drive_image.dart';

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

/// Thrown by [UserService.upsertFromCredential] when the signed-in email is
/// neither invited nor an imported Glofox member, or belongs to a
/// deactivated account. By the time it's thrown the user is signed out.
class NotInvitedException implements Exception {
  final String email;
  final bool deactivated;
  NotInvitedException(this.email, {this.deactivated = false});
  @override
  String toString() => 'NotInvitedException($email, deactivated: $deactivated)';
}

/// Why the last sign-in was refused — see [UserService.accessDenied].
class AccessDenial {
  final String email;
  final bool deactivated;
  const AccessDenial(this.email, {this.deactivated = false});
}

class UserService {
  static final _db = FirebaseFirestore.instance;

  /// Set to the rejected email when an uninvited person tries to sign in.
  /// Lives here rather than in LoginScreen's state because the rejection
  /// lands after the auth gate has already swapped LoginScreen out — the
  /// freshly-mounted LoginScreen reads this to explain what happened.
  static final accessDenied = ValueNotifier<AccessDenial?>(null);
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

  /// Creates the `users/{uid}` doc on first sign-in (consuming any pending
  /// invitation), or merges updated profile fields on repeat sign-ins.
  /// [displayName] lets a caller supply the name explicitly instead of
  /// relying on `result.user!.displayName` (e.g. Apple, which Firebase
  /// doesn't populate that field for). Shared by every sign-in entry point —
  /// mobile's LoginScreen and the web shop's deferred sign-in prompt — so
  /// the invitation/role logic lives in exactly one place.
  static Future<void> upsertFromCredential(
    UserCredential result, {
    String? displayName,
  }) async {
    final uid = result.user!.uid;
    final email = result.user!.email ?? '';
    final name = displayName ?? result.user!.displayName ?? '';
    final photoUrl = result.user!.photoURL ?? '';

    final userRef = _db.collection('users').doc(uid);
    final existing = await userRef.get();

    if (!existing.exists) {
      // Sign-up is invite-only: a first sign-in must match either an
      // admin-created invitation or a member imported from Glofox
      // (importedPending, handed over by the onUserCreated function).
      // firestore.rules enforces the same check on the users/{uid} create,
      // so this is the friendly path, not the only gate.
      final emailKey = email.toLowerCase().trim();
      final inviteRef = _db.collection('invitations').doc(emailKey);
      final invite = emailKey.isEmpty ? null : (await inviteRef.get()).data();

      String? importedFrom;
      if (invite == null && emailKey.isNotEmpty) {
        final matches = await _db
            .collection('users')
            .where('email', isEqualTo: emailKey)
            .get();
        for (final d in matches.docs) {
          if (d.id != uid && d.data()['importedPending'] == true) {
            importedFrom = d.id;
            break;
          }
        }
      }

      if (invite == null && importedFrom == null) {
        await _rejectUninvited(result.user!);
        throw NotInvitedException(email);
      }

      // Role (including 'admin'/adminLevel) comes entirely from the
      // invitation, never from a hardcoded email list.
      final role = invite?['role'] as String? ?? 'client';
      final adminLevel = invite?['adminLevel'] as String?;

      // One batch so the invitation is consumed only if the profile is
      // created — and so the rules' exists() check on the invitation sees it
      // (rules evaluate exists() against the pre-batch state).
      final batch = _db.batch();
      batch.set(userRef, {
        'email': email,
        'name': (invite?['name'] as String?)?.isNotEmpty == true
            ? invite!['name']
            : name,
        'photoUrl': photoUrl,
        if ((invite?['phone'] as String?)?.isNotEmpty == true)
          'phone': invite!['phone'],
        'role': role,
        if (adminLevel != null) 'adminLevel': adminLevel,
        'adminPermissions': <String>[],
        'credits': invite?['initialCredits'] as int? ?? 0,
        'memberships': <Map<String, dynamic>>[],
        if (importedFrom != null) 'importedFrom': importedFrom,
      });
      if (invite != null) batch.delete(inviteRef);
      await batch.commit();
    } else if (existing.data()?['isActive'] == false) {
      // Deactivated by an admin. Sign out but keep the Auth account: its uid
      // is what links their bookings/plans/history, so reactivating them
      // later gives back the same account with everything intact.
      await signOutDeactivated(email);
      throw NotInvitedException(email, deactivated: true);
    } else {
      // Update mutable profile fields only; role/adminLevel/credits are
      // preserved as-is — Firestore is the sole source of truth for them.
      await userRef.set({
        'email': email,
        if (name.isNotEmpty) 'name': name,
        if (photoUrl.isNotEmpty) 'photoUrl': photoUrl,
      }, SetOptions(merge: true));
    }
  }

  static Future<List<UserModel>> getAllUsers() async {
    final snap = await _db.collection('users').get();
    return sortByName(snap.docs
        .map((d) => UserModel.fromFirestore(d.data(), d.id))
        .toList());
  }

  static Future<List<UserModel>> getUsersByRole(String role) async {
    final snap =
        await _db.collection('users').where('role', isEqualTo: role).get();
    return sortByName(snap.docs
        .map((d) => UserModel.fromFirestore(d.data(), d.id))
        .toList());
  }

  /// Alphabetical by name (case-insensitive), falling back to email for
  /// accounts with no name — the order every user/client list shows.
  static List<UserModel> sortByName(List<UserModel> users) {
    String key(UserModel u) =>
        (u.name.trim().isNotEmpty ? u.name : u.email).trim().toLowerCase();
    return users..sort((a, b) => key(a).compareTo(key(b)));
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

  /// Saves a trainer's public coach profile — shown to members from the
  /// class timetable. [photoUrl] is typically a Google Drive share link,
  /// stored as Drive's direct image URL so it renders in the app.
  static Future<void> updateCoachProfile({
    required String uid,
    required String photoUrl,
    required String bio,
  }) async {
    final photo = photoUrl.trim();
    await _db.collection('users').doc(uid).update({
      'coachPhotoUrl': photo.isEmpty ? FieldValue.delete() : driveDirectImageUrl(photo),
      'coachBio': bio.trim().isEmpty ? FieldValue.delete() : bio.trim(),
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

  /// Undoes an uninvited sign-in: deletes the Auth account Firebase just
  /// created (so strangers don't pile up in Authentication) and signs out,
  /// leaving [accessDenied] set for LoginScreen to explain.
  static Future<void> _rejectUninvited(User user) async {
    accessDenied.value = AccessDenial(user.email ?? '');
    try {
      await user.delete();
    } catch (_) {
      // Already-existing Auth account (e.g. a member whose profile an admin
      // removed) or a transient failure — signing out is enough.
    }
    await _signOutEverywhere();
  }

  /// Signs out a deactivated account WITHOUT deleting it (the uid must
  /// survive for reactivation). Also called by the app's auth gates when an
  /// admin deactivates someone who is already signed in.
  static Future<void> signOutDeactivated(String email) async {
    accessDenied.value = AccessDenial(email, deactivated: true);
    await _signOutEverywhere();
  }

  /// Admin action from User Management. Nothing is deleted either way.
  static Future<void> setActive(String uid, bool active) => _db
      .collection('users')
      .doc(uid)
      .update({'isActive': active});

  static Future<void> _signOutEverywhere() async {
    await FirebaseAuth.instance.signOut();
    if (!kIsWeb) {
      // Otherwise the next tap silently reuses the same Google account
      // instead of showing the account picker.
      try {
        await GoogleSignIn().signOut();
      } catch (_) {}
    }
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
  ///
  /// [excludedPlanNames] are never drawn from (junior packages when the
  /// account holder books for themselves); [preferredPlanNames] are tried
  /// first before any other eligible plan (junior packages when booking a
  /// child) — see [BookingService.creditRulesFor].
  static Future<String?> deductCredit(
    String uid, {
    List<String> allowedPlanNames = const [],
    Set<String> excludedPlanNames = const {},
    Set<String> preferredPlanNames = const {},
  }) {
    final userRef = _db.collection('users').doc(uid);
    return _db.runTransaction<String?>((tx) => _selectAndDeductWithinTx(
        tx, userRef,
        allowedPlanNames: allowedPlanNames,
        excludedPlanNames: excludedPlanNames,
        preferredPlanNames: preferredPlanNames));
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
  /// [allowedPlanNames]/[excludedPlanNames]/[preferredPlanNames] — see
  /// [deductCredit].
  static Future<void> deductCreditAndWrite(
    String uid,
    void Function(Transaction tx, String? sourceEntryId) writeDoc, {
    List<String> allowedPlanNames = const [],
    Set<String> excludedPlanNames = const {},
    Set<String> preferredPlanNames = const {},
  }) async {
    final userRef = _db.collection('users').doc(uid);
    await _db.runTransaction((tx) async {
      final source = await _selectAndDeductWithinTx(tx, userRef,
          allowedPlanNames: allowedPlanNames,
          excludedPlanNames: excludedPlanNames,
          preferredPlanNames: preferredPlanNames);
      writeDoc(tx, source);
    });
  }

  static bool _isEligiblePlan(
    MembershipEntry m,
    List<String> allowedPlanNames, [
    Set<String> excludedPlanNames = const {},
  ]) =>
      !excludedPlanNames.contains(m.planName) &&
      (allowedPlanNames.isEmpty || allowedPlanNames.contains(m.planName));

  static Future<String?> _selectAndDeductWithinTx(
    Transaction tx,
    DocumentReference<Map<String, dynamic>> userRef, {
    List<String> allowedPlanNames = const [],
    Set<String> excludedPlanNames = const {},
    Set<String> preferredPlanNames = const {},
  }) async =>
      (await _selectAndDeductManyWithinTx(tx, userRef, 1,
              allowedPlanNames: allowedPlanNames,
              excludedPlanNames: excludedPlanNames,
              preferredPlanNames: preferredPlanNames))
          .single;

  /// Deducts [count] credits in one transaction — one per attendee when a
  /// member brings guests on their own credits. Firestore transactions
  /// can't read after writing, so the user doc is read once and every
  /// credit is picked in memory (each pick sees the previous ones), then
  /// written once. Returns each credit's source entry id (null = admin
  /// pool) in order, for per-booking refunds. Throws if fewer than [count]
  /// credits are available — nothing is deducted in that case.
  static Future<List<String?>> _selectAndDeductManyWithinTx(
    Transaction tx,
    DocumentReference<Map<String, dynamic>> userRef,
    int count, {
    List<String> allowedPlanNames = const [],
    Set<String> excludedPlanNames = const {},
    Set<String> preferredPlanNames = const {},
  }) async {
    final snap = await tx.get(userRef);
    final data = snap.data();
    if (data == null) throw StateError('User not found');
    final memberships = _parseMemberships(data);
    var pooledCredits = data['credits'] as int? ?? 0;
    final now = DateTime.now();
    final sources = <String?>[];
    var membershipsChanged = false;
    var pooledUsed = 0;

    // An eligible active entry whose date window is genuinely still open
    // (re-checked against `now`, not just `status`, since a rollover-lag
    // window can leave a stale 'active' entry past its endDate) and that
    // still has credit.
    bool activeWithCredits(MembershipEntry m) =>
        m.isActive &&
        m.endDate.isAfter(now) &&
        _isEligiblePlan(m, allowedPlanNames, excludedPlanNames) &&
        m.creditsRemaining > 0;

    for (var i = 0; i < count; i++) {
      var activeWithCreditsIdx = memberships.indexWhere((m) =>
          preferredPlanNames.contains(m.planName) && activeWithCredits(m));
      if (activeWithCreditsIdx == -1) {
        activeWithCreditsIdx = memberships.indexWhere(activeWithCredits);
      }

      if (activeWithCreditsIdx != -1) {
        final entry = memberships[activeWithCreditsIdx];
        memberships[activeWithCreditsIdx] =
            entry.copyWith(creditsRemaining: entry.creditsRemaining - 1);
        membershipsChanged = true;
        sources.add(entry.id);
        continue;
      }

      var queuedIdx = preferredPlanNames.isEmpty
          ? -1
          : _earliestQueuedWithCredits(memberships, allowedPlanNames,
              excludedPlanNames: excludedPlanNames,
              onlyPlanNames: preferredPlanNames);
      if (queuedIdx == -1) {
        queuedIdx = _earliestQueuedWithCredits(memberships, allowedPlanNames,
            excludedPlanNames: excludedPlanNames);
      }
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
        membershipsChanged = true;
        sources.add(promoted.id);
        continue;
      }

      if (pooledCredits > 0) {
        pooledCredits--;
        pooledUsed++;
        sources.add(null);
        continue;
      }

      throw StateError('No credits available');
    }

    tx.update(userRef, {
      if (membershipsChanged) 'memberships': _toMaps(memberships),
      if (pooledUsed > 0) 'credits': FieldValue.increment(-pooledUsed),
    });
    return sources;
  }

  /// Like [deductCreditAndWrite], for [count] credits at once: [writeDocs]
  /// gets one source entry id per credit (see [_selectAndDeductManyWithinTx])
  /// and writes all the docs in the same transaction — either every
  /// booking is created with its credit, or none are.
  static Future<void> deductCreditsAndWrite(
    String uid,
    int count,
    void Function(Transaction tx, List<String?> sourceEntryIds) writeDocs, {
    List<String> allowedPlanNames = const [],
    Set<String> excludedPlanNames = const {},
  }) async {
    final userRef = _db.collection('users').doc(uid);
    await _db.runTransaction((tx) async {
      final sources = await _selectAndDeductManyWithinTx(tx, userRef, count,
          allowedPlanNames: allowedPlanNames,
          excludedPlanNames: excludedPlanNames);
      writeDocs(tx, sources);
    });
  }

  /// Read-only count of credits usable for a class right now — active
  /// plans with an open window, queued plans, and the admin pool — mirroring
  /// [_selectAndDeductManyWithinTx]'s buckets. Used to cap how many guests a
  /// member can bring; the deduction transaction remains authoritative.
  static Future<int> usableCreditCount(
    String uid, {
    List<String> allowedPlanNames = const [],
    Set<String> excludedPlanNames = const {},
  }) async {
    final user = await getUser(uid);
    if (user == null) return 0;
    final now = DateTime.now();
    int positive(int n) => n > 0 ? n : 0;
    final fromActive = user.activeMemberships
        .where((m) =>
            _isEligiblePlan(m, allowedPlanNames, excludedPlanNames) &&
            m.endDate.isAfter(now))
        .fold<int>(0, (total, m) => total + positive(m.creditsRemaining));
    final fromQueued = user.queuedMemberships
        .where((m) => _isEligiblePlan(m, allowedPlanNames, excludedPlanNames))
        .fold<int>(0, (total, m) => total + positive(m.creditsRemaining));
    return fromActive + fromQueued + positive(user.credits);
  }

  /// Read-only precheck mirroring [deductCredit]'s bucket-selection logic,
  /// used to short-circuit the "no credits" UI message before attempting a
  /// booking. The transaction in [deductCredit] remains authoritative.
  /// [allowedPlanNames]/[excludedPlanNames] — see [deductCredit].
  static Future<bool> hasEnoughCredits(
    String uid, {
    List<String> allowedPlanNames = const [],
    Set<String> excludedPlanNames = const {},
  }) async {
    final user = await getUser(uid);
    if (user == null) return false;
    final now = DateTime.now();

    final hasActiveCredit = user.activeMemberships.any((m) =>
        _isEligiblePlan(m, allowedPlanNames, excludedPlanNames) &&
        m.endDate.isAfter(now) &&
        m.creditsRemaining > 0);
    if (hasActiveCredit) return true;

    final hasQueuedCredit = user.queuedMemberships.any((m) =>
        _isEligiblePlan(m, allowedPlanNames, excludedPlanNames) &&
        m.creditsRemaining > 0);
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
  /// or -1 if none. Used by [deductCredit]'s pull-forward. [onlyPlanNames],
  /// if given, further restricts the search to those plans.
  static int _earliestQueuedWithCredits(
    List<MembershipEntry> memberships,
    List<String> allowedPlanNames, {
    Set<String> excludedPlanNames = const {},
    Set<String>? onlyPlanNames,
  }) {
    final candidates = <MapEntry<int, MembershipEntry>>[];
    for (var i = 0; i < memberships.length; i++) {
      final m = memberships[i];
      if (m.isQueued &&
          m.creditsRemaining > 0 &&
          (onlyPlanNames == null || onlyPlanNames.contains(m.planName)) &&
          _isEligiblePlan(m, allowedPlanNames, excludedPlanNames)) {
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

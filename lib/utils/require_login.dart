import 'dart:js_interop';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../services/user_service.dart';
import 'app_colors.dart';
import 'error_reporter.dart';

/// Ensures some Firestore-readable session exists before a public embed
/// page (e.g. the web shop's membership/timetable embeds) mounts its real
/// screen — signs in anonymously if nothing is signed in yet. Anonymous
/// sessions satisfy firestore.rules' isSignedIn() for read-only browsing
/// (the membershipPlans/classes collections) with zero rules changes, and
/// never get a users/{uid} doc, so isAdmin()/isStaff() are unaffected.
Future<User> ensureAnonymousSession() async {
  final current = FirebaseAuth.instance.currentUser;
  if (current != null) return current;
  final cred = await FirebaseAuth.instance.signInAnonymously();
  return cred.user!;
}

/// The deferred-login gate for actions that need a real identity (buying a
/// plan, booking a class). No-ops if already signed in for real; otherwise
/// prompts Google sign-in and returns whether it succeeded, so the caller
/// can resume the original action right after. Only ever triggers when
/// signed out or on an anonymous session — on mobile that's unreachable,
/// since LoginScreen always gates real sign-in first there.
Future<bool> requireRealSignIn(BuildContext context) async {
  final current = FirebaseAuth.instance.currentUser;
  if (current != null && !current.isAnonymous) return true;

  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.bg,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => const _SignInSheet(),
  );
  return result ?? false;
}

@JS('document.requestStorageAccess')
external JSPromise<JSAny?>? _requestStorageAccess();

/// Best-effort request for Safari's Storage Access API before the sign-in
/// popup — without it, Safari's cross-site iframe tracking prevention can
/// block/evict the auth session's storage entirely. Silently ignored where
/// unsupported (every non-Safari browser today, where calling the undefined
/// JS function throws) or denied.
Future<void> _tryRequestStorageAccess() async {
  try {
    final promise = _requestStorageAccess();
    if (promise == null) return;
    await promise.toDart;
  } catch (_) {
    // Unsupported or denied — sign-in still proceeds via signInWithPopup.
  }
}

class _SignInSheet extends StatefulWidget {
  const _SignInSheet();

  @override
  State<_SignInSheet> createState() => _SignInSheetState();
}

class _SignInSheetState extends State<_SignInSheet> {
  bool _loading = false;

  Future<void> _signIn() async {
    setState(() => _loading = true);
    try {
      await _tryRequestStorageAccess();
      final result =
          await FirebaseAuth.instance.signInWithPopup(GoogleAuthProvider());
      await UserService.upsertFromCredential(result);
      if (mounted) Navigator.pop(context, true);
    } catch (e, st) {
      if (mounted) {
        reportError(
          context,
          e,
          st,
          userMessage: 'Sign-in failed. Please try again.',
          reason: 'Web shop deferred sign-in failed',
        );
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 28,
        bottom: MediaQuery.of(context).padding.bottom + 28,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Sign in to continue',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 6),
          const Text(
            'One quick Google sign-in and you can pick up right where you left off.',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _loading ? null : _signIn,
              child: _loading
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Sign in with Google'),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: _loading ? null : () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
          ),
        ],
      ),
    );
  }
}

import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import '../../firebase_options.dart';
import '../../services/user_service.dart';
import '../../utils/app_colors.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _loading = false;

  // Emails that always get super_admin on first login.
  // Remove or clear this list when going to production.
  static const _superAdminEmails = <String>[
    'admin.psas@gmail.com',
  ];

  Future<void> _signInWithGoogle() async {
    setState(() => _loading = true);
    try {
      final googleSignIn = GoogleSignIn(
        clientId: !kIsWeb && (Platform.isIOS || Platform.isMacOS)
            ? DefaultFirebaseOptions.ios.iosClientId
            : null,
      );
      final googleUser = await googleSignIn.signIn();
      if (googleUser == null) {
        setState(() => _loading = false);
        return;
      }
      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      final result =
          await FirebaseAuth.instance.signInWithCredential(credential);
      await _upsertUserAndFinish(result);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _signInWithApple() async {
    setState(() => _loading = true);
    try {
      final rawNonce = _generateNonce();
      final nonce = _sha256ofString(rawNonce);

      final appleCredential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: nonce,
      );

      final oauthCredential = OAuthProvider('apple.com').credential(
        idToken: appleCredential.identityToken,
        rawNonce: rawNonce,
      );

      final result =
          await FirebaseAuth.instance.signInWithCredential(oauthCredential);

      // Apple only ever hands back the name on the first authorization for
      // this app, and Firebase doesn't populate displayName for Apple sign-in,
      // so it has to be captured here or it's lost for good.
      final appleName = [appleCredential.givenName, appleCredential.familyName]
          .where((s) => s != null && s.isNotEmpty)
          .join(' ');

      await _upsertUserAndFinish(
        result,
        displayName: appleName.isNotEmpty ? appleName : null,
      );
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) {
        // User dismissed the Apple sheet; nothing to report.
      } else if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  /// Shared post-auth step for every sign-in provider: creates the Firestore
  /// user doc on first login (consuming any pending invitation), or merges
  /// updated profile fields on repeat logins. [displayName] lets a provider
  /// (e.g. Apple, which Firebase doesn't populate `displayName` for) supply
  /// the name explicitly instead of relying on `result.user!.displayName`.
  Future<void> _upsertUserAndFinish(
    UserCredential result, {
    String? displayName,
  }) async {
    final uid = result.user!.uid;
    final email = result.user!.email ?? '';
    final name = displayName ?? result.user!.displayName ?? '';
    final photoUrl = result.user!.photoURL ?? '';

    final userRef = FirebaseFirestore.instance.collection('users').doc(uid);
    final existing = await userRef.get();

    if (!existing.exists) {
      // Check for an admin-created invitation for this email
      final invite = await UserService.consumeInvitation(email);
      final isSuperAdmin = _superAdminEmails.contains(email);

      final role =
          isSuperAdmin ? 'admin' : (invite?['role'] as String? ?? 'client');
      final adminLevel =
          isSuperAdmin ? 'super_admin' : (invite?['adminLevel'] as String?);

      await userRef.set({
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
        'credits':
            isSuperAdmin ? 0 : (invite?['initialCredits'] as int? ?? 0),
        'memberships': <Map<String, dynamic>>[],
      });
    } else {
      // Update mutable profile fields; preserve role/credits.
      // Always enforce super_admin for designated emails.
      final isSuperAdmin = _superAdminEmails.contains(email);
      await userRef.set({
        'email': email,
        if (name.isNotEmpty) 'name': name,
        if (photoUrl.isNotEmpty) 'photoUrl': photoUrl,
        if (isSuperAdmin) 'role': 'admin',
        if (isSuperAdmin) 'adminLevel': 'super_admin',
      }, SetOptions(merge: true));
    }
  }

  String _generateNonce([int length = 32]) {
    const charset =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    return List.generate(
      length,
      (_) => charset[random.nextInt(charset.length)],
    ).join();
  }

  String _sha256ofString(String input) {
    return sha256.convert(utf8.encode(input)).toString();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Container(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(0.0, -0.8),
            radius: 0.9,
            colors: [
              AppColors.primary.withValues(alpha: 0.08),
              AppColors.bg,
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _Logo(),
                  const SizedBox(height: 32),
                  const Text(
                    'PSAS',
                    style: TextStyle(
                      fontSize: 44,
                      fontWeight: FontWeight.w900,
                      color: AppColors.textPrimary,
                      letterSpacing: 6,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    height: 3,
                    width: 48,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Pegasus Sports & Psychology Performance',
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.textSecondary,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(height: 28),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _pill(Icons.calendar_today_outlined, 'Book Classes'),
                      const SizedBox(width: 10),
                      _pill(Icons.notifications_outlined, 'Smart Reminders'),
                    ],
                  ),
                  const SizedBox(height: 56),
                  if (_loading)
                    const CircularProgressIndicator(color: AppColors.primary)
                  else
                    Column(
                      children: [
                        _GoogleButton(onTap: _signInWithGoogle),
                        if (!kIsWeb && Platform.isIOS) ...[
                          const SizedBox(height: 12),
                          _AppleButton(onTap: _signInWithApple),
                        ],
                      ],
                    ),
                  const SizedBox(height: 20),
                  const Text(
                    'Sign in once — stay signed in automatically',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _pill(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 13, color: AppColors.primary),
          const SizedBox(width: 6),
          Text(label,
              style: const TextStyle(
                  color: AppColors.primary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _Logo extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/images/logo.png',
      width: 150,
      height: 150,
    );
  }
}

class _GoogleButton extends StatelessWidget {
  final VoidCallback onTap;
  const _GoogleButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
        decoration: BoxDecoration(
          color: AppColors.navBg,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 20,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'G',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Color(0xFF4285F4),
              ),
            ),
            SizedBox(width: 14),
            Text(
              'Continue with Google',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AppleButton extends StatelessWidget {
  final VoidCallback onTap;
  const _AppleButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 20,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.apple, size: 22, color: Colors.white),
            SizedBox(width: 14),
            Text(
              'Continue with Apple',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

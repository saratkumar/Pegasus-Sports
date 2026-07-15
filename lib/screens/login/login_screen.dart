import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
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
      final googleUser = await GoogleSignIn().signIn();
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
      final uid = result.user!.uid;
      final email = result.user!.email ?? '';

      final userRef =
          FirebaseFirestore.instance.collection('users').doc(uid);
      final existing = await userRef.get();

      if (!existing.exists) {
        // Check for an admin-created invitation for this email
        final invite = await UserService.consumeInvitation(email);
        final isSuperAdmin = _superAdminEmails.contains(email);

        final role = isSuperAdmin
            ? 'admin'
            : (invite?['role'] as String? ?? 'client');
        final adminLevel = isSuperAdmin
            ? 'super_admin'
            : (invite?['adminLevel'] as String?);

        await userRef.set({
          'email': email,
          'name': (invite?['name'] as String?)?.isNotEmpty == true
              ? invite!['name']
              : result.user!.displayName ?? '',
          'photoUrl': result.user!.photoURL ?? '',
          if ((invite?['phone'] as String?)?.isNotEmpty == true)
            'phone': invite!['phone'],
          'role': role,
          if (adminLevel != null) 'adminLevel': adminLevel,
          'adminPermissions': <String>[],
          'credits': isSuperAdmin
              ? 0
              : (invite?['initialCredits'] as int? ?? 0),
          'memberships': <Map<String, dynamic>>[],
        });
      } else {
        // Update mutable profile fields; preserve role/credits
        // Always enforce super_admin for designated emails
        final isSuperAdmin = _superAdminEmails.contains(email);
        await userRef.set({
          'email': email,
          'name': result.user!.displayName ?? '',
          if ((result.user!.photoURL ?? '').isNotEmpty)
            'photoUrl': result.user!.photoURL,
          if (isSuperAdmin) 'role': 'admin',
          if (isSuperAdmin) 'adminLevel': 'super_admin',
        }, SetOptions(merge: true));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
    if (mounted) setState(() => _loading = false);
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
                    'Pegasus Sports & Athletic Society',
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
                    _GoogleButton(onTap: _signInWithGoogle),
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

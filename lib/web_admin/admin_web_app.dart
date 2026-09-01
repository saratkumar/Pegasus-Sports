import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/user_model.dart';
import '../services/user_service.dart';
import '../utils/app_colors.dart';
import '../screens/admin/activity_log_screen.dart';
import '../screens/admin/appointment_management_screen.dart';
import '../screens/admin/cancel_classes_screen.dart';
import '../screens/admin/class_management_screen.dart';
import '../screens/admin/class_roster_screen.dart';
import '../screens/admin/facility_management_screen.dart';
import '../screens/admin/plan_management_screen.dart';
import '../screens/admin/type_management_screen.dart';
import '../utils/error_reporter.dart';

class AdminWebApp extends StatelessWidget {
  const AdminWebApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'PSAS Admin',
      // Copied (not shared) from main.dart:111-211 — keeps this entrypoint
      // self-contained rather than importing the mobile app's widget tree.
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorScheme: const ColorScheme.light(
          primary: AppColors.primary,
          secondary: AppColors.secondary,
          surface: AppColors.surface,
          error: AppColors.error,
          onPrimary: Colors.white,
          onSecondary: Colors.white,
          onSurface: AppColors.textPrimary,
        ),
        scaffoldBackgroundColor: AppColors.bg,
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.bg,
          foregroundColor: AppColors.textPrimary,
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: false,
          titleTextStyle: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
            letterSpacing: 0.3,
          ),
          iconTheme: IconThemeData(color: AppColors.textPrimary),
          systemOverlayStyle: SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: Brightness.dark,
          ),
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: AppColors.divider, width: 1),
          ),
          color: AppColors.card,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            textStyle: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
            elevation: 0,
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.primary,
            side: const BorderSide(color: AppColors.primary),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          ),
        ),
        chipTheme: ChipThemeData(
          backgroundColor: AppColors.surface,
          selectedColor: AppColors.primary.withValues(alpha: 0.15),
          labelStyle: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: AppColors.divider),
          ),
        ),
        dividerTheme: const DividerThemeData(color: AppColors.divider),
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      home: const _AuthGate(),
    );
  }
}

class _AuthGate extends StatelessWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, authSnap) {
        if (authSnap.connectionState == ConnectionState.waiting) {
          return const _Splash();
        }
        if (!authSnap.hasData) return const _SignInScreen();

        return StreamBuilder<UserModel?>(
          stream: UserService.currentUserStream(),
          builder: (context, userSnap) {
            if (userSnap.connectionState == ConnectionState.waiting) {
              return const _Splash();
            }
            final user = userSnap.data;
            if (user == null || !user.isAdmin) {
              return const _NotAuthorizedScreen();
            }
            return const AdminWebShell();
          },
        );
      },
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppColors.bg,
      body: Center(child: CircularProgressIndicator(color: AppColors.primary)),
    );
  }
}

class _SignInScreen extends StatefulWidget {
  const _SignInScreen();

  @override
  State<_SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<_SignInScreen> {
  bool _loading = false;
  String? _error;

  Future<void> _signIn() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // firebase_auth_web only implements signInWithPopup/signInWithRedirect
      // for provider sign-in — signInWithProvider (the cross-platform
      // convenience method) throws UnimplementedError on web.
      await FirebaseAuth.instance.signInWithPopup(GoogleAuthProvider());
    } catch (e, st) {
      if (mounted) {
        reportError(
          context,
          e,
          st,
          userMessage: 'Sign-in failed. Please try again.',
          reason: 'Admin web sign-in failed',
        );
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'PSAS Admin',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _loading ? null : _signIn,
                  child: _loading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Sign in with Google'),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: const TextStyle(color: AppColors.error)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NotAuthorizedScreen extends StatelessWidget {
  const _NotAuthorizedScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Not authorized', style: TextStyle(fontSize: 18)),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => FirebaseAuth.instance.signOut(),
              child: const Text('Sign out'),
            ),
          ],
        ),
      ),
    );
  }
}

class AdminWebShell extends StatefulWidget {
  const AdminWebShell({super.key});

  @override
  State<AdminWebShell> createState() => _AdminWebShellState();
}

class _AdminWebShellState extends State<AdminWebShell> {
  int _selected = 0;

  static const _sections = <(String, IconData, Widget)>[
    ('Classes', Icons.event, ClassManagementScreen()),
    ('Class Roster', Icons.calendar_view_month, ClassRosterScreen()),
    ('Facilities', Icons.villa_outlined, FacilityManagementScreen()),
    ('Class Types', Icons.category_outlined, TypeManagementScreen()),
    ('Plans', Icons.card_membership_outlined, PlanManagementScreen()),
    ('Cancel Classes', Icons.event_busy_outlined, CancelClassesScreen()),
    ('Appointments', Icons.calendar_month_outlined, AppointmentManagementScreen()),
    ('Activity Log', Icons.history, ActivityLogScreen()),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _selected,
            onDestinationSelected: (i) => setState(() => _selected = i),
            labelType: NavigationRailLabelType.all,
            leading: const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text('PSAS', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
            trailing: Expanded(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: IconButton(
                    icon: const Icon(Icons.logout),
                    tooltip: 'Sign out',
                    onPressed: () => FirebaseAuth.instance.signOut(),
                  ),
                ),
              ),
            ),
            destinations: [
              for (final s in _sections)
                NavigationRailDestination(icon: Icon(s.$2), label: Text(s.$1)),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(child: _sections[_selected].$3),
        ],
      ),
    );
  }
}

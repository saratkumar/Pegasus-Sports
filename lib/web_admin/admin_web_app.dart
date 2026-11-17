import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/user_model.dart';
import '../services/user_service.dart';
import '../utils/app_colors.dart';
import '../screens/admin/activity_log_screen.dart';
import '../screens/admin/admin_requests_screen.dart';
import '../screens/admin/appointment_management_screen.dart';
import '../screens/admin/cancel_classes_screen.dart';
import '../screens/admin/cash_payment_screen.dart';
import '../screens/admin/class_management_screen.dart';
import '../screens/admin/class_roster_screen.dart';
import '../screens/admin/coupon_management_screen.dart';
import '../screens/admin/facility_management_screen.dart';
import '../screens/admin/payment_qr_screen.dart';
import '../screens/admin/plan_management_screen.dart';
import '../screens/admin/trainer_profiles_screen.dart';
import '../screens/admin/transactions_screen.dart';
import '../screens/admin/type_management_screen.dart';
import '../screens/admin/user_management_screen.dart';
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
          labelStyle:
              const TextStyle(color: AppColors.textPrimary, fontSize: 13),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: AppColors.divider),
          ),
        ),
        dividerTheme: const DividerThemeData(color: AppColors.divider),
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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
            if (user == null || !user.isAdmin || !user.isActive) {
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
                Image.asset('assets/images/logo.png',
                    width: 96, height: 96, fit: BoxFit.contain),
                const SizedBox(height: 16),
                const Text(
                  'PSAS Admin',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Pegasus Sports & Psychology Performance',
                  textAlign: TextAlign.center,
                  style:
                      TextStyle(fontSize: 13, color: AppColors.textSecondary),
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

/// One sidebar entry. [builder] (not a const widget) so a section's screen
/// is only built when opened.
class _Section {
  final String group;
  final String label;
  final IconData icon;
  final Widget Function() builder;
  const _Section(this.group, this.label, this.icon, this.builder);
}

/// The admin panel: every admin screen the mobile app has (except Backup,
/// which writes files and is mobile-only), in a grouped sidebar. The
/// sidebar scrolls, so it never overflows on a short window; below
/// [_wideLayout] it collapses into a drawer behind a menu button.
class _AdminWebShellState extends State<AdminWebShell> {
  int _selected = 0;

  static const _wideLayout = 900.0;

  static final _sections = <_Section>[
    _Section('People', 'Users', Icons.people_outline,
        () => const UserManagementScreen()),
    _Section('People', 'Requests', Icons.inbox_outlined,
        () => const AdminRequestsScreen()),
    _Section('Schedule', 'Class Roster', Icons.calendar_view_month,
        () => const ClassRosterScreen()),
    _Section('Schedule', 'Classes', Icons.event,
        () => const ClassManagementScreen()),
    _Section('Schedule', 'Cancel Classes', Icons.event_busy_outlined,
        () => const CancelClassesScreen()),
    _Section('Schedule', 'Appointments', Icons.calendar_month_outlined,
        () => const AppointmentManagementScreen()),
    _Section('Payments', 'Transactions', Icons.receipt_long_outlined,
        () => const TransactionsScreen()),
    _Section('Payments', 'Record Cash Payment', Icons.payments_outlined,
        () => const CashPaymentScreen()),
    _Section('Payments', 'Membership Plans', Icons.card_membership_outlined,
        () => const PlanManagementScreen()),
    _Section('Payments', 'Coupons', Icons.local_offer_outlined,
        () => const CouponManagementScreen()),
    _Section('Payments', 'Business QR Code', Icons.qr_code_2,
        () => const PaymentQrScreen()),
    _Section('Setup', 'Facilities', Icons.villa_outlined,
        () => const FacilityManagementScreen()),
    _Section('Setup', 'Class Types', Icons.category_outlined,
        () => const TypeManagementScreen()),
    _Section('Setup', 'Trainers', Icons.badge_outlined,
        () => const TrainerProfilesScreen()),
    _Section('Records', 'Activity Log', Icons.history,
        () => const ActivityLogScreen()),
  ];

  void _select(int i, {bool closeDrawer = false}) {
    setState(() => _selected = i);
    if (closeDrawer) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final wide = constraints.maxWidth >= _wideLayout;
      // Keyed by section so switching sections never keeps the previous
      // screen's state (scroll position, open dialogs) around.
      final page = KeyedSubtree(
        key: ValueKey(_selected),
        child: _sections[_selected].builder(),
      );
      if (wide) {
        return Scaffold(
          body: Row(
            children: [
              SizedBox(width: 248, child: _sidebar(closeDrawer: false)),
              const VerticalDivider(width: 1),
              Expanded(child: page),
            ],
          ),
        );
      }
      return Scaffold(
        appBar: AppBar(
          titleSpacing: 0,
          title: Row(children: [
            Image.asset('assets/images/logo.png',
                width: 28, height: 28, fit: BoxFit.contain),
            const SizedBox(width: 10),
            Flexible(
              child: Text('PSAS Admin · ${_sections[_selected].label}',
                  overflow: TextOverflow.ellipsis),
            ),
          ]),
        ),
        drawer: Drawer(
          width: 280,
          child: SafeArea(child: _sidebar(closeDrawer: true)),
        ),
        body: page,
      );
    });
  }

  Widget _sidebar({required bool closeDrawer}) {
    final user = FirebaseAuth.instance.currentUser;
    final items = <Widget>[];
    String? group;
    for (var i = 0; i < _sections.length; i++) {
      final sec = _sections[i];
      if (sec.group != group) {
        group = sec.group;
        items.add(Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 16, 4),
          child: Text(group.toUpperCase(),
              style: const TextStyle(
                  fontSize: 11,
                  letterSpacing: 0.8,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textMuted)),
        ));
      }
      final selected = i == _selected;
      items.add(Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 1),
        child: ListTile(
          dense: true,
          selected: selected,
          selectedTileColor: AppColors.primary.withValues(alpha: 0.12),
          selectedColor: AppColors.primary,
          iconColor: AppColors.textSecondary,
          textColor: AppColors.textPrimary,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          leading: Icon(sec.icon, size: 20),
          title: Text(sec.label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500)),
          onTap: () => _select(i, closeDrawer: closeDrawer),
        ),
      ));
    }

    return Container(
      color: AppColors.card,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
            child: Row(children: [
              Image.asset('assets/images/logo.png',
                  width: 40, height: 40, fit: BoxFit.contain),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('PSAS Admin',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w800)),
                    Text('Pegasus Sports & Psychology',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 11, color: AppColors.textMuted)),
                  ],
                ),
              ),
            ]),
          ),
          const Divider(height: 1),
          // Scrolls — the menu never overflows a short window.
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 8),
              children: items,
            ),
          ),
          const Divider(height: 1),
          ListTile(
            dense: true,
            leading: const Icon(Icons.logout, size: 20),
            title: Text(
              user?.email ?? 'Sign out',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13),
            ),
            subtitle: const Text('Sign out', style: TextStyle(fontSize: 11)),
            onTap: () => FirebaseAuth.instance.signOut(),
          ),
        ],
      ),
    );
  }
}

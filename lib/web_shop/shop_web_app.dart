import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/user_model.dart';
import '../services/user_service.dart';
import '../utils/app_colors.dart';
import '../screens/login/login_screen.dart';
import '../screens/timetable/timetable_screen.dart';
import '../screens/bookings/bookings_screen.dart';
import '../screens/memberships/memberships_screen.dart';
import '../screens/profile/profile_screen.dart';
import '../utils/require_login.dart';

class ShopWebApp extends StatelessWidget {
  const ShopWebApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'PSAS',
      // Copied (not shared) from main.dart:111-211 — keeps this entrypoint
      // self-contained rather than importing the mobile app's widget tree
      // (BottomNav pulls in dart:io-touching code this doesn't need).
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
      home: _rootFor(Uri.base.fragment),
    );
  }

  // Single-screen, publicly-browsable routes meant to be iframed by the
  // portal — e.g. https://psas-shop.web.app/#/membership. Each starts an
  // anonymous session (see require_login.dart) so the screen's Firestore
  // reads succeed even for a signed-out visitor; the screens themselves
  // prompt for a real sign-in only when an action needs one (purchasing a
  // plan, booking a class). Any other/empty fragment keeps today's full
  // tabbed app behind real sign-in, for direct visits.
  Widget _rootFor(String fragment) {
    switch (fragment) {
      case '/membership':
        return const _MembershipEmbedPage();
      case '/timetable':
        return const _TimetableEmbedPage();
      default:
        return const _AuthGate();
    }
  }
}

class _MembershipEmbedPage extends StatefulWidget {
  const _MembershipEmbedPage();

  @override
  State<_MembershipEmbedPage> createState() => _MembershipEmbedPageState();
}

class _MembershipEmbedPageState extends State<_MembershipEmbedPage> {
  late final Future<User> _sessionFuture = ensureAnonymousSession();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<User>(
      future: _sessionFuture,
      builder: (context, snap) {
        if (!snap.hasData) return const _Splash();
        return const MembershipScreen();
      },
    );
  }
}

class _TimetableEmbedPage extends StatefulWidget {
  const _TimetableEmbedPage();

  @override
  State<_TimetableEmbedPage> createState() => _TimetableEmbedPageState();
}

class _TimetableEmbedPageState extends State<_TimetableEmbedPage> {
  late final Future<User> _sessionFuture = ensureAnonymousSession();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<User>(
      future: _sessionFuture,
      builder: (context, snap) {
        if (!snap.hasData) return const _Splash();
        // Anonymous sessions have no users/{uid} doc, so this naturally
        // yields null — TimetableScreen already treats userModel as
        // optional (only used for the phone-reminder banner).
        return StreamBuilder<UserModel?>(
          stream: UserService.currentUserStream(),
          builder: (context, userSnap) {
            return TimetableScreen(userModel: userSnap.data);
          },
        );
      },
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
        if (!authSnap.hasData) return const LoginScreen();

        return StreamBuilder<UserModel?>(
          stream: UserService.currentUserStream(),
          builder: (context, userSnap) {
            if (userSnap.connectionState == ConnectionState.waiting) {
              return const _Splash();
            }
            return ShopWebShell(userModel: userSnap.data);
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

class ShopWebShell extends StatefulWidget {
  final UserModel? userModel;
  const ShopWebShell({super.key, this.userModel});

  @override
  State<ShopWebShell> createState() => _ShopWebShellState();
}

class _ShopWebShellState extends State<ShopWebShell> {
  int _selected = 0;

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    // Same 3 screens mobile's BottomNav shows for the client role — see
    // lib/navigation/bottom_navigation.dart's default case.
    final sections = <(String, IconData, Widget)>[
      ('Timetable', Icons.calendar_month_outlined,
          TimetableScreen(userModel: widget.userModel)),
      ('Bookings', Icons.bookmark_border, const BookingsScreen()),
      ('Membership', Icons.card_membership_outlined, const MembershipScreen()),
    ];
    if (_selected >= sections.length) _selected = 0;

    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _selected,
            onDestinationSelected: (i) => setState(() => _selected = i),
            labelType: NavigationRailLabelType.all,
            leading: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Column(
                children: [
                  const Text('PSAS', style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 16),
                  GestureDetector(
                    onTap: widget.userModel == null
                        ? null
                        : () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    ProfileScreen(userModel: widget.userModel!),
                              ),
                            ),
                    child: CircleAvatar(
                      radius: 15,
                      backgroundColor: AppColors.primary.withValues(alpha: 0.15),
                      backgroundImage:
                          user?.photoURL != null ? NetworkImage(user!.photoURL!) : null,
                      child: user?.photoURL == null
                          ? const Icon(Icons.person, size: 16, color: AppColors.primary)
                          : null,
                    ),
                  ),
                ],
              ),
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
              for (final s in sections)
                NavigationRailDestination(icon: Icon(s.$2), label: Text(s.$1)),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(child: sections[_selected].$3),
        ],
      ),
    );
  }
}

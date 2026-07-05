import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/user_model.dart';
import '../screens/timetable/timetable_screen.dart';
import '../screens/bookings/bookings_screen.dart';
import '../screens/memberships/memberships_screen.dart';
import '../screens/trainer/trainer_home_screen.dart';
import '../screens/admin/admin_home_screen.dart';
import '../utils/app_colors.dart';

class BottomNav extends StatefulWidget {
  final UserModel? userModel;
  const BottomNav({super.key, this.userModel});

  @override
  State<BottomNav> createState() => _BottomNavState();
}

class _BottomNavState extends State<BottomNav> {
  int _index = 0;

  void _confirmSignOut() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: AppColors.divider),
        ),
        title: const Text('Sign Out?',
            style: TextStyle(
                color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
        content: const Text(
          'You will need to sign in again to access your bookings.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Stay', style: TextStyle(color: AppColors.primary)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await FirebaseAuth.instance.signOut();
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                foregroundColor: Colors.white),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );
  }

  // ── Client nav ──────────────────────────────────────────────────────────────

  List<Widget> get _clientPages => const [
        TimetableScreen(),
        BookingsScreen(),
        MembershipScreen(),
      ];

  List<NavigationDestination> get _clientDests => const [
        NavigationDestination(
          icon: Icon(Icons.calendar_month_outlined, color: Color(0xFF666666)),
          selectedIcon: Icon(Icons.calendar_month, color: AppColors.primary),
          label: 'Timetable',
        ),
        NavigationDestination(
          icon: Icon(Icons.bookmark_border, color: Color(0xFF666666)),
          selectedIcon: Icon(Icons.bookmark, color: AppColors.primary),
          label: 'Bookings',
        ),
        NavigationDestination(
          icon: Icon(Icons.card_membership_outlined, color: Color(0xFF666666)),
          selectedIcon: Icon(Icons.card_membership, color: AppColors.primary),
          label: 'Membership',
        ),
      ];

  // ── Trainer nav ─────────────────────────────────────────────────────────────

  List<Widget> get _trainerPages => const [
        TimetableScreen(),
        TrainerHomeScreen(),
        BookingsScreen(),
      ];

  List<NavigationDestination> get _trainerDests => const [
        NavigationDestination(
          icon: Icon(Icons.calendar_month_outlined, color: Color(0xFF666666)),
          selectedIcon: Icon(Icons.calendar_month, color: AppColors.primary),
          label: 'Timetable',
        ),
        NavigationDestination(
          icon: Icon(Icons.manage_accounts_outlined, color: Color(0xFF666666)),
          selectedIcon: Icon(Icons.manage_accounts, color: AppColors.primary),
          label: 'Trainer',
        ),
        NavigationDestination(
          icon: Icon(Icons.bookmark_border, color: Color(0xFF666666)),
          selectedIcon: Icon(Icons.bookmark, color: AppColors.primary),
          label: 'Bookings',
        ),
      ];

  // ── Admin nav ────────────────────────────────────────────────────────────────

  List<Widget> get _adminPages => const [
        TimetableScreen(),
        AdminHomeScreen(),
        BookingsScreen(),
        MembershipScreen(),
      ];

  List<NavigationDestination> get _adminDests => const [
        NavigationDestination(
          icon: Icon(Icons.calendar_month_outlined, color: Color(0xFF666666)),
          selectedIcon: Icon(Icons.calendar_month, color: AppColors.primary),
          label: 'Timetable',
        ),
        NavigationDestination(
          icon: Icon(Icons.admin_panel_settings_outlined,
              color: Color(0xFF666666)),
          selectedIcon:
              Icon(Icons.admin_panel_settings, color: AppColors.primary),
          label: 'Admin',
        ),
        NavigationDestination(
          icon: Icon(Icons.bookmark_border, color: Color(0xFF666666)),
          selectedIcon: Icon(Icons.bookmark, color: AppColors.primary),
          label: 'Bookings',
        ),
        NavigationDestination(
          icon: Icon(Icons.card_membership_outlined, color: Color(0xFF666666)),
          selectedIcon: Icon(Icons.card_membership, color: AppColors.primary),
          label: 'Plans',
        ),
      ];

  List<Widget> get _pages {
    final role = widget.userModel?.role ?? 'client';
    if (role == 'admin') return _adminPages;
    if (role == 'trainer') return _trainerPages;
    return _clientPages;
  }

  List<NavigationDestination> get _dests {
    final role = widget.userModel?.role ?? 'client';
    if (role == 'admin') return _adminDests;
    if (role == 'trainer') return _trainerDests;
    return _clientDests;
  }

  String get _roleLabel {
    switch (widget.userModel?.role) {
      case 'trainer':
        return 'Trainer';
      case 'admin':
        return widget.userModel?.adminLevel == 'super_admin'
            ? 'Super Admin'
            : 'Admin';
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    // Clamp index when role changes and page count differs
    final pageCount = _pages.length;
    if (_index >= pageCount) _index = 0;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Image.asset('assets/images/logo.png',
                width: 32, height: 32, fit: BoxFit.contain),
            const SizedBox(width: 10),
            const Text('PSAS'),
            if (_roleLabel.isNotEmpty) ...[
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _roleLabel,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ],
        ),
        actions: [
          if (user?.photoURL != null)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: CircleAvatar(
                radius: 15,
                backgroundImage: NetworkImage(user!.photoURL!),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.logout, color: AppColors.textMuted),
            tooltip: 'Sign out',
            onPressed: _confirmSignOut,
          ),
        ],
      ),
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border:
              Border(top: BorderSide(color: AppColors.divider, width: 1)),
        ),
        child: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (v) => setState(() => _index = v),
          backgroundColor: AppColors.navBg,
          indicatorColor: AppColors.primary.withValues(alpha: 0.25),
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          destinations: _dests,
        ),
      ),
    );
  }
}

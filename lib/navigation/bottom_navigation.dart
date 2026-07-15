import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../models/user_model.dart';
import '../screens/timetable/timetable_screen.dart';
import '../screens/bookings/bookings_screen.dart';
import '../screens/memberships/memberships_screen.dart';
import '../screens/trainer/trainer_home_screen.dart';
import '../screens/trainer/trainer_history_screen.dart';
import '../screens/trainer/trainer_requests_screen.dart';
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
  // null = use real role; set by super admin to preview another role
  String? _viewAs;

  String get _effectiveRole =>
      _viewAs ?? widget.userModel?.role ?? 'client';

  bool get _isSuperAdmin => widget.userModel?.isSuperAdmin == true;

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
            child:
                const Text('Stay', style: TextStyle(color: AppColors.primary)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await GoogleSignIn().signOut();
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

  // ── Pages / destinations per role ───────────────────────────────────────────

  List<Widget> get _pages {
    switch (_effectiveRole) {
      case 'admin':
        return [
          const TimetableScreen(),
          AdminHomeScreen(userModel: widget.userModel),
          const BookingsScreen(),
          const MembershipScreen(),
        ];
      case 'trainer':
        return const [
          TrainerHomeScreen(),
          TrainerHistoryScreen(),
          TrainerRequestsScreen(),
        ];
      default:
        return const [
          TimetableScreen(),
          BookingsScreen(),
          MembershipScreen(),
        ];
    }
  }

  List<NavigationDestination> get _dests {
    switch (_effectiveRole) {
      case 'admin':
        return const [
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
            icon:
                Icon(Icons.card_membership_outlined, color: Color(0xFF666666)),
            selectedIcon:
                Icon(Icons.card_membership, color: AppColors.primary),
            label: 'Plans',
          ),
        ];
      case 'trainer':
        return const [
          NavigationDestination(
            icon: Icon(Icons.today_outlined, color: Color(0xFF666666)),
            selectedIcon: Icon(Icons.today, color: AppColors.primary),
            label: 'Schedule',
          ),
          NavigationDestination(
            icon: Icon(Icons.history_outlined, color: Color(0xFF666666)),
            selectedIcon: Icon(Icons.history, color: AppColors.primary),
            label: 'History',
          ),
          NavigationDestination(
            icon: Icon(Icons.inbox_outlined, color: Color(0xFF666666)),
            selectedIcon: Icon(Icons.inbox, color: AppColors.primary),
            label: 'Requests',
          ),
        ];
      default:
        return const [
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
            icon:
                Icon(Icons.card_membership_outlined, color: Color(0xFF666666)),
            selectedIcon:
                Icon(Icons.card_membership, color: AppColors.primary),
            label: 'Membership',
          ),
        ];
    }
  }

  String get _roleLabel {
    if (_viewAs != null) {
      return 'Viewing as ${_viewAs![0].toUpperCase()}${_viewAs!.substring(1)}';
    }
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
                  color: _viewAs != null
                      ? Colors.orange.withValues(alpha: 0.15)
                      : AppColors.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _roleLabel,
                  style: TextStyle(
                    fontSize: 11,
                    color:
                        _viewAs != null ? Colors.orange : AppColors.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ],
        ),
        actions: [
          if (_isSuperAdmin)
            IconButton(
              icon: Icon(
                Icons.switch_account_outlined,
                color: _viewAs != null ? Colors.orange : AppColors.textMuted,
              ),
              tooltip: 'View As',
              onPressed: () => _showViewAsPicker(context),
            ),
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

  void _showViewAsPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.bg,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('View App As',
                style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary)),
            const SizedBox(height: 6),
            const Text(
                'Switch perspective to test different role views. Your actual role is not changed.',
                style: TextStyle(
                    fontSize: 13, color: AppColors.textSecondary)),
            const SizedBox(height: 20),
            ...['admin', 'trainer', 'client'].map((role) {
              final isActive = (_viewAs ?? widget.userModel?.role) == role;
              final color = role == 'admin'
                  ? AppColors.error
                  : role == 'trainer'
                      ? const Color(0xFF00D4AA)
                      : AppColors.primary;
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  radius: 18,
                  backgroundColor: color.withValues(alpha: 0.12),
                  child: Icon(
                    role == 'admin'
                        ? Icons.admin_panel_settings
                        : role == 'trainer'
                            ? Icons.fitness_center
                            : Icons.person,
                    color: color,
                    size: 18,
                  ),
                ),
                title: Text(
                  role[0].toUpperCase() + role.substring(1),
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: isActive ? color : AppColors.textPrimary),
                ),
                subtitle: Text(
                  role == 'admin'
                      ? 'Manage classes, users, requests'
                      : role == 'trainer'
                          ? 'View trainer tools and schedule'
                          : 'Book classes, manage membership',
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.textMuted),
                ),
                trailing: isActive
                    ? Icon(Icons.check_circle, color: color, size: 20)
                    : null,
                onTap: () {
                  setState(() {
                    _viewAs = role == widget.userModel?.role ? null : role;
                    _index = 0;
                  });
                  Navigator.pop(context);
                },
              );
            }),
          ],
        ),
      ),
    );
  }
}

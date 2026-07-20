import 'package:flutter/material.dart';
import '../../models/user_model.dart';
import '../../utils/app_colors.dart';
import '../profile/profile_screen.dart';
import 'classes_screen.dart';
import 'appointments_screen.dart';
import 'facilities_screen.dart';

class TimetableScreen extends StatefulWidget {
  final UserModel? userModel;
  const TimetableScreen({super.key, this.userModel});

  @override
  State<TimetableScreen> createState() => _TimetableScreenState();
}

class _TimetableScreenState extends State<TimetableScreen> {
  bool _bannerDismissed = false;

  @override
  Widget build(BuildContext context) {
    final showPhoneReminder = widget.userModel != null &&
        (widget.userModel!.phone ?? '').isEmpty &&
        !_bannerDismissed;

    return Scaffold(
      appBar: AppBar(title: const Text("Timetable")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showPhoneReminder) ...[
              _PhoneReminderBanner(
                onAddNow: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        ProfileScreen(userModel: widget.userModel!),
                  ),
                ),
                onDismiss: () => setState(() => _bannerDismissed = true),
              ),
              const SizedBox(height: 16),
            ],
            const Text('What would you like to book?',
                style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w500)),
            const SizedBox(height: 16),
            _Tile(
              title: 'Classes',
              subtitle: 'Group fitness sessions with a coach',
              icon: Icons.groups_outlined,
              color: AppColors.primary,
              page: const ClassesScreen(),
            ),
            const SizedBox(height: 12),
            _Tile(
              title: 'Appointments',
              subtitle: 'One-on-one personal training slots',
              icon: Icons.person_outline,
              color: const Color(0xFFB388FF),
              page: const AppointmentsScreen(),
            ),
            const SizedBox(height: 12),
            _Tile(
              title: 'Facilities',
              subtitle: 'Gym equipment and facility access',
              icon: Icons.fitness_center,
              color: AppColors.secondary,
              page: const FacilitiesScreen(),
            ),
          ],
        ),
      ),
    );
  }
}

class _PhoneReminderBanner extends StatelessWidget {
  final VoidCallback onAddNow;
  final VoidCallback onDismiss;

  const _PhoneReminderBanner({required this.onAddNow, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.phone_outlined, color: AppColors.warning, size: 20),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              "Add your mobile number so we can reach you about bookings.",
              style: TextStyle(
                  fontSize: 12.5,
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w500),
            ),
          ),
          TextButton(
            onPressed: onAddNow,
            style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8)),
            child: const Text('Add now',
                style: TextStyle(fontWeight: FontWeight.w700)),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18, color: AppColors.textMuted),
            onPressed: onDismiss,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final Widget page;

  const _Tile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.page,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => Navigator.push(
          context, MaterialPageRoute(builder: (_) => page)),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.divider),
        ),
        child: Row(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: color, size: 26),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary)),
                  const SizedBox(height: 3),
                  Text(subtitle,
                      style: const TextStyle(
                          fontSize: 13, color: AppColors.textSecondary)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }
}

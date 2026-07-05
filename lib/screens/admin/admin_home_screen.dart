import 'package:flutter/material.dart';
import '../../utils/app_colors.dart';
import 'class_management_screen.dart';
import 'facility_management_screen.dart';
import 'admin_requests_screen.dart';
import 'user_management_screen.dart';
import 'attendance_report_screen.dart';

class AdminHomeScreen extends StatelessWidget {
  const AdminHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Admin Panel')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SectionHeader('Manage'),
          const SizedBox(height: 12),
          _tile(
            context,
            icon: Icons.fitness_center,
            color: AppColors.primary,
            title: 'Classes',
            subtitle: 'Create, edit and delete fitness classes',
            page: const ClassManagementScreen(),
          ),
          const SizedBox(height: 10),
          _tile(
            context,
            icon: Icons.place_outlined,
            color: const Color(0xFF00D4AA),
            title: 'Facilities',
            subtitle: 'Add and manage gym facilities',
            page: const FacilityManagementScreen(),
          ),
          const SizedBox(height: 10),
          _tile(
            context,
            icon: Icons.people_outline,
            color: const Color(0xFFB388FF),
            title: 'Users',
            subtitle: 'Manage roles, credits and memberships',
            page: const UserManagementScreen(),
          ),
          const SizedBox(height: 22),
          _SectionHeader('Approvals'),
          const SizedBox(height: 12),
          _tile(
            context,
            icon: Icons.inbox_outlined,
            color: const Color(0xFFFFAB40),
            title: 'Pending Requests',
            subtitle: 'Credit requests and slot increase approvals',
            page: const AdminRequestsScreen(),
          ),
          const SizedBox(height: 22),
          _SectionHeader('Reports'),
          const SizedBox(height: 12),
          _tile(
            context,
            icon: Icons.bar_chart_outlined,
            color: const Color(0xFF4FC3F7),
            title: 'Attendance Report',
            subtitle: 'Month-wise log of bookings, cancellations & waitlist',
            page: const AttendanceReportScreen(),
          ),
        ],
      ),
    );
  }

  Widget _tile(
    BuildContext context, {
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required Widget page,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () =>
          Navigator.push(context, MaterialPageRoute(builder: (_) => page)),
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
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: color, size: 24),
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

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Text(title,
        style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppColors.textSecondary,
            letterSpacing: 0.8));
  }
}

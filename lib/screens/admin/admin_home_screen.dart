import 'package:flutter/material.dart';
import '../../services/backup_service.dart';
import '../../utils/app_colors.dart';
import 'backup_screen.dart';
import 'cash_payment_screen.dart';
import 'class_management_screen.dart';
import 'coupon_management_screen.dart';
import 'facility_management_screen.dart';
import 'plan_management_screen.dart';
import 'type_management_screen.dart';
import 'admin_requests_screen.dart';
import 'user_management_screen.dart';
import 'attendance_report_screen.dart';
import 'transactions_screen.dart';

class AdminHomeScreen extends StatefulWidget {
  const AdminHomeScreen({super.key});

  @override
  State<AdminHomeScreen> createState() => _AdminHomeScreenState();
}

class _AdminHomeScreenState extends State<AdminHomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkBackupReminder());
  }

  Future<void> _checkBackupReminder() async {
    final overdue = await BackupService.isOverdue();
    if (!overdue || !mounted) return;
    final lastBackupAt = await BackupService.getLastBackupAt();
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Backup Reminder',
            style: TextStyle(
                color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
        content: Text(
          lastBackupAt == null
              ? 'A backup has never been taken. Please export a backup of logs and requests.'
              : 'It has been over 30 days since the last backup. Please export a fresh backup of logs and requests.',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Later',
                style: TextStyle(color: AppColors.textMuted)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const BackupScreen()));
            },
            child: const Text('Back Up Now'),
          ),
        ],
      ),
    );
  }

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
            icon: Icons.category_outlined,
            color: const Color(0xFFFF7043),
            title: 'Class Types',
            subtitle: 'Manage types with image auto-mapping',
            page: const TypeManagementScreen(),
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
          const SizedBox(height: 10),
          _tile(
            context,
            icon: Icons.card_membership_outlined,
            color: const Color(0xFF4FC3F7),
            title: 'Membership Plans',
            subtitle: 'Create, edit and price membership plans',
            page: const PlanManagementScreen(),
          ),
          const SizedBox(height: 10),
          _tile(
            context,
            icon: Icons.local_offer_outlined,
            color: const Color(0xFFEC407A),
            title: 'Coupons',
            subtitle: 'Create discount codes for client checkout',
            page: const CouponManagementScreen(),
          ),
          const SizedBox(height: 10),
          _tile(
            context,
            icon: Icons.payments_outlined,
            color: const Color(0xFF66BB6A),
            title: 'Record Cash Payment',
            subtitle: 'Sell a plan to a client who paid by cash',
            page: const CashPaymentScreen(),
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
          const SizedBox(height: 10),
          _tile(
            context,
            icon: Icons.receipt_long_outlined,
            color: const Color(0xFF66BB6A),
            title: 'Transactions',
            subtitle: 'Payment history, revenue summary and invoice lookup',
            page: const TransactionsScreen(),
          ),
          const SizedBox(height: 10),
          _tile(
            context,
            icon: Icons.backup_outlined,
            color: const Color(0xFF7E57C2),
            title: 'Backup',
            subtitle: 'Export logs and requests to CSV/Excel',
            page: const BackupScreen(),
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

import 'package:flutter/material.dart';
import '../../models/user_model.dart';
import '../../services/backup_service.dart';
import '../../utils/app_colors.dart';
import 'appointment_management_screen.dart';
import 'backup_screen.dart';
import 'cancel_classes_screen.dart';
import 'cash_payment_screen.dart';
import 'class_management_screen.dart';
import 'class_roster_screen.dart';
import 'coupon_management_screen.dart';
import 'facility_management_screen.dart';
import 'payment_qr_screen.dart';
import 'plan_management_screen.dart';
import 'type_management_screen.dart';

class AdminHomeScreen extends StatefulWidget {
  final UserModel? userModel;
  const AdminHomeScreen({super.key, this.userModel});

  @override
  State<AdminHomeScreen> createState() => _AdminHomeScreenState();
}

class _AdminHomeScreenState extends State<AdminHomeScreen> {
  @override
  void initState() {
    super.initState();
    // Backup menu is hidden for now, so skip the reminder dialog too —
    // it would otherwise point at a screen the admin can't reach.
    // WidgetsBinding.instance.addPostFrameCallback((_) => _checkBackupReminder());
  }

  // ignore: unused_element
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
      appBar: AppBar(title: const Text('More')),
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
            icon: Icons.event_busy_outlined,
            color: AppColors.error,
            title: 'Cancel Classes',
            subtitle: 'Cancel a single session or an entire class series',
            page: const CancelClassesScreen(),
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
            icon: Icons.event_available_outlined,
            color: const Color(0xFFFF7043),
            title: 'Appointment Slots',
            subtitle: 'Manage one-on-one bookable slots',
            page: const AppointmentManagementScreen(),
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
          const SizedBox(height: 10),
          _tile(
            context,
            icon: Icons.qr_code_2_outlined,
            color: const Color(0xFF4FC3F7),
            title: 'Business QR Code',
            subtitle: 'Configure the QR shown at checkout as an alternative to card',
            page: const PaymentQrScreen(),
          ),
          if (widget.userModel?.isSuperAdmin == true) ...[
            const SizedBox(height: 22),
            _SectionHeader('Reports'),
            const SizedBox(height: 12),
            _tile(
              context,
              icon: Icons.groups_outlined,
              color: const Color(0xFF00D4AA),
              title: 'Class Roster',
              subtitle: 'Who signed up for which class, by day',
              page: const ClassRosterScreen(),
            ),
          ],
          // Backup menu hidden for now — BackupScreen/CleanupService are
          // untouched, just not linked from the menu.
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

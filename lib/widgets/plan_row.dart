import 'package:flutter/material.dart';
import '../models/user_model.dart';
import '../utils/app_colors.dart';

/// One plan entry in an admin's plan list — status chip (tap to override)
/// plus start/end dates and credits, with a date-edit button. Shared by
/// User Management (an adult's plans) and the staff Family view (a child's
/// junior packages).
class PlanRow extends StatelessWidget {
  final MembershipEntry entry;
  final VoidCallback? onEdit;
  final ValueChanged<String>? onSetStatus;

  const PlanRow({
    super.key,
    required this.entry,
    required this.onEdit,
    required this.onSetStatus,
  });

  String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  Color get _statusColor {
    switch (entry.status) {
      case 'active':
        return AppColors.primary;
      case 'queued':
        return const Color(0xFFFFAB40);
      default:
        return AppColors.textMuted;
    }
  }

  String get _statusLabel {
    switch (entry.status) {
      case 'active':
        return 'Active';
      case 'queued':
        return 'Queued';
      default:
        return 'Expired';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(entry.planName,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary)),
                    ),
                    const SizedBox(width: 6),
                    PopupMenuButton<String>(
                      enabled: onSetStatus != null,
                      onSelected: onSetStatus,
                      tooltip: 'Change status',
                      padding: EdgeInsets.zero,
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'active', child: Text('Active')),
                        PopupMenuItem(value: 'queued', child: Text('Queued')),
                        PopupMenuItem(value: 'expired', child: Text('Expired')),
                      ],
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: _statusColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          _statusLabel,
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                            color: _statusColor,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  '${_fmtDate(entry.startDate)} → ${_fmtDate(entry.endDate)} · '
                  '${entry.creditsRemaining}/${entry.credits} credits',
                  style:
                      const TextStyle(fontSize: 11, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onEdit,
            icon: const Icon(Icons.edit_calendar_outlined,
                size: 18, color: AppColors.primary),
            tooltip: 'Edit start/end date',
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

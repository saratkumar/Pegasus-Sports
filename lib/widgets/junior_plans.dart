import 'package:flutter/material.dart';
import '../models/dependent_model.dart';
import '../models/user_model.dart';
import '../services/user_service.dart';
import '../utils/app_colors.dart';
import '../utils/app_toast.dart';
import 'plan_row.dart';

/// The junior packages assigned to one child. Parents see a read-only
/// summary (credits left, days left / start date); staff ([editable]) get
/// the same per-plan rows as an adult's plans in User Management, to fix
/// dates or override a status. Renders nothing when the child has no
/// packages (and isn't [editable]).
class JuniorPlansSection extends StatelessWidget {
  final String parentUid;
  final DependentModel child;
  final bool editable;

  const JuniorPlansSection({
    super.key,
    required this.parentUid,
    required this.child,
    this.editable = false,
  });

  @override
  Widget build(BuildContext context) {
    if (editable) return _buildEditable(context);

    final active = child.activeMemberships;
    final queued = child.queuedMemberships;
    if (active.isEmpty && queued.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final m in active) _summaryRow(m, queuedRow: false),
        for (final m in queued) _summaryRow(m, queuedRow: true),
      ],
    );
  }

  Widget _summaryRow(MembershipEntry m, {required bool queuedRow}) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final endDay = DateTime(m.endDate.year, m.endDate.month, m.endDate.day);
    final daysLeft = endDay.difference(today).inDays;
    final trailing = queuedRow
        ? 'starts ${_fmt(m.startDate)}'
        : '${m.creditsRemaining} credit${m.creditsRemaining == 1 ? '' : 's'} · $daysLeft days left';
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          Icon(queuedRow ? Icons.schedule_rounded : Icons.verified_rounded,
              color: queuedRow ? AppColors.textMuted : AppColors.primary,
              size: 14),
          const SizedBox(width: 8),
          Expanded(
            child: Text(m.planName,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary)),
          ),
          const SizedBox(width: 8),
          Text(trailing,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: !queuedRow && daysLeft < 7
                      ? AppColors.error
                      : AppColors.textMuted)),
        ],
      ),
    );
  }

  Widget _buildEditable(BuildContext context) {
    final plans = child.memberships;
    if (plans.isEmpty) {
      return const Padding(
        padding: EdgeInsets.only(top: 6),
        child: Text(
            'No junior packages yet — record one under Cash Payment, or the '
            'parent can buy one in the app.',
            style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
      );
    }
    return Column(
      children: [
        for (var i = 0; i < plans.length; i++)
          PlanRow(
            entry: plans[i],
            onEdit: () => _editDates(context, i),
            onSetStatus: (status) => _setStatus(context, i, status),
          ),
      ],
    );
  }

  Future<void> _editDates(BuildContext context, int index) async {
    final entry = child.memberships[index];
    final newStart = await showDatePicker(
      context: context,
      initialDate: entry.startDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
      helpText: '${entry.planName} — start date',
    );
    if (newStart == null || !context.mounted) return;
    final newEnd = await showDatePicker(
      context: context,
      initialDate: entry.endDate.isAfter(newStart) ? entry.endDate : newStart,
      firstDate: newStart,
      lastDate: DateTime.now().add(const Duration(days: 3650)),
      helpText: '${entry.planName} — end date',
    );
    if (newEnd == null || !context.mounted) return;
    final list = List<MembershipEntry>.of(child.memberships)
      ..[index] = entry.copyWith(startDate: newStart, endDate: newEnd);
    await UserService.updateMemberships(parentUid, list, childId: child.id);
    if (context.mounted) AppToast.success(context, 'Package dates updated');
  }

  /// Same guard as the adult plan editor: at most one active entry per
  /// plan name, since credit deduction assumes it.
  Future<void> _setStatus(
      BuildContext context, int index, String status) async {
    final plans = child.memberships;
    final planName = plans[index].planName;
    if (status == 'active' &&
        plans.any(
            (m) => m.isActive && m != plans[index] && m.planName == planName)) {
      AppToast.error(context,
          'Another $planName package is already active — set it to expired first');
      return;
    }
    final list = List<MembershipEntry>.of(plans)
      ..[index] = plans[index].copyWith(status: status);
    await UserService.updateMemberships(parentUid, list, childId: child.id);
    if (context.mounted) AppToast.success(context, 'Package status updated');
  }

  static String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}

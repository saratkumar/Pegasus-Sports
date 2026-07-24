import 'package:flutter/material.dart';
import '../../models/class_model.dart';
import '../../services/class_cancellation_service.dart';
import '../../services/class_service.dart';
import '../../services/waiting_list_service.dart';
import '../../utils/app_colors.dart';
import '../../utils/app_toast.dart';
import '../../widgets/timeline_range_selector.dart';

/// Direct admin "cancel a session" / "cancel this whole class" actions —
/// separate from ClassManagementScreen's create/edit/delete flow, since
/// cancelling has real cascading side effects (refunds, waitlist, client
/// emails) that a plain delete never had. See ClassCancellationService.
class CancelClassesScreen extends StatelessWidget {
  const CancelClassesScreen({super.key});

  Future<void> _cancelSession(BuildContext context, ClassModel cls) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final date = await showDatePicker(
      context: context,
      initialDate: today,
      firstDate: today,
      lastDate: today.add(const Duration(days: 365)),
      helpText: 'Select the session to cancel',
    );
    if (date == null || !context.mounted) return;

    if (cls.isCancelledOn(date)) {
      AppToast.info(context, 'That date is already cancelled');
      return;
    }

    final classId = cls.effectiveId;
    final bookingCount = await ClassService.getBookingCount(classId, date);
    final waitingCount = await WaitingListService.getWaitingCount(classId, date);
    if (!context.mounted) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text('Cancel ${cls.mode}?',
            style: const TextStyle(
                color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
        content: Text(
          '${formatWithWeekday(date)}\n\n'
          '$bookingCount booking${bookingCount == 1 ? '' : 's'} will be cancelled '
          'and refunded'
          '${waitingCount > 0 ? ', and $waitingCount waiting-list entr${waitingCount == 1 ? 'y' : 'ies'} cleared and refunded' : ''}. '
          'Affected clients will be emailed. This cannot be undone.',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Back',
                  style: TextStyle(color: AppColors.primary))),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.error,
                  foregroundColor: Colors.white),
              child: const Text('Cancel Session')),
        ],
      ),
    );
    if (confirm != true || !context.mounted) return;

    try {
      final result = await ClassCancellationService.cancelSession(cls, date);
      if (context.mounted) {
        final entryWord = result.waitlistCleared == 1 ? 'entry' : 'entries';
        AppToast.success(context,
            '${result.bookingsCancelled} booking(s) cancelled, ${result.waitlistCleared} waitlist $entryWord cleared');
      }
    } catch (e) {
      if (context.mounted) AppToast.error(context, 'Failed: $e');
    }
  }

  Future<void> _cancelWholeClass(BuildContext context, ClassModel cls) async {
    final preview =
        await ClassCancellationService.previewFutureBookingsCount(cls.effectiveId);
    if (!context.mounted) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text('Cancel all of ${cls.mode}?',
            style: const TextStyle(
                color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
        content: Text(
          'This cancels every future session — $preview upcoming booking${preview == 1 ? '' : 's'} '
          'will be cancelled and refunded, the waiting list cleared and refunded, '
          'affected clients emailed, and the class removed from the timetable. '
          'This cannot be undone.',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Back',
                  style: TextStyle(color: AppColors.primary))),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.error,
                  foregroundColor: Colors.white),
              child: const Text('Cancel Whole Class')),
        ],
      ),
    );
    if (confirm != true || !context.mounted) return;

    try {
      final result = await ClassCancellationService.cancelWholeClass(cls);
      if (context.mounted) {
        AppToast.success(context,
            'Class cancelled — ${result.bookingsCancelled} booking(s) refunded, ${result.waitlistCleared} waitlist entries cleared');
      }
    } catch (e) {
      if (context.mounted) AppToast.error(context, 'Failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cancel Classes')),
      body: StreamBuilder<List<ClassModel>>(
        stream: ClassService.streamClasses(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
            return const Center(
                child: CircularProgressIndicator(color: AppColors.primary));
          }
          final classes = (snap.data ?? [])
            ..sort((a, b) => a.mode.compareTo(b.mode));
          if (classes.isEmpty) {
            return const Center(
              child: Text('No classes yet',
                  style: TextStyle(color: AppColors.textSecondary)),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(14),
            itemCount: classes.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final cls = classes[i];
              return _ClassCancelCard(
                cls: cls,
                onCancelSession: () => _cancelSession(context, cls),
                onCancelWholeClass: () => _cancelWholeClass(context, cls),
              );
            },
          );
        },
      ),
    );
  }
}

class _ClassCancelCard extends StatelessWidget {
  final ClassModel cls;
  final VoidCallback onCancelSession;
  final VoidCallback onCancelWholeClass;

  const _ClassCancelCard({
    required this.cls,
    required this.onCancelSession,
    required this.onCancelWholeClass,
  });

  @override
  Widget build(BuildContext context) {
    final inactive = !cls.isActive;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(cls.mode,
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary)),
              ),
              if (inactive)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.textMuted.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text('INACTIVE',
                      style: TextStyle(
                          fontSize: 10,
                          color: AppColors.textMuted,
                          fontWeight: FontWeight.w700)),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${cls.occurrence == 'weekly' ? cls.day : cls.occurrence[0].toUpperCase()}${cls.occurrence == 'weekly' ? '' : cls.occurrence.substring(1)} · ${cls.startTime} · ${cls.coach}',
            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: inactive ? null : onCancelSession,
                  icon: const Icon(Icons.event_busy, size: 16),
                  label: const Text('Cancel a Session'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.warning,
                    side: BorderSide(color: AppColors.warning.withValues(alpha: 0.5)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: inactive ? null : onCancelWholeClass,
                  icon: const Icon(Icons.cancel_outlined, size: 16),
                  label: const Text('Cancel Whole Class'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.error,
                    side: BorderSide(color: AppColors.error.withValues(alpha: 0.5)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

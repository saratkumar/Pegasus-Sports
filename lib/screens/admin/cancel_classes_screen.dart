import 'package:flutter/material.dart';
import '../../models/class_model.dart';
import '../../services/class_cancellation_service.dart';
import '../../services/class_service.dart';
import '../../services/waiting_list_service.dart';
import '../../utils/app_colors.dart';
import '../../utils/app_toast.dart';
import '../../utils/time_utils.dart';
import '../../widgets/timeline_range_selector.dart';

/// Direct admin "cancel a session" / "cancel this whole class" actions —
/// separate from ClassManagementScreen's create/edit/delete flow, since
/// cancelling has real cascading side effects (refunds, waitlist, client
/// emails) that a plain delete never had. See ClassCancellationService.
///
/// "Upcoming sessions" lists each dated session (e.g. Tue 17 Nov · 9:30 AM)
/// so one tap cancels exactly that session — no date to pick. "Whole
/// classes" stops every future week of a repeating class.
class CancelClassesScreen extends StatelessWidget {
  const CancelClassesScreen({super.key});

  /// How far ahead the session list looks.
  static const _daysAhead = 28;

  /// Confirms, then cancels [cls] on [date] only: that session's bookings
  /// are cancelled and refunded, its waiting list cleared, clients emailed.
  /// Other times that day, and other weeks of this class, are untouched.
  Future<void> _cancelOne(
      BuildContext context, ClassModel cls, DateTime date) async {
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
          '${formatWithWeekday(date)} · ${cls.startTime}\n\n'
          'Only this session is cancelled. '
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
            '${cls.mode} ${cls.startTime} cancelled — ${result.bookingsCancelled} booking(s) refunded, ${result.waitlistCleared} waitlist $entryWord cleared');
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
          '${_scheduleLabel(cls)}\n\n'
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
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Cancel Classes'),
          bottom: const TabBar(
            indicatorColor: AppColors.primary,
            labelColor: AppColors.textPrimary,
            unselectedLabelColor: AppColors.textMuted,
            tabs: [
              Tab(text: 'Upcoming sessions'),
              Tab(text: 'Whole classes'),
            ],
          ),
        ),
        body: StreamBuilder<List<ClassModel>>(
          stream: ClassService.streamClasses(),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting &&
                !snap.hasData) {
              return const Center(
                  child: CircularProgressIndicator(color: AppColors.primary));
            }
            final classes = snap.data ?? [];
            if (classes.isEmpty) {
              return const Center(
                child: Text('No classes yet',
                    style: TextStyle(color: AppColors.textSecondary)),
              );
            }
            return TabBarView(children: [
              _sessionsTab(context, classes),
              _wholeClassesTab(context, classes),
            ]);
          },
        ),
      ),
    );
  }

  /// Every session in the next [_daysAhead] days, grouped by date and sorted
  /// by time. Already-cancelled sessions stay listed (greyed) so it's clear
  /// what has been cancelled.
  Widget _sessionsTab(BuildContext context, List<ClassModel> classes) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final active = classes.where((c) => c.isActive).toList();
    final children = <Widget>[];
    for (var i = 0; i < _daysAhead; i++) {
      final date = today.add(Duration(days: i));
      final sessions = active
          .where((c) => c.occursOn(date) || c.isCancelledOn(date))
          .toList()
        ..sort((a, b) {
          final byTime = _startMinutes(a).compareTo(_startMinutes(b));
          return byTime != 0 ? byTime : a.mode.compareTo(b.mode);
        });
      if (sessions.isEmpty) continue;
      children.add(Padding(
        padding: const EdgeInsets.fromLTRB(4, 14, 4, 6),
        child: Text(
          i == 0 ? 'Today · ${formatWithWeekday(date)}' : formatWithWeekday(date),
          style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.textSecondary),
        ),
      ));
      for (final cls in sessions) {
        children.add(_SessionRow(
          cls: cls,
          cancelled: cls.isCancelledOn(date),
          onCancel: () => _cancelOne(context, cls, date),
        ));
      }
    }
    if (children.isEmpty) {
      return const Center(
        child: Text('No sessions in the next 4 weeks',
            style: TextStyle(color: AppColors.textSecondary)),
      );
    }
    return ListView(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 24), children: children);
  }

  Widget _wholeClassesTab(BuildContext context, List<ClassModel> classes) {
    // Stable order — name, then first weekday, then start time — so classes
    // sharing a name (one per time slot) don't swap places on refresh.
    final sorted = List.of(classes)
      ..sort((a, b) {
        final byName = a.mode.compareTo(b.mode);
        if (byName != 0) return byName;
        final byDay = _firstDayIndex(a).compareTo(_firstDayIndex(b));
        if (byDay != 0) return byDay;
        return _startMinutes(a).compareTo(_startMinutes(b));
      });
    return ListView.separated(
      padding: const EdgeInsets.all(14),
      itemCount: sorted.length + 1,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        if (i == 0) {
          return const Text(
            'Stops every future week of a class. To cancel one date only, '
            'use Upcoming sessions.',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          );
        }
        final cls = sorted[i - 1];
        return _ClassCancelCard(
          cls: cls,
          onCancelWholeClass: () => _cancelWholeClass(context, cls),
        );
      },
    );
  }
}

const _weekdays = [
  'Monday', 'Tuesday', 'Wednesday', 'Thursday',
  'Friday', 'Saturday', 'Sunday',
];

int _firstDayIndex(ClassModel c) => c.day
    .split(',')
    .map((d) => _weekdays.indexOf(d.trim()))
    .where((i) => i >= 0)
    .fold<int>(99, (m, i) => i < m ? i : m);

int _startMinutes(ClassModel c) {
  final t = parseTimeString(c.startTime);
  return t == null ? 24 * 60 : t.hour * 60 + t.minute;
}

String _scheduleLabel(ClassModel cls) => cls.occurrence == 'weekly'
    ? '${cls.day.replaceAll(',', ', ')} · ${cls.startTime}'
    : '${cls.occurrence[0].toUpperCase()}${cls.occurrence.substring(1)} · ${cls.startTime}';

/// One dated session with its own Cancel button.
class _SessionRow extends StatelessWidget {
  final ClassModel cls;
  final bool cancelled;
  final VoidCallback onCancel;

  const _SessionRow({
    required this.cls,
    required this.cancelled,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      decoration: BoxDecoration(
        color: cancelled ? AppColors.surface : AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            child: Text(cls.startTime,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: cancelled
                        ? AppColors.textMuted
                        : AppColors.textPrimary)),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(cls.mode,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        decoration:
                            cancelled ? TextDecoration.lineThrough : null,
                        color: cancelled
                            ? AppColors.textMuted
                            : AppColors.textPrimary)),
                Text('${cls.duration} · ${cls.coach}',
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textMuted)),
              ],
            ),
          ),
          if (cancelled)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Text('Cancelled',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.error)),
            )
          else
            TextButton(
              onPressed: onCancel,
              style: TextButton.styleFrom(foregroundColor: AppColors.error),
              child: const Text('Cancel'),
            ),
        ],
      ),
    );
  }
}

class _ClassCancelCard extends StatelessWidget {
  final ClassModel cls;
  final VoidCallback onCancelWholeClass;

  const _ClassCancelCard({
    required this.cls,
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
          Text('${_scheduleLabel(cls)} · ${cls.coach}',
              style:
                  const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
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
    );
  }
}

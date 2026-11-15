import 'package:flutter/material.dart';
import '../models/class_model.dart';
import '../services/class_cancellation_service.dart';
import '../services/class_reschedule_service.dart';
import '../services/waiting_list_service.dart';
import '../utils/app_colors.dart';
import '../utils/app_toast.dart';
import 'timeline_range_selector.dart' show formatWithWeekday;

/// Admin-only actions for one session, opened from the Class Roster:
/// reschedule this session / the whole class, or cancel this session / the
/// whole class. Cancelling reuses ClassCancellationService exactly as the
/// Cancel Classes screen does; rescheduling uses ClassRescheduleService.
/// Returns true when something changed, so the caller can reload.
Future<bool> showSessionAdminActions(
  BuildContext context, {
  required ClassModel cls,
  required DateTime date,
}) async {
  final action = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: AppColors.bg,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text('${cls.mode}\n${formatWithWeekday(date)} · ${cls.startTime}',
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary)),
            ),
            const SizedBox(height: 8),
            _actionTile(ctx, 'reschedule_session', Icons.event_repeat,
                AppColors.primary, 'Reschedule this session',
                'Move just this date to another date/time. Bookings move with it.'),
            _actionTile(ctx, 'reschedule_class', Icons.edit_calendar,
                AppColors.primary, 'Reschedule whole class',
                'Change the day/time for every session from now on.'),
            const Divider(),
            _actionTile(ctx, 'cancel_session', Icons.event_busy,
                AppColors.warning, 'Cancel this session',
                'Bookings are cancelled and refunded.'),
            _actionTile(ctx, 'cancel_class', Icons.cancel_outlined,
                AppColors.error, 'Cancel whole class',
                'Every future session is cancelled and refunded.'),
          ],
        ),
      ),
    ),
  );
  if (action == null || !context.mounted) return false;
  switch (action) {
    case 'reschedule_session':
      return _rescheduleSession(context, cls, date);
    case 'reschedule_class':
      return _rescheduleClass(context, cls);
    case 'cancel_session':
      return _cancelSession(context, cls, date);
    case 'cancel_class':
      return _cancelWholeClass(context, cls);
  }
  return false;
}

Widget _actionTile(BuildContext ctx, String value, IconData icon, Color color,
    String title, String subtitle) {
  return ListTile(
    leading: Icon(icon, color: color),
    title: Text(title,
        style: TextStyle(color: color, fontWeight: FontWeight.w600)),
    subtitle: Text(subtitle,
        style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
    onTap: () => Navigator.pop(ctx, value),
  );
}

TimeOfDay _endFor(ClassModel cls, TimeOfDay start) {
  final mins = ClassRescheduleService.parseDuration(cls.duration) ?? 60;
  final total = (start.hour * 60 + start.minute + mins) % (24 * 60);
  return TimeOfDay(hour: total ~/ 60, minute: total % 60);
}

Future<bool> _confirm(BuildContext context,
    {required String title,
    required String body,
    required String action,
    required Color color}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Text(title,
          style: const TextStyle(
              color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
      content: Text(body, style: const TextStyle(color: AppColors.textSecondary)),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Back', style: TextStyle(color: AppColors.primary))),
        ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: color, foregroundColor: Colors.white),
            child: Text(action)),
      ],
    ),
  );
  return ok == true;
}

// ── Reschedule ───────────────────────────────────────────────────────────

Future<bool> _rescheduleSession(
    BuildContext context, ClassModel cls, DateTime date) async {
  final start = ClassRescheduleService.parseTime(cls.startTime) ??
      const TimeOfDay(hour: 9, minute: 0);
  final picked = await showModalBottomSheet<_SlotChoice>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.bg,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => _RescheduleSheet(
      title: 'Reschedule this session',
      subtitle: '${cls.mode} · was ${formatWithWeekday(date)} at ${cls.startTime}',
      initialDate: date,
      initialStart: start,
      initialEnd: _endFor(cls, start),
    ),
  );
  if (picked == null || !context.mounted) return false;

  final newDate = picked.date!;
  final unchanged = DateUtils.isSameDay(newDate, date) &&
      ClassRescheduleService.formatTime(picked.start) == cls.startTime;
  if (unchanged) {
    AppToast.info(context, 'That is the same date and time');
    return false;
  }

  final bookings = await ClassRescheduleService.bookingsOn(cls, date);
  final waiting = await WaitingListService.getWaitingCount(cls.effectiveId, date);
  if (!context.mounted) return false;
  final newWhen =
      '${formatWithWeekday(newDate)}, ${ClassRescheduleService.formatTime(picked.start)}–'
      '${ClassRescheduleService.formatTime(picked.end)}';
  final ok = await _confirm(
    context,
    title: 'Move ${cls.mode}?',
    body: 'From ${formatWithWeekday(date)} at ${cls.startTime}\n'
        'To $newWhen\n\n'
        '$bookings booking${bookings == 1 ? '' : 's'}'
        '${waiting > 0 ? ' and $waiting waiting-list entr${waiting == 1 ? 'y' : 'ies'}' : ''} '
        'will move to the new time. No credits are refunded or used, and '
        'affected clients will be emailed the new time. '
        'The rest of the series stays as it is.',
    action: 'Reschedule',
    color: AppColors.primary,
  );
  if (!ok || !context.mounted) return false;

  try {
    final r = await ClassRescheduleService.rescheduleSession(
      cls: cls,
      fromDate: date,
      toDate: newDate,
      newStart: picked.start,
      newEnd: picked.end,
    );
    if (context.mounted) {
      AppToast.success(context,
          'Session moved — ${r.bookingsMoved} booking(s) and ${r.waitlistMoved} waitlist entr${r.waitlistMoved == 1 ? 'y' : 'ies'} moved');
    }
    return true;
  } catch (e) {
    if (context.mounted) AppToast.error(context, 'Failed: $e');
    return false;
  }
}

Future<bool> _rescheduleClass(BuildContext context, ClassModel cls) async {
  if (cls.occurrence == 'once') {
    AppToast.info(context,
        'This is a one-off session — use "Reschedule this session" instead');
    return false;
  }
  final weekly = cls.occurrence == 'weekly' || cls.occurrence.isEmpty;
  final start = ClassRescheduleService.parseTime(cls.startTime) ??
      const TimeOfDay(hour: 9, minute: 0);
  final currentDays = cls.day
      .split(',')
      .map((d) => d.trim())
      .where(ClassRescheduleService.dayNames.contains)
      .toSet();
  final picked = await showModalBottomSheet<_SlotChoice>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.bg,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => _RescheduleSheet(
      title: 'Reschedule whole class',
      subtitle: '${cls.mode} · now ${weekly ? cls.day.replaceAll(',', ', ') : cls.occurrence} at ${cls.startTime}',
      initialDays: weekly ? currentDays : null,
      initialStart: start,
      initialEnd: _endFor(cls, start),
    ),
  );
  if (picked == null || !context.mounted) return false;

  final days = picked.days ?? currentDays;
  final preview =
      await ClassRescheduleService.previewWholeClass(cls: cls, newDays: days);
  if (!context.mounted) return false;
  final newWhen = '${weekly ? '${ClassRescheduleService.dayNames.where(days.contains).join(', ')}, ' : ''}'
      '${ClassRescheduleService.formatTime(picked.start)}–${ClassRescheduleService.formatTime(picked.end)}';
  final ok = await _confirm(
    context,
    title: 'Reschedule all of ${cls.mode}?',
    body: 'New schedule: $newWhen\n\n'
        '${preview.bookings} upcoming booking${preview.bookings == 1 ? '' : 's'} '
        'will move to the next session on the new schedule (same date if only '
        'the time changes). No credits are refunded or used, and affected '
        'clients will be emailed.'
        '${preview.overCapacity.isEmpty ? '' : '\n\n⚠ Over capacity after the move:\n${preview.overCapacity.join('\n')}'}',
    action: 'Reschedule',
    color: AppColors.primary,
  );
  if (!ok || !context.mounted) return false;

  try {
    final r = await ClassRescheduleService.rescheduleWholeClass(
      cls: cls,
      newDays: days,
      newStart: picked.start,
      newEnd: picked.end,
    );
    if (context.mounted) {
      AppToast.success(context,
          'Class rescheduled — ${r.bookingsMoved} booking(s) moved');
    }
    return true;
  } catch (e) {
    if (context.mounted) AppToast.error(context, 'Failed: $e');
    return false;
  }
}

// ── Cancel (same service calls as the Cancel Classes screen) ─────────────

Future<bool> _cancelSession(
    BuildContext context, ClassModel cls, DateTime date) async {
  final bookings = await ClassRescheduleService.bookingsOn(cls, date);
  final waiting = await WaitingListService.getWaitingCount(cls.effectiveId, date);
  if (!context.mounted) return false;
  final ok = await _confirm(
    context,
    title: 'Cancel ${cls.mode}?',
    body: '${formatWithWeekday(date)}\n\n'
        '$bookings booking${bookings == 1 ? '' : 's'} will be cancelled and refunded'
        '${waiting > 0 ? ', and $waiting waiting-list entr${waiting == 1 ? 'y' : 'ies'} cleared and refunded' : ''}. '
        'Affected clients will be emailed. This cannot be undone.',
    action: 'Cancel Session',
    color: AppColors.error,
  );
  if (!ok || !context.mounted) return false;
  try {
    final r = await ClassCancellationService.cancelSession(cls, date);
    if (context.mounted) {
      AppToast.success(context,
          '${r.bookingsCancelled} booking(s) cancelled, ${r.waitlistCleared} waitlist entr${r.waitlistCleared == 1 ? 'y' : 'ies'} cleared');
    }
    return true;
  } catch (e) {
    if (context.mounted) AppToast.error(context, 'Failed: $e');
    return false;
  }
}

Future<bool> _cancelWholeClass(BuildContext context, ClassModel cls) async {
  final preview =
      await ClassCancellationService.previewFutureBookingsCount(cls.effectiveId);
  if (!context.mounted) return false;
  final ok = await _confirm(
    context,
    title: 'Cancel all of ${cls.mode}?',
    body: 'This cancels every future session — $preview upcoming booking${preview == 1 ? '' : 's'} '
        'will be cancelled and refunded, the waiting list cleared and refunded, '
        'affected clients emailed, and the class removed from the timetable. '
        'This cannot be undone.',
    action: 'Cancel Whole Class',
    color: AppColors.error,
  );
  if (!ok || !context.mounted) return false;
  try {
    final r = await ClassCancellationService.cancelWholeClass(cls);
    if (context.mounted) {
      AppToast.success(context,
          'Class cancelled — ${r.bookingsCancelled} booking(s) refunded, ${r.waitlistCleared} waitlist entries cleared');
    }
    return true;
  } catch (e) {
    if (context.mounted) AppToast.error(context, 'Failed: $e');
    return false;
  }
}

// ── Date/time picker sheet ───────────────────────────────────────────────

class _SlotChoice {
  final DateTime? date;
  final Set<String>? days;
  final TimeOfDay start;
  final TimeOfDay end;
  _SlotChoice({this.date, this.days, required this.start, required this.end});
}

/// Pick a new date (single session) or days (whole weekly class), plus a
/// start and end time.
class _RescheduleSheet extends StatefulWidget {
  final String title;
  final String subtitle;
  final DateTime? initialDate;
  final Set<String>? initialDays;
  final TimeOfDay initialStart;
  final TimeOfDay initialEnd;

  const _RescheduleSheet({
    required this.title,
    required this.subtitle,
    this.initialDate,
    this.initialDays,
    required this.initialStart,
    required this.initialEnd,
  });

  @override
  State<_RescheduleSheet> createState() => _RescheduleSheetState();
}

class _RescheduleSheetState extends State<_RescheduleSheet> {
  late DateTime? _date = widget.initialDate;
  late final Set<String>? _days =
      widget.initialDays == null ? null : {...widget.initialDays!};
  late TimeOfDay _start = widget.initialStart;
  late TimeOfDay _end = widget.initialEnd;

  Future<void> _pickDate() async {
    final today = DateUtils.dateOnly(DateTime.now());
    final d = await showDatePicker(
      context: context,
      initialDate: _date != null && !_date!.isBefore(today) ? _date! : today,
      firstDate: today,
      lastDate: today.add(const Duration(days: 365)),
      helpText: 'New date',
    );
    if (d != null) setState(() => _date = d);
  }

  Future<void> _pickTime(bool isStart) async {
    final t = await showTimePicker(
      context: context,
      initialTime: isStart ? _start : _end,
      helpText: isStart ? 'START TIME' : 'END TIME',
    );
    if (t == null) return;
    setState(() {
      if (isStart) {
        final length = ClassRescheduleService.minutesBetween(_start, _end);
        _start = t;
        final total = (t.hour * 60 + t.minute + length) % (24 * 60);
        _end = TimeOfDay(hour: total ~/ 60, minute: total % 60);
      } else {
        _end = t;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final days = _days;
    final valid = _start != _end && (days == null || days.isNotEmpty);
    final mins = ClassRescheduleService.minutesBetween(_start, _end);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.title,
                style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary)),
            const SizedBox(height: 4),
            Text(widget.subtitle,
                style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
            const SizedBox(height: 16),
            if (widget.initialDate != null)
              OutlinedButton.icon(
                onPressed: _pickDate,
                icon: const Icon(Icons.calendar_today, size: 18),
                label: Text(_date == null ? 'Pick a date' : formatWithWeekday(_date!)),
              ),
            if (days != null)
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final d in ClassRescheduleService.dayNames)
                    FilterChip(
                      label: Text(d.substring(0, 3)),
                      selected: days.contains(d),
                      onSelected: (on) =>
                          setState(() => on ? days.add(d) : days.remove(d)),
                    ),
                ],
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickTime(true),
                    icon: const Icon(Icons.schedule, size: 18),
                    label: Text('Start ${ClassRescheduleService.formatTime(_start)}'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickTime(false),
                    icon: const Icon(Icons.schedule, size: 18),
                    label: Text('End ${ClassRescheduleService.formatTime(_end)}'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text('Duration: ${ClassRescheduleService.formatDuration(mins)}',
                style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: !valid || (widget.initialDate != null && _date == null)
                    ? null
                    : () => Navigator.pop(
                          context,
                          _SlotChoice(
                              date: _date, days: days, start: _start, end: _end),
                        ),
                child: const Text('Continue'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

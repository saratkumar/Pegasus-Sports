import 'package:flutter/material.dart';
import '../utils/app_colors.dart';

/// Shared "from – to" history filter — every history/timeline view (Resolved
/// QR Payments, Transaction History, client booking History, admin Activity
/// Log) fetches its full unfiltered Sheet mirror and filters client-side, so
/// the range is capped at 3 months to keep that bounded. `null` means "no
/// explicit selection" and falls back to the default: the last 1 month
/// ending today.
const int kMaxDateRangeDays = 90; // 3 months
const int kDefaultDateRangeDays = 30; // 1 month

DateTimeRange defaultDateRange() {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  return DateTimeRange(
    start: today.subtract(const Duration(days: kDefaultDateRangeDays - 1)),
    end: today,
  );
}

/// Clamps [range] to at most [kMaxDateRangeDays] days, keeping the end fixed
/// and pulling the start forward if the user picked a wider span.
DateTimeRange clampDateRange(DateTimeRange range) {
  final span = range.end.difference(range.start).inDays;
  if (span <= kMaxDateRangeDays) return range;
  return DateTimeRange(
    start: range.end.subtract(const Duration(days: kMaxDateRangeDays)),
    end: range.end,
  );
}

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
];

/// e.g. "Fri, 24 Jul 2026" — every date shown in a filtering context includes
/// the weekday, not just the day-of-month.
String formatWithWeekday(DateTime d) =>
    '${_weekdays[d.weekday - 1]}, ${d.day} ${_months[d.month - 1]} ${d.year}';

/// Parses the loosely-typed date/timestamp strings that come back from the
/// Sheet mirror (ISO `timestamp` on ActivityLog rows, plain `YYYY-MM-DD`
/// `date` on Transactions rows) and reports whether they fall within
/// [range] (inclusive of both ends, compared by calendar day). Rows with an
/// unparseable date are excluded rather than crashing or assumed-recent.
bool isWithinRange(String? rawDate, DateTimeRange range) {
  if (rawDate == null || rawDate.isEmpty) return false;
  final dt = DateTime.tryParse(rawDate);
  if (dt == null) return false;
  final day = DateTime(dt.year, dt.month, dt.day);
  final start = DateTime(range.start.year, range.start.month, range.start.day);
  final end = DateTime(range.end.year, range.end.month, range.end.day);
  return !day.isBefore(start) && !day.isAfter(end);
}

/// Button that opens a from–to range picker capped at 3 months, showing
/// "Last 1 Month" when [value] is null (the default, unselected state).
class DateRangeFilterBar extends StatelessWidget {
  final DateTimeRange? value;
  final ValueChanged<DateTimeRange?> onChanged;

  const DateRangeFilterBar({
    super.key,
    required this.value,
    required this.onChanged,
  });

  Future<void> _pick(BuildContext context) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final picked = await showDateRangePicker(
      context: context,
      firstDate: today.subtract(const Duration(days: 365)),
      lastDate: today,
      initialDateRange: value ?? defaultDateRange(),
      helpText: 'Select date range (max 3 months)',
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: Theme.of(context)
              .colorScheme
              .copyWith(primary: AppColors.primary),
        ),
        child: child!,
      ),
    );
    if (picked == null) return;
    final clamped = clampDateRange(picked);
    if (clamped != picked && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Range capped to the most recent 3 months')),
      );
    }
    onChanged(clamped);
  }

  @override
  Widget build(BuildContext context) {
    final range = value;
    final label = range == null
        ? 'Last 1 Month'
        : '${formatWithWeekday(range.start)}  →  ${formatWithWeekday(range.end)}';
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => _pick(context),
            icon: const Icon(Icons.date_range, size: 16),
            label: Text(label,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12)),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.textPrimary,
              side: const BorderSide(color: AppColors.divider),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              alignment: Alignment.centerLeft,
            ),
          ),
        ),
        if (range != null)
          IconButton(
            icon: const Icon(Icons.clear, size: 18, color: AppColors.textMuted),
            tooltip: 'Reset to last 1 month',
            onPressed: () => onChanged(null),
          ),
      ],
    );
  }
}

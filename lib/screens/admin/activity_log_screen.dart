import 'package:flutter/material.dart';
import '../../models/user_model.dart';
import '../../services/config_service.dart';
import '../../services/user_service.dart';
import '../../utils/app_colors.dart';
import '../../widgets/timeline_range_selector.dart';

/// Full, unfiltered feed of every event mirrored to the ActivityLog Google
/// Sheet within a date range — bookings, cancellations, waiting-list
/// activity, trainer requests and their resolutions, and admin credit
/// adjustments. Admin-only. Read from the Sheet mirror, not Firestore — see
/// ConfigService.logActivityEvent/getActivityLog.
class ActivityLogScreen extends StatefulWidget {
  const ActivityLogScreen({super.key});

  @override
  State<ActivityLogScreen> createState() => _ActivityLogScreenState();
}

class _ActivityLogScreenState extends State<ActivityLogScreen> {
  DateTimeRange? _range;
  bool _loading = false;
  bool _loaded = false;
  List<Map<String, String>> _rows = [];

  UserModel? _selectedUser;
  List<UserModel> _allUsers = [];

  @override
  void initState() {
    super.initState();
    // Independent of _loading/_loaded (the log's own fetch state) so the
    // search field is usable immediately, without waiting on a Load tap.
    UserService.getAllUsers().then((users) {
      if (!mounted) return;
      setState(() => _allUsers = users);
    });
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loaded = false;
    });
    // Filtered by when the action actually happened (timestamp), not the
    // class's session date — a booking made today for a future class
    // should show up under today, not the class's date. get_activity_log's
    // server-side `date` filter matches on sessionDate, so that doesn't fit
    // here; fetch unfiltered (or scoped to the selected user, all-time) and
    // filter client-side on timestamp instead.
    final all = _selectedUser != null
        ? await ConfigService.getActivityLog(userId: _selectedUser!.uid)
        : await ConfigService.getActivityLog();
    final range = _range ?? defaultDateRange();
    final rows = all.where((r) => isWithinRange(r['timestamp'], range)).toList();
    rows.sort((a, b) => (b['timestamp'] ?? '').compareTo(a['timestamp'] ?? ''));
    if (!mounted) return;
    setState(() {
      _rows = rows;
      _loading = false;
      _loaded = true;
    });
  }

  ({IconData icon, Color color}) _styleFor(String eventType) {
    final e = eventType.toLowerCase();
    if (e.contains('cancelled') || e.contains('rejected')) {
      return (icon: Icons.cancel_outlined, color: AppColors.error);
    }
    if (e.contains('waitlist') || e.contains('requested') || e.contains('submitted')) {
      return (icon: Icons.hourglass_top, color: const Color(0xFFFFAB40));
    }
    if (e.contains('credit adjusted')) {
      return (icon: Icons.toll_rounded, color: AppColors.primary);
    }
    if (e.contains('approved') || e.contains('admitted') || e.contains('reassigned') || e.contains('booked')) {
      return (icon: Icons.check_circle_outline, color: const Color(0xFF00D4AA));
    }
    return (icon: Icons.circle_outlined, color: AppColors.textMuted);
  }

  String _fmtTimestamp(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return '';
    final local = dt.toLocal();
    final time =
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    return '${formatWithWeekday(local)} · $time';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Activity Log')),
      body: Column(
        children: [
          Container(
            color: AppColors.bg,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Column(
              children: [
                _UserSearchField(
                  users: _allUsers,
                  selected: _selectedUser,
                  onSelected: (u) {
                    setState(() {
                      _selectedUser = u;
                      _loaded = false;
                      _rows = [];
                    });
                    _load();
                  },
                ),
                const SizedBox(height: 10),
                DateRangeFilterBar(
                  value: _range,
                  onChanged: (r) => setState(() {
                    _range = r;
                    _loaded = false;
                    _rows = [];
                  }),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            child: ElevatedButton.icon(
              onPressed: _loading ? null : _load,
              icon: _loading
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.refresh, size: 18),
              label: Text(_loading ? 'Loading…' : 'Load'),
              style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 44)),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: const Text(
              'Every booking, cancellation, waitlist event, trainer request, '
              'and credit adjustment in this window — read from the Google '
              'Sheet mirror, not Firestore. Capped at 3 months.',
              style: TextStyle(fontSize: 11, color: AppColors.textMuted),
            ),
          ),
          const SizedBox(height: 8),
          const Divider(height: 1),
          if (!_loaded)
            const Expanded(
              child: Center(
                child: Text('Select a range and tap Load',
                    style: TextStyle(color: AppColors.textSecondary)),
              ),
            )
          else if (_rows.isEmpty)
            const Expanded(
              child: Center(
                child: Text('No activity in this window',
                    style: TextStyle(color: AppColors.textSecondary)),
              ),
            )
          else
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.all(14),
                itemCount: _rows.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, i) {
                  final row = _rows[i];
                  final eventType = row['eventType'] ?? '';
                  final style = _styleFor(eventType);
                  final className = row['className'] ?? '';
                  final userName = row['userName'] ?? '';
                  final note = row['note'] ?? '';
                  return Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.divider),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(style.icon, size: 18, color: style.color),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(eventType,
                                        style: TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 13,
                                            color: style.color)),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 3),
                              Text(
                                [userName, className]
                                    .where((s) => s.isNotEmpty)
                                    .join(' · '),
                                style: const TextStyle(
                                    fontSize: 13, color: AppColors.textPrimary),
                              ),
                              const SizedBox(height: 2),
                              Text(_fmtTimestamp(row['timestamp']),
                                  style: const TextStyle(
                                      fontSize: 11, color: AppColors.textMuted)),
                              if (note.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(note,
                                    style: const TextStyle(
                                        fontSize: 11,
                                        color: AppColors.textSecondary,
                                        fontStyle: FontStyle.italic)),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

// ── User search ──────────────────────────────────────────────────────────────

/// Lets the admin scope the log to one user's all-time history. Collapses to
/// a chip once a user is picked; shows a filterable list while searching.
class _UserSearchField extends StatefulWidget {
  final List<UserModel> users;
  final UserModel? selected;
  final ValueChanged<UserModel?> onSelected;

  const _UserSearchField({
    required this.users,
    required this.selected,
    required this.onSelected,
  });

  @override
  State<_UserSearchField> createState() => _UserSearchFieldState();
}

class _UserSearchFieldState extends State<_UserSearchField> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    if (selected != null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.divider),
        ),
        child: Row(
          children: [
            const Icon(Icons.person_outline,
                size: 18, color: AppColors.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(selected.name,
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary)),
                  Text(selected.email,
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.textSecondary)),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.clear, size: 18, color: AppColors.textMuted),
              tooltip: 'Clear user filter',
              onPressed: () => widget.onSelected(null),
            ),
          ],
        ),
      );
    }

    final q = _query.trim().toLowerCase();
    final matches = q.isEmpty
        ? const <UserModel>[]
        : widget.users
            .where((u) =>
                u.name.toLowerCase().contains(q) ||
                u.email.toLowerCase().contains(q))
            .take(20)
            .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          onChanged: (v) => setState(() => _query = v),
          decoration: InputDecoration(
            hintText: 'Search a user by name or email to filter their history...',
            hintStyle: const TextStyle(fontSize: 12),
            prefixIcon: const Icon(Icons.search, size: 18, color: AppColors.textMuted),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppColors.divider)),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppColors.divider)),
          ),
        ),
        if (q.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 6),
            constraints: const BoxConstraints(maxHeight: 220),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.divider),
            ),
            child: matches.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text('No matching users',
                        style: TextStyle(
                            fontSize: 12, color: AppColors.textMuted)),
                  )
                : Scrollbar(
                    thumbVisibility: true,
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: matches.length,
                      itemBuilder: (_, i) {
                        final u = matches[i];
                        return ListTile(
                          dense: true,
                          title: Text(u.name,
                              style: const TextStyle(
                                  fontSize: 13, color: AppColors.textPrimary)),
                          subtitle: Text(u.email,
                              style: const TextStyle(
                                  fontSize: 11, color: AppColors.textSecondary)),
                          onTap: () {
                            setState(() => _query = '');
                            widget.onSelected(u);
                          },
                        );
                      },
                    ),
                  ),
          ),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import '../../services/config_service.dart';
import '../../utils/app_colors.dart';

/// Shows who's currently enrolled in each class on a given day, reconciled
/// from the ActivityLog Google Sheet mirror (not Firestore) — see
/// ConfigService.logActivityEvent/getActivityLog. This is a best-effort
/// convenience view; Firestore remains the actual source of truth for
/// booking state.
class ClassRosterScreen extends StatefulWidget {
  const ClassRosterScreen({super.key});

  @override
  State<ClassRosterScreen> createState() => _ClassRosterScreenState();
}

class _ClassRosterScreenState extends State<ClassRosterScreen> {
  DateTime _date = DateTime(
      DateTime.now().year, DateTime.now().month, DateTime.now().day);
  bool _loading = false;
  bool _loaded = false;
  List<_ClassGroup> _groups = [];

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  String get _dateLabel =>
      '${_date.day.toString().padLeft(2, '0')} ${_months[_date.month - 1]} ${_date.year}';

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loaded = false;
    });
    final rows = await ConfigService.getActivityLog(date: _date);
    if (!mounted) return;
    setState(() {
      _groups = _buildRoster(rows);
      _loading = false;
      _loaded = true;
    });
  }

  List<_ClassGroup> _buildRoster(List<Map<String, String>> rows) {
    final cancelledIds = <String>{};
    for (final r in rows) {
      final type = r['eventType'] ?? '';
      final bid = r['bookingId'] ?? '';
      if (bid.isNotEmpty &&
          (type == 'Cancelled by Client' || type == 'Cancelled by Trainer')) {
        cancelledIds.add(bid);
      }
    }

    final groups = <String, _ClassGroup>{};
    for (final r in rows) {
      final type = r['eventType'] ?? '';
      if (type != 'Booked' && type != 'Admitted from Waitlist') continue;
      final bid = r['bookingId'] ?? '';
      if (bid.isNotEmpty && cancelledIds.contains(bid)) continue;

      final classId = r['classId'] ?? '';
      final sessionTime = r['sessionTime'] ?? '';
      final key = '$classId|$sessionTime';
      final group = groups.putIfAbsent(
        key,
        () => _ClassGroup(
          classId: classId,
          className: r['className'] ?? '',
          sessionTime: sessionTime,
        ),
      );
      group.members.add(_RosterEntry(
        userName: r['userName']?.isNotEmpty == true ? r['userName']! : 'Unknown',
        eventType: type,
        bookedByRole: r['bookedByRole'] ?? 'client',
      ));
    }

    final list = groups.values.toList()
      ..sort((a, b) => a.sessionTime.compareTo(b.sessionTime));
    return list;
  }

  void _prevDay() {
    setState(() {
      _date = _date.subtract(const Duration(days: 1));
      _loaded = false;
      _groups = [];
    });
  }

  void _nextDay() {
    setState(() {
      _date = _date.add(const Duration(days: 1));
      _loaded = false;
      _groups = [];
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Class Roster')),
      body: Column(
        children: [
          Container(
            color: AppColors.bg,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: _prevDay,
                ),
                Expanded(
                  child: Text(
                    _dateLabel,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: _nextDay,
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
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
              label: Text(_loading ? 'Loading…' : 'Load $_dateLabel'),
              style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 44)),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: const Text(
              'Read from the Google Sheet activity mirror, not Firestore — '
              'a best-effort convenience view, not an audit-proof record.',
              style: TextStyle(fontSize: 11, color: AppColors.textMuted),
            ),
          ),
          const SizedBox(height: 8),
          const Divider(height: 1),
          if (!_loaded)
            const Expanded(
              child: Center(
                child: Text('Select a day and tap Load',
                    style: TextStyle(color: AppColors.textSecondary)),
              ),
            )
          else if (_groups.isEmpty)
            const Expanded(
              child: Center(
                child: Text('No one signed up for this day',
                    style: TextStyle(color: AppColors.textSecondary)),
              ),
            )
          else
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.all(14),
                itemCount: _groups.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, i) => _GroupCard(group: _groups[i]),
              ),
            ),
        ],
      ),
    );
  }
}

class _ClassGroup {
  final String classId;
  final String className;
  final String sessionTime;
  final List<_RosterEntry> members = [];

  _ClassGroup({
    required this.classId,
    required this.className,
    required this.sessionTime,
  });
}

class _RosterEntry {
  final String userName;
  final String eventType;
  final String bookedByRole;

  _RosterEntry({
    required this.userName,
    required this.eventType,
    required this.bookedByRole,
  });
}

class _GroupCard extends StatelessWidget {
  final _ClassGroup group;
  const _GroupCard({required this.group});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          title: Text(group.className,
              style: const TextStyle(
                  fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          subtitle: Text(group.sessionTime,
              style:
                  const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text('${group.members.length} enrolled',
                style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700)),
          ),
          children: group.members
              .map((m) => Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(m.userName,
                              style: const TextStyle(
                                  fontSize: 14, color: AppColors.textPrimary)),
                        ),
                        if (m.eventType == 'Admitted from Waitlist')
                          _chip('waitlisted', const Color(0xFFFFAB40)),
                        if (m.bookedByRole != 'client') ...[
                          const SizedBox(width: 6),
                          _chip('by ${m.bookedByRole}', AppColors.primary),
                        ],
                      ],
                    ),
                  ))
              .toList(),
        ),
      ),
    );
  }

  Widget _chip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 10, color: color, fontWeight: FontWeight.w700)),
    );
  }
}

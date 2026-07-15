import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../services/config_service.dart';
import '../../utils/app_colors.dart';

class TrainerRequestsScreen extends StatefulWidget {
  const TrainerRequestsScreen({super.key});

  @override
  State<TrainerRequestsScreen> createState() => _TrainerRequestsScreenState();
}

class _TrainerRequestsScreenState extends State<TrainerRequestsScreen> {
  bool _historyLoading = true;
  List<_HistoryEntry> _history = [];
  DateTime _historyDate = DateTime(
      DateTime.now().year, DateTime.now().month, DateTime.now().day);

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  String get _historyDateLabel =>
      '${_historyDate.day.toString().padLeft(2, '0')} ${_months[_historyDate.month - 1]} ${_historyDate.year}';

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() => _historyLoading = true);
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final rows =
        await ConfigService.getActivityLog(date: _historyDate, userId: uid);
    if (!mounted) return;
    setState(() {
      _history = _groupHistory(rows);
      _historyLoading = false;
    });
  }

  void _prevHistoryDay() {
    setState(() => _historyDate = _historyDate.subtract(const Duration(days: 1)));
    _loadHistory();
  }

  void _nextHistoryDay() {
    setState(() => _historyDate = _historyDate.add(const Duration(days: 1)));
    _loadHistory();
  }

  /// Groups raw ActivityLog rows by bookingId (holds the original request
  /// id for request-type events) so a "Requested" + "Approved" pair for the
  /// same request collapses into one card showing its latest status.
  List<_HistoryEntry> _groupHistory(List<Map<String, String>> rows) {
    final groups = <String, List<Map<String, String>>>{};
    for (final r in rows) {
      final key = (r['bookingId']?.isNotEmpty == true)
          ? r['bookingId']!
          : '${r['eventType']}_${r['timestamp']}';
      groups.putIfAbsent(key, () => []).add(r);
    }

    final entries = groups.values.map((group) {
      group.sort((a, b) => (a['timestamp'] ?? '').compareTo(b['timestamp'] ?? ''));
      final latest = group.last;
      return _HistoryEntry(
        eventType: latest['eventType'] ?? '',
        className: latest['className'] ?? '',
        sessionDate: latest['sessionDate'] ?? '',
        note: latest['note'] ?? '',
        timestamp: latest['timestamp'] ?? '',
      );
    }).toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return entries;
  }

  Color _statusColor(String eventType) {
    final e = eventType.toLowerCase();
    if (e.contains('approved') || e.contains('reassigned')) {
      return const Color(0xFF00D4AA);
    }
    if (e.contains('rejected')) return AppColors.error;
    return const Color(0xFFFFAB40);
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _loadHistory,
        child: ListView(
          padding: const EdgeInsets.all(14),
          children: [
            StreamBuilder<QuerySnapshot>(
              // No orderBy with where — composite index required; sort in Dart instead.
              // Only ever contains PENDING requests — resolved ones are archived
              // to the Sheet and removed from Firestore.
              stream: FirebaseFirestore.instance
                  .collection('adminRequests')
                  .where('requestedBy', isEqualTo: uid)
                  .snapshots(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting &&
                    !snap.hasData) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                        child: CircularProgressIndicator(
                            color: AppColors.primary)),
                  );
                }
                final raw = snap.data?.docs ?? [];
                final docs = List.of(raw)
                  ..sort((a, b) {
                    final ta = (a['createdAt'] as Timestamp?)
                            ?.millisecondsSinceEpoch ??
                        0;
                    final tb = (b['createdAt'] as Timestamp?)
                            ?.millisecondsSinceEpoch ??
                        0;
                    return tb.compareTo(ta);
                  });

                if (docs.isEmpty) return const SizedBox.shrink();

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _SectionHeader('Pending'),
                    const SizedBox(height: 8),
                    ...docs.map((d) => _PendingCard(
                        data: d.data() as Map<String, dynamic>)),
                    const SizedBox(height: 22),
                  ],
                );
              },
            ),
            const _SectionHeader('History'),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: _historyLoading ? null : _prevHistoryDay,
                ),
                Text(_historyDateLabel,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary)),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: _historyLoading ? null : _nextHistoryDay,
                ),
              ],
            ),
            const SizedBox(height: 4),
            if (_historyLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(
                    child:
                        CircularProgressIndicator(color: AppColors.primary)),
              )
            else if (_history.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Column(
                    children: [
                      Icon(Icons.inbox_outlined,
                          size: 56, color: AppColors.textMuted),
                      SizedBox(height: 14),
                      Text('No requests for this day',
                          style: TextStyle(
                              color: AppColors.textSecondary, fontSize: 15)),
                      SizedBox(height: 6),
                      Text(
                        'Resolved slot increase, credit, and\ncancellation requests will show up here.',
                        style:
                            TextStyle(color: AppColors.textMuted, fontSize: 13),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              )
            else
              ..._history.map((h) => _HistoryCard(
                  entry: h, statusColor: _statusColor(h.eventType))),
          ],
        ),
      ),
    );
  }
}

class _HistoryEntry {
  final String eventType;
  final String className;
  final String sessionDate;
  final String note;
  final String timestamp;

  _HistoryEntry({
    required this.eventType,
    required this.className,
    required this.sessionDate,
    required this.note,
    required this.timestamp,
  });
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

class _PendingCard extends StatelessWidget {
  final Map<String, dynamic> data;
  const _PendingCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final type = data['type'] as String? ?? '';
    final IconData typeIcon;
    final String title;
    final String subtitle;
    switch (type) {
      case 'session_cancel':
        typeIcon = Icons.cancel_outlined;
        title = 'Cancel Session — ${data['className'] ?? ''}';
        final sessionDate = data['sessionDate'] as String? ?? '';
        subtitle =
            sessionDate.isNotEmpty ? 'Session date: $sessionDate' : 'Pending admin review';
      case 'credit_request':
        typeIcon = Icons.toll_outlined;
        title = 'Credit Request — ${data['targetUserName'] ?? ''}';
        subtitle = '+${data['amount']} credits';
      default:
        typeIcon = Icons.add_box_outlined;
        title = 'Slot Increase — ${data['className'] ?? ''}';
        subtitle = '+${data['amount']} slots';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFFFFAB40).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(typeIcon, color: const Color(0xFFFFAB40), size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                        fontSize: 14)),
                const SizedBox(height: 3),
                Text(subtitle,
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSecondary)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFFFAB40).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text('PENDING',
                style: TextStyle(
                    fontSize: 10,
                    color: Color(0xFFFFAB40),
                    fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  final _HistoryEntry entry;
  final Color statusColor;
  const _HistoryCard({required this.entry, required this.statusColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.history, color: statusColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.className.isNotEmpty
                      ? entry.className
                      : entry.eventType,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                      fontSize: 14),
                ),
                const SizedBox(height: 3),
                Text(
                  entry.sessionDate.isNotEmpty
                      ? '${entry.sessionDate}${entry.note.isNotEmpty ? ' · ${entry.note}' : ''}'
                      : entry.note,
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(entry.eventType.toUpperCase(),
                style: TextStyle(
                    fontSize: 10,
                    color: statusColor,
                    fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

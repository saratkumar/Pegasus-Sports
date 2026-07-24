import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../models/waiting_list_model.dart';
import '../../services/config_service.dart';
import '../../services/user_service.dart';
import '../../services/waiting_list_service.dart';
import '../../utils/app_colors.dart';
import '../../utils/app_toast.dart';
import '../../utils/time_utils.dart';
import '../../widgets/timeline_range_selector.dart';

class BookingsScreen extends StatefulWidget {
  const BookingsScreen({super.key});

  @override
  State<BookingsScreen> createState() => _BookingsScreenState();
}

class _BookingsScreenState extends State<BookingsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("My Bookings"),
        bottom: TabBar(
          controller: _tab,
          indicatorColor: AppColors.primary,
          labelColor: AppColors.textPrimary,
          unselectedLabelColor: AppColors.textMuted,
          tabs: const [
            Tab(text: 'Bookings'),
            Tab(text: 'Waiting List'),
            Tab(text: 'History'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          _BookingsTab(),
          _WaitingListTab(),
          const _HistoryTab(),
        ],
      ),
    );
  }
}

// ── Bookings tab ─────────────────────────────────────────────────────────────

class _BookingsTab extends StatelessWidget {
  Future<void> _cancel(BuildContext context, String id,
      Map<String, dynamic> data) async {
    final bd = data['bookingDate'];
    if (bd != null) {
      final sessionStart = combineDateAndTime(
          (bd as Timestamp).toDate(), data['bookingTime']?.toString() ?? '');
      if (sessionStart != null &&
          sessionStart.difference(DateTime.now()).inHours < 24) {
        AppToast.error(context,
            'Cancellations must be made at least 24 hours before the class');
        return;
      }
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18),
            side: const BorderSide(color: AppColors.divider)),
        title: const Text('Cancel Booking?',
            style: TextStyle(
                color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
        content: const Text('Credits used will be refunded to your account.',
            style: TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep it',
                style: TextStyle(color: AppColors.primary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                foregroundColor: Colors.white),
            child: const Text('Cancel Booking'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    final uid = FirebaseAuth.instance.currentUser!.uid;
    final creditsUsed = (data['creditsUsed'] as int?) ?? 1;

    await FirebaseFirestore.instance.collection('bookings').doc(id).delete();

    // Refund credit
    if (creditsUsed > 0) {
      await UserService.addCredits(uid, creditsUsed);
    }

    // Try to admit next person from waiting list
    final classId = data['classId']?.toString() ?? '';
    final bt = data['bookingTime']?.toString() ?? '';
    final dn = data['displayName']?.toString() ?? '';
    if (classId.isNotEmpty && bd != null) {
      final bookingDate = (bd as Timestamp).toDate();
      unawaited(ConfigService.logActivityEvent(
        eventType: 'Cancelled by Client',
        classId: classId,
        className: dn,
        sessionDate: bookingDate,
        sessionTime: bt,
        userId: uid,
        userName: FirebaseAuth.instance.currentUser?.displayName ?? uid,
        bookedByRole: data['bookedByRole']?.toString() ?? 'client',
        creditsUsed: creditsUsed,
        bookingId: id,
      ));
      await WaitingListService.admitNextFromWaitingList(
        classId: classId,
        bookingDate: bookingDate,
        bookingTime: bt,
        className: dn,
      );
    }

    if (context.mounted) AppToast.info(context, "Booking cancelled · credit refunded");
  }

  String _formatDate(dynamic value) {
    if (value == null) return '-';
    try {
      final dt = (value as Timestamp).toDate();
      const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
      return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
    } catch (_) {
      return '-';
    }
  }

  bool _isUpcoming(Map<String, dynamic> data) {
    final bd = data['bookingDate'];
    if (bd != null) {
      final dt = (bd as Timestamp).toDate();
      final today = DateTime(
          DateTime.now().year, DateTime.now().month, DateTime.now().day);
      return !dt.isBefore(today);
    }
    const days = {'Monday': 1, 'Tuesday': 2, 'Wednesday': 3, 'Thursday': 4,
        'Friday': 5, 'Saturday': 6, 'Sunday': 7};
    return (days[data['bookingDay']?.toString() ?? ''] ?? 0) >=
        DateTime.now().weekday;
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('bookings')
          .where('userId', isEqualTo: uid)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
              child: CircularProgressIndicator(color: AppColors.primary));
        }
        final docs = snapshot.data?.docs ?? [];
        // Exclude cancelled bookings
        final active = docs
            .where((d) =>
                (d.data() as Map<String, dynamic>)['status'] !=
                'cancelled_by_trainer')
            .toList();

        if (active.isEmpty) return _empty();

        final upcoming = active
            .where((d) => _isUpcoming(d.data() as Map<String, dynamic>))
            .toList();
        final past = active
            .where((d) => !_isUpcoming(d.data() as Map<String, dynamic>))
            .toList();

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (upcoming.isNotEmpty) ...[
              _header('Upcoming', upcoming.length),
              const SizedBox(height: 10),
              ...upcoming.map((d) => _card(context, d, true)),
              const SizedBox(height: 8),
            ],
            if (past.isNotEmpty) ...[
              _header('Past', past.length),
              const SizedBox(height: 10),
              ...past.map((d) => _card(context, d, false)),
            ],
          ],
        );
      },
    );
  }

  Widget _empty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.card,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.divider),
            ),
            child: const Icon(Icons.event_note,
                size: 48, color: AppColors.textMuted),
          ),
          const SizedBox(height: 20),
          const Text("No bookings yet",
              style: TextStyle(
                  fontSize: 18,
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          const Text("Browse classes and book your first session",
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
        ],
      ),
    );
  }

  Widget _card(BuildContext context, QueryDocumentSnapshot doc, bool upcoming) {
    final data = doc.data() as Map<String, dynamic>;
    final raw = data['classId']?.toString() ?? data['className']?.toString() ?? '';
    final name = data['displayName']?.toString() ??
        (raw.split('_').length >= 2 ? raw.split('_')[1] : raw);
    final time = data['bookingTime']?.toString() ?? '-';
    final type = data['bookingType']?.toString() ?? '-';
    final dateStr = _formatDate(data['bookingDate']) != '-'
        ? _formatDate(data['bookingDate'])
        : data['bookingDay']?.toString() ?? '-';
    final bookedByRole = data['bookedByRole']?.toString();
    final credits = data['creditsUsed'] as int? ?? 1;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: upcoming
                ? AppColors.primary.withValues(alpha: 0.3)
                : AppColors.divider),
      ),
      child: IntrinsicHeight(
        child: Row(
          children: [
            Container(
              width: 4,
              decoration: BoxDecoration(
                color: upcoming ? AppColors.primary : AppColors.textMuted,
                borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(16),
                    bottomLeft: Radius.circular(16)),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(name,
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: upcoming
                                      ? AppColors.textPrimary
                                      : AppColors.textSecondary)),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 3),
                          decoration: BoxDecoration(
                            color: upcoming
                                ? AppColors.primary.withValues(alpha: 0.15)
                                : AppColors.divider,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(upcoming ? 'Upcoming' : 'Past',
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: upcoming
                                      ? AppColors.primary
                                      : AppColors.textMuted)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 12,
                      runSpacing: 6,
                      children: [
                        _chip(Icons.calendar_today_outlined, dateStr),
                        _chip(Icons.schedule, time),
                        _chip(Icons.label_outline, type),
                        _chip(Icons.toll_rounded, '$credits credit${credits != 1 ? 's' : ''}'),
                        if (bookedByRole != null && bookedByRole != 'client')
                          _chip(Icons.person_outlined,
                              'Booked by $bookedByRole'),
                      ],
                    ),
                    if (upcoming) ...[
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: () => _cancel(context, doc.id, data),
                        icon: const Icon(Icons.cancel_outlined, size: 16),
                        label: const Text('Cancel Booking'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.error,
                          side: BorderSide(
                              color: AppColors.error.withValues(alpha: 0.5)),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                          textStyle: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(IconData icon, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: AppColors.textMuted),
        const SizedBox(width: 4),
        Text(label,
            style: const TextStyle(
                fontSize: 12, color: AppColors.textSecondary)),
      ],
    );
  }

  Widget _header(String title, int count) {
    return Row(
      children: [
        Text(title,
            style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary)),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text('$count',
              style: const TextStyle(
                  color: AppColors.primary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700)),
        ),
      ],
    );
  }
}

// ── Waiting list tab ─────────────────────────────────────────────────────────

class _WaitingListTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    return StreamBuilder<List<WaitingListModel>>(
      stream: WaitingListService.userWaitingListStream(uid),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(
              child: CircularProgressIndicator(color: AppColors.primary));
        }
        final entries = snap.data ?? [];
        if (entries.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.divider),
                  ),
                  child: const Icon(Icons.hourglass_empty,
                      size: 48, color: AppColors.textMuted),
                ),
                const SizedBox(height: 20),
                const Text("Not on any waiting lists",
                    style: TextStyle(
                        fontSize: 18,
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                const Text(
                    "Join a full class to be added to the waiting list",
                    style: TextStyle(
                        fontSize: 13, color: AppColors.textSecondary)),
              ],
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: entries.length,
          itemBuilder: (context, i) =>
              _WaitingCard(entry: entries[i]),
        );
      },
    );
  }
}

class _WaitingCard extends StatelessWidget {
  final WaitingListModel entry;
  const _WaitingCard({required this.entry});

  String _fmt(DateTime d) {
    const m = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${d.day} ${m[d.month - 1]} ${d.year}';
  }

  Future<void> _leave(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Leave Waiting List?',
            style: TextStyle(
                color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
        content: const Text(
            'Your held credit will be refunded immediately.',
            style: TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Stay',
                style: TextStyle(color: AppColors.primary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                foregroundColor: Colors.white),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    final uid = FirebaseAuth.instance.currentUser!.uid;
    await WaitingListService.leaveWaitingList(entry.id!, uid);

    if (context.mounted) {
      AppToast.info(context, "Removed from waiting list · credit refunded");
    }
  }

  @override
  Widget build(BuildContext context) {
    final daysUntil =
        entry.bookingDate.difference(DateTime.now()).inDays;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: const Color(0xFFFFAB40).withValues(alpha: 0.4)),
      ),
      child: IntrinsicHeight(
        child: Row(
          children: [
            Container(
              width: 4,
              decoration: const BoxDecoration(
                color: Color(0xFFFFAB40),
                borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(16),
                    bottomLeft: Radius.circular(16)),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(entry.className,
                              style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textPrimary)),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFAB40)
                                .withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text('Waiting',
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFFFFAB40))),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 12,
                      runSpacing: 6,
                      children: [
                        _chip(Icons.calendar_today_outlined,
                            _fmt(entry.bookingDate)),
                        _chip(Icons.schedule, entry.bookingTime),
                        _chip(Icons.hourglass_bottom_rounded,
                            daysUntil >= 0
                                ? 'In $daysUntil day${daysUntil != 1 ? 's' : ''}'
                                : 'Past'),
                        _chip(Icons.toll_rounded, '1 credit held'),
                      ],
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () => _leave(context),
                      icon: const Icon(Icons.exit_to_app, size: 16),
                      label: const Text('Leave Waiting List'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.error,
                        side: BorderSide(
                            color: AppColors.error.withValues(alpha: 0.5)),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        textStyle: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(IconData icon, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: AppColors.textMuted),
        const SizedBox(width: 4),
        Text(label,
            style: const TextStyle(
                fontSize: 12, color: AppColors.textSecondary)),
      ],
    );
  }
}

// ── History tab (from the Activity Log Sheet) ──────────────────────────────

/// The `bookings` collection is a live/working set only — old bookings are
/// periodically purged (see CleanupService) — so it can't be relied on for
/// history. This tab reads the durable Activity Log Sheet mirror instead,
/// scoped to the signed-in client's own events (server-side enforced in
/// functions/index.js's callAppsScript), bounded to a 1/2/3-month window.
class _HistoryTab extends StatefulWidget {
  const _HistoryTab();

  @override
  State<_HistoryTab> createState() => _HistoryTabState();
}

class _HistoryTabState extends State<_HistoryTab> {
  DateTimeRange? _range;
  late Future<List<Map<String, String>>> _rowsFuture;

  @override
  void initState() {
    super.initState();
    _rowsFuture = _load();
  }

  Future<List<Map<String, String>>> _load() {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    return ConfigService.getActivityLog(userId: uid);
  }

  void _reload() {
    setState(() => _rowsFuture = _load());
  }

  ({IconData icon, Color color}) _styleFor(String eventType) {
    final e = eventType.toLowerCase();
    if (e.contains('cancelled') || e.contains('rejected')) {
      return (icon: Icons.cancel_outlined, color: AppColors.error);
    }
    if (e.contains('waitlist') || e.contains('requested') || e.contains('submitted')) {
      return (icon: Icons.hourglass_top, color: const Color(0xFFFFAB40));
    }
    if (e.contains('approved') || e.contains('admitted') || e.contains('booked')) {
      return (icon: Icons.check_circle_outline, color: const Color(0xFF00D4AA));
    }
    return (icon: Icons.circle_outlined, color: AppColors.textMuted);
  }

  String _fmt(String? iso) {
    final dt = DateTime.tryParse(iso ?? '')?.toLocal();
    if (dt == null) return '';
    return formatWithWeekday(dt);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
          child: Row(
            children: [
              Expanded(
                child: DateRangeFilterBar(
                  value: _range,
                  onChanged: (r) => setState(() => _range = r),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh,
                    size: 18, color: AppColors.textMuted),
                tooltip: 'Reload',
                onPressed: _reload,
              ),
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder<List<Map<String, String>>>(
            future: _rowsFuture,
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting &&
                  !snap.hasData) {
                return const Center(
                    child: CircularProgressIndicator(color: AppColors.primary));
              }
              final rows = (snap.data ?? [])
                  .where((r) =>
                      isWithinRange(r['timestamp'], _range ?? defaultDateRange()))
                  .toList()
                ..sort((a, b) =>
                    (b['timestamp'] ?? '').compareTo(a['timestamp'] ?? ''));

              if (rows.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: AppColors.card,
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.divider),
                        ),
                        child: const Icon(Icons.history,
                            size: 48, color: AppColors.textMuted),
                      ),
                      const SizedBox(height: 20),
                      const Text("No history in this window",
                          style: TextStyle(
                              fontSize: 18,
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      const Text("Try a longer timeline above",
                          style: TextStyle(
                              fontSize: 13, color: AppColors.textSecondary)),
                    ],
                  ),
                );
              }

              return ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: rows.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, i) {
                  final row = rows[i];
                  final eventType = row['eventType'] ?? '';
                  final style = _styleFor(eventType);
                  final className = row['className'] ?? '';
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
                                  Text(_fmt(row['timestamp']),
                                      style: const TextStyle(
                                          fontSize: 11,
                                          color: AppColors.textMuted)),
                                ],
                              ),
                              if (className.isNotEmpty) ...[
                                const SizedBox(height: 3),
                                Text(className,
                                    style: const TextStyle(
                                        fontSize: 13,
                                        color: AppColors.textPrimary)),
                              ],
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
              );
            },
          ),
        ),
      ],
    );
  }
}

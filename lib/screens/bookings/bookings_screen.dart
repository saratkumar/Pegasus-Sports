import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../models/waiting_list_model.dart';
import '../../services/user_service.dart';
import '../../services/waiting_list_service.dart';
import '../../utils/app_colors.dart';
import '../../utils/app_toast.dart';

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
    _tab = TabController(length: 2, vsync: this);
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
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          _BookingsTab(),
          _WaitingListTab(),
        ],
      ),
    );
  }
}

// ── Bookings tab ─────────────────────────────────────────────────────────────

class _BookingsTab extends StatelessWidget {
  Future<void> _cancel(BuildContext context, String id,
      Map<String, dynamic> data) async {
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
    final bd = data['bookingDate'];
    final bt = data['bookingTime']?.toString() ?? '';
    final dn = data['displayName']?.toString() ?? '';
    if (classId.isNotEmpty && bd != null) {
      final bookingDate = (bd as Timestamp).toDate();
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

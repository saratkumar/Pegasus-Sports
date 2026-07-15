import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../models/class_model.dart';
import '../../models/user_model.dart';
import '../../services/class_service.dart';
import '../../services/user_service.dart';
import '../../utils/app_colors.dart';

class TrainerHistoryScreen extends StatefulWidget {
  const TrainerHistoryScreen({super.key});

  @override
  State<TrainerHistoryScreen> createState() => _TrainerHistoryScreenState();
}

class _TrainerHistoryScreenState extends State<TrainerHistoryScreen> {
  String _trainerName = '';
  List<_Session> _sessions = [];
  bool _loading = true;

  static const _dayNames = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday',
  ];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final results = await Future.wait([
        UserService.getCurrentUser(),
        ClassService.getClasses(),
      ]);
      if (!mounted) return;

      final trainer = results[0] as UserModel?;
      final allClasses = results[1] as List<ClassModel>;
      final name = trainer?.name ?? '';

      // Build sessions: every date in the past 60 days where this trainer had a class
      final today = DateTime.now();
      final past = <_Session>[];
      for (int i = 1; i <= 60; i++) {
        final date = DateTime(today.year, today.month, today.day)
            .subtract(Duration(days: i));
        for (final cls in allClasses) {
          if (cls.coach.trim().toLowerCase() != name.trim().toLowerCase()) continue;
          if (_matchesDate(cls, date)) {
            // A once-off class deactivated by admin cancel = cancelled session
            final isCancelled = cls.isCancelledOn(date) ||
                (cls.occurrence == 'once' && !cls.isActive);
            past.add(_Session(cls: cls, date: date, isCancelled: isCancelled));
          }
        }
      }

      if (!mounted) return;
      setState(() {
        _trainerName = name;
        _sessions = past;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  static bool _matchesDate(ClassModel cls, DateTime date) {
    final dayName = _dayNames[date.weekday - 1];
    switch (cls.occurrence) {
      case 'daily':
        return true;
      case 'weekly':
        return cls.day.split(',').map((d) => d.trim()).contains(dayName);
      case 'once':
        final parts = cls.specificDate?.split('-');
        if (parts?.length != 3) return false;
        try {
          final d = DateTime(
              int.parse(parts![0]), int.parse(parts[1]), int.parse(parts[2]));
          return d.year == date.year && d.month == date.month && d.day == date.day;
        } catch (_) {
          return false;
        }
      case 'monthly':
        if (cls.day != dayName || cls.specificDate == null) return false;
        final parts = cls.specificDate!.split('-');
        if (parts.length != 3) return false;
        try {
          final ref = DateTime(
              int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
          return ((ref.day - 1) ~/ 7) == ((date.day - 1) ~/ 7);
        } catch (_) {
          return false;
        }
      default:
        return cls.day == dayName;
    }
  }

  String _fmt(DateTime d) {
    const m = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    final today = DateTime.now();
    final yesterday = today.subtract(const Duration(days: 1));
    if (d.year == yesterday.year && d.month == yesterday.month && d.day == yesterday.day) {
      return 'Yesterday';
    }
    return '${_dayNames[d.weekday - 1]}, ${d.day} ${m[d.month - 1]}';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
          body: Center(child: CircularProgressIndicator(color: AppColors.primary)));
    }

    if (_sessions.isEmpty) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.history, size: 56, color: AppColors.textMuted),
              const SizedBox(height: 14),
              Text(
                _trainerName.isEmpty
                    ? 'Profile name not set'
                    : 'No sessions in the past 60 days',
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 15),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: _loadData,
        child: ListView.builder(
          padding: const EdgeInsets.all(14),
          itemCount: _sessions.length,
          itemBuilder: (_, i) => _SessionCard(
            session: _sessions[i],
            fmt: _fmt,
          ),
        ),
      ),
    );
  }
}

class _Session {
  final ClassModel cls;
  final DateTime date;
  final bool isCancelled;
  const _Session({required this.cls, required this.date, this.isCancelled = false});
}

// ── Session card ──────────────────────────────────────────────────────────────

class _SessionCard extends StatelessWidget {
  final _Session session;
  final String Function(DateTime) fmt;
  const _SessionCard({required this.session, required this.fmt});

  @override
  Widget build(BuildContext context) {
    final cls = session.cls;
    final cancelled = session.isCancelled;
    final chipColor = cancelled ? AppColors.error : AppColors.primary;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: cancelled
              ? AppColors.error.withValues(alpha: 0.35)
              : AppColors.divider,
        ),
      ),
      child: Row(
        children: [
          // Date chip
          Container(
            width: 52,
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: chipColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              children: [
                Text(
                  session.date.day.toString(),
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: chipColor),
                ),
                Text(
                  ['Jan','Feb','Mar','Apr','May','Jun',
                   'Jul','Aug','Sep','Oct','Nov','Dec'][session.date.month - 1],
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: chipColor),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(cls.mode,
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: cancelled
                                  ? AppColors.textMuted
                                  : AppColors.textPrimary,
                              decoration: cancelled
                                  ? TextDecoration.lineThrough
                                  : null)),
                    ),
                    if (cancelled)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.error.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text('CANCELLED',
                            style: TextStyle(
                                fontSize: 9,
                                color: AppColors.error,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.5)),
                      ),
                  ],
                ),
                const SizedBox(height: 3),
                Text('${cls.startTime} · ${cls.duration} · ${cls.location}',
                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                const SizedBox(height: 3),
                Text(fmt(session.date),
                    style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
              ],
            ),
          ),
          // Enrollment badge — skip query for cancelled sessions
          if (cancelled)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Column(
                children: [
                  Icon(Icons.cancel_outlined,
                      size: 18, color: AppColors.error),
                  SizedBox(height: 2),
                  Text('cancelled',
                      style: TextStyle(fontSize: 9, color: AppColors.error)),
                ],
              ),
            )
          else
            FutureBuilder<QuerySnapshot>(
              future: FirebaseFirestore.instance
                  .collection('bookings')
                  .where('classId', isEqualTo: cls.effectiveId)
                  .get(),
              builder: (_, snap) {
                final start = DateTime(
                    session.date.year, session.date.month, session.date.day);
                final end = start.add(const Duration(days: 1));
                final count = snap.data?.docs.where((d) {
                      final data = d.data() as Map<String, dynamic>;
                      if (data['status'] == 'cancelled_by_trainer') return false;
                      final bd = data['bookingDate'];
                      if (bd == null) return false;
                      final dt = (bd as Timestamp).toDate();
                      return !dt.isBefore(start) && dt.isBefore(end);
                    }).length ??
                    0;
                return Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: count > 0
                        ? const Color(0xFF00D4AA).withValues(alpha: 0.12)
                        : AppColors.surface,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    children: [
                      Text(
                        '$count',
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: count > 0
                                ? const Color(0xFF00D4AA)
                                : AppColors.textMuted),
                      ),
                      Text(
                        'attended',
                        style: TextStyle(
                            fontSize: 9,
                            color: count > 0
                                ? const Color(0xFF00D4AA)
                                : AppColors.textMuted),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

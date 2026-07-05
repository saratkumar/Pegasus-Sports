import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../models/class_model.dart';
import '../../services/class_service.dart';
import '../../services/user_service.dart';
import '../../services/waiting_list_service.dart';
import '../../services/email_service.dart';
import '../../services/notifications.dart';
import '../../utils/app_colors.dart';
import '../../utils/app_toast.dart';

class ClassesScreen extends StatefulWidget {
  const ClassesScreen({super.key});

  @override
  State<ClassesScreen> createState() => _ClassesScreenState();
}

class _ClassesScreenState extends State<ClassesScreen> {
  DateTime _selectedDate = DateTime.now();

  static const _dayNames = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday',
    'Friday', 'Saturday', 'Sunday',
  ];

  String get _selectedDayName => _dayNames[_selectedDate.weekday - 1];

  String _formatDate(DateTime d) {
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    const days = ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];
    return '${days[d.weekday - 1]}, ${d.day} ${months[d.month - 1]} ${d.year}';
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 60)),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(
            primary: AppColors.primary,
            surface: AppColors.bg,
            onSurface: AppColors.textPrimary,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _selectedDate = picked);
  }

  Future<void> _book(BuildContext context, ClassModel cls) async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final classId = cls.effectiveId;

    // Duplicate check
    final existing = await FirebaseFirestore.instance
        .collection('bookings')
        .where('userId', isEqualTo: uid)
        .where('classId', isEqualTo: classId)
        .get();

    final alreadyBookedToday = existing.docs.any((d) {
      final bd = d['bookingDate'];
      if (bd == null) return false;
      final dt = (bd as Timestamp).toDate();
      return dt.year == _selectedDate.year &&
          dt.month == _selectedDate.month &&
          dt.day == _selectedDate.day;
    });

    if (alreadyBookedToday) {
      if (context.mounted) {
        AppToast.warning(context, "Already registered for ${cls.mode}");
      }
      return;
    }

    // Check credits
    final hasCredits = await UserService.hasEnoughCredits(uid);
    if (!hasCredits) {
      if (context.mounted) {
        AppToast.error(context, "No credits — purchase a membership plan first");
      }
      return;
    }

    // Check capacity
    final booked = await ClassService.getBookingCount(classId, _selectedDate);
    final capacity = int.tryParse(cls.groupSize) ?? 0;
    final isFull = capacity > 0 && booked >= capacity;

    if (isFull) {
      if (context.mounted) {
        AppToast.error(context, "Class is full");
      }
      return;
    }

    // Create booking
    await FirebaseFirestore.instance.collection('bookings').add({
      'userId': uid,
      'classId': classId,
      'displayName': cls.mode,
      'bookingType': 'class',
      'bookingDay': _selectedDayName,
      'bookingDate': Timestamp.fromDate(_selectedDate),
      'bookingTime': cls.startTime,
      'createdAt': Timestamp.now(),
      'bookedBy': uid,
      'bookedByRole': 'client',
      'creditsUsed': 1,
    });

    await UserService.deductCredit(uid);

    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get();
    final email =
        FirebaseAuth.instance.currentUser?.email?.isNotEmpty == true
            ? FirebaseAuth.instance.currentUser!.email!
            : (userDoc.data()?['email']?.toString() ?? '');

    if (email.isNotEmpty) {
      await EmailService.sendBookingEmail(
        email: email,
        className: cls.mode,
        classTime: cls.startTime,
      );
    }

    await NotificationService.showBookingConfirmed(cls.mode);
    await NotificationService.scheduleClassNotifications(
        cls.mode, _selectedDate, cls.startTime);

    if (context.mounted) {
      AppToast.success(
          context, '${cls.mode} booked for ${_formatDate(_selectedDate)}');
    }
  }

  Future<void> _joinWaitingList(BuildContext context, ClassModel cls) async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final classId = cls.effectiveId;

    // Check if already on waiting list
    final alreadyWaiting = await WaitingListService.isOnWaitingList(
        classId, uid, _selectedDate);
    if (alreadyWaiting) {
      if (context.mounted) {
        AppToast.warning(context, "Already on the waiting list for ${cls.mode}");
      }
      return;
    }

    // 6-hour cutoff check
    final sessionStart = _parseSessionStart(cls.startTime, _selectedDate);
    if (sessionStart != null &&
        DateTime.now()
            .isAfter(sessionStart.subtract(const Duration(hours: 6)))) {
      if (context.mounted) {
        AppToast.error(context,
            "Waiting list closed — less than 6 hours before session");
      }
      return;
    }

    // Check credits
    final hasCredits = await UserService.hasEnoughCredits(uid);
    if (!hasCredits) {
      if (context.mounted) {
        AppToast.error(context,
            "No credits — 1 credit is held when joining the waiting list");
      }
      return;
    }

    if (!context.mounted) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Join Waiting List?',
            style: TextStyle(
                color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
        content: const Text(
          '1 credit will be held. If you get a spot, you\'re in. If not, your credit is refunded automatically.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel',
                style: TextStyle(color: AppColors.textMuted)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Join Waiting List'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get();
    final userName =
        userDoc.data()?['name']?.toString() ?? 'Unknown';

    await WaitingListService.joinWaitingList(
      classId: classId,
      userId: uid,
      userName: userName,
      bookingDate: _selectedDate,
      bookingTime: cls.startTime,
      className: cls.mode,
    );

    if (context.mounted) {
      AppToast.success(context,
          "Added to waiting list for ${cls.mode}. 1 credit held.");
    }
  }

  DateTime? _parseSessionStart(String timeStr, DateTime date) {
    try {
      final cleaned = timeStr.toUpperCase().replaceAll(' ', '');
      final isPM = cleaned.contains('PM');
      final isAM = cleaned.contains('AM');
      final digits = cleaned.replaceAll('AM', '').replaceAll('PM', '');
      final parts = digits.split(':');
      int hour = int.parse(parts[0]);
      final minute = parts.length > 1 ? int.parse(parts[1]) : 0;
      if (isPM && hour != 12) hour += 12;
      if (isAM && hour == 12) hour = 0;
      return DateTime(date.year, date.month, date.day, hour, minute);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Classes")),
      body: Column(
        children: [
          _DateBar(label: _formatDate(_selectedDate), onTap: _pickDate),
          Expanded(
            child: StreamBuilder<List<ClassModel>>(
              stream: ClassService.streamClasses(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                      child: CircularProgressIndicator(color: AppColors.primary));
                }
                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return _emptyState("No classes available");
                }

                final classes = snapshot.data!
                    .where((c) => c.day == _selectedDayName)
                    .toList();

                if (classes.isEmpty) {
                  return _emptyState("No classes on $_selectedDayName");
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(14),
                  itemCount: classes.length,
                  itemBuilder: (context, index) {
                    final cls = classes[index];
                    return _ClassCard(
                      item: cls,
                      selectedDate: _selectedDate,
                      onBook: (ctx) => _book(ctx, cls),
                      onJoinWaitingList: (ctx) =>
                          _joinWaitingList(ctx, cls),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState(String msg) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.event_busy, size: 56, color: AppColors.textMuted),
          const SizedBox(height: 14),
          Text(msg,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 15)),
        ],
      ),
    );
  }
}

// ── Date bar ─────────────────────────────────────────────────────────────────

class _DateBar extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _DateBar({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.bg,
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(12),
            border:
                Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
          ),
          child: Row(
            children: [
              const Icon(Icons.calendar_today,
                  color: AppColors.primary, size: 18),
              const SizedBox(width: 12),
              Text(label,
                  style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w600)),
              const Spacer(),
              const Icon(Icons.keyboard_arrow_down,
                  color: AppColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Class card ────────────────────────────────────────────────────────────────

class _ClassCard extends StatelessWidget {
  final ClassModel item;
  final DateTime selectedDate;
  final Future<void> Function(BuildContext) onBook;
  final Future<void> Function(BuildContext) onJoinWaitingList;

  const _ClassCard({
    required this.item,
    required this.selectedDate,
    required this.onBook,
    required this.onJoinWaitingList,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.divider),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 190,
            width: double.infinity,
            child: item.image.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: item.image,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => _imgPlaceholder(),
                    errorWidget: (_, __, ___) => _imgPlaceholder(),
                  )
                : _imgPlaceholder(),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(item.mode,
                          style: const TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary)),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color:
                                AppColors.primary.withValues(alpha: 0.4)),
                      ),
                      child: Text(item.type,
                          style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.primary,
                              fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _row(Icons.person_outline, item.coach),
                const SizedBox(height: 5),
                _row(Icons.location_on_outlined,
                    '${item.location} · ${item.detailLocation}'),
                const SizedBox(height: 5),
                _row(Icons.schedule,
                    '${item.startTime} · ${item.duration}'),
                const SizedBox(height: 14),
                _CapacitySection(
                  classId: item.effectiveId,
                  groupSize: item.groupSize,
                  selectedDate: selectedDate,
                  onBook: onBook,
                  onJoinWaitingList: onJoinWaitingList,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _imgPlaceholder() {
    return Container(
      color: AppColors.surface,
      child: Center(
        child: Icon(Icons.fitness_center,
            size: 42,
            color: AppColors.primary.withValues(alpha: 0.4)),
      ),
    );
  }

  Widget _row(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 15, color: AppColors.textMuted),
        const SizedBox(width: 7),
        Expanded(
          child: Text(text,
              style: const TextStyle(
                  fontSize: 13, color: AppColors.textSecondary)),
        ),
      ],
    );
  }
}

// ── Capacity section — streams booking count live ────────────────────────────

class _CapacitySection extends StatelessWidget {
  final String classId;
  final String groupSize;
  final DateTime selectedDate;
  final Future<void> Function(BuildContext) onBook;
  final Future<void> Function(BuildContext) onJoinWaitingList;

  const _CapacitySection({
    required this.classId,
    required this.groupSize,
    required this.selectedDate,
    required this.onBook,
    required this.onJoinWaitingList,
  });

  @override
  Widget build(BuildContext context) {
    final startOfDay =
        DateTime(selectedDate.year, selectedDate.month, selectedDate.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('bookings')
          .where('classId', isEqualTo: classId)
          .where('bookingDate',
              isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
          .where('bookingDate', isLessThan: Timestamp.fromDate(endOfDay))
          .snapshots(),
      builder: (context, snap) {
        final booked = snap.data?.docs.length ?? 0;
        final capacity = int.tryParse(groupSize) ?? 0;
        final isFull = capacity > 0 && booked >= capacity;
        final pct =
            capacity > 0 ? (booked / capacity).clamp(0.0, 1.0) : 0.0;

        return FutureBuilder<int>(
          future: WaitingListService.getWaitingCount(classId, selectedDate),
          builder: (context, waitSnap) {
            final waiting = waitSnap.data ?? 0;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      isFull
                          ? 'Class full'
                          : '$booked / $capacity spots taken',
                      style: TextStyle(
                        fontSize: 12,
                        color: isFull
                            ? AppColors.error
                            : AppColors.textSecondary,
                      ),
                    ),
                    if (!isFull && snap.hasData)
                      Text(
                        '${capacity - booked} left',
                        style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.primary,
                            fontWeight: FontWeight.w600),
                      ),
                    if (isFull && waiting > 0)
                      Text(
                        '$waiting waiting',
                        style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFFFFAB40),
                            fontWeight: FontWeight.w600),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: pct,
                    backgroundColor: AppColors.divider,
                    color: isFull ? AppColors.error : AppColors.primary,
                    minHeight: 5,
                  ),
                ),
                const SizedBox(height: 14),
                if (!isFull)
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => onBook(context),
                      child: const Text('Book Now'),
                    ),
                  ),
                if (isFull) ...[
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => onJoinWaitingList(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            const Color(0xFFFFAB40).withValues(alpha: 0.15),
                        foregroundColor: const Color(0xFFFFAB40),
                        side: const BorderSide(
                            color: Color(0xFFFFAB40), width: 1),
                        elevation: 0,
                      ),
                      child: const Text('Join Waiting List'),
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Center(
                    child: Text(
                      'Waiting list closes 6 hours before session',
                      style: TextStyle(
                          fontSize: 11, color: AppColors.textMuted),
                    ),
                  ),
                ],
              ],
            );
          },
        );
      },
    );
  }
}

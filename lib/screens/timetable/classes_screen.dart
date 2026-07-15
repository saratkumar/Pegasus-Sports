import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../models/class_model.dart';
import '../../services/class_service.dart';
import '../../services/config_service.dart';
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

  // Returns true if the class should appear on the given date based on occurrence.
  bool _matchesDate(ClassModel cls, DateTime date) {
    final dayName = _dayNames[date.weekday - 1];
    // day field may be comma-separated for weekly: "Monday,Wednesday,Friday"
    final classDays = cls.day.split(',').map((d) => d.trim()).toSet();
    switch (cls.occurrence) {
      case 'daily':
        return true;
      case 'once':
        if (cls.specificDate == null) return false;
        final parts = cls.specificDate!.split('-');
        if (parts.length < 3) return false;
        final d = DateTime(
            int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
        return d.year == date.year &&
            d.month == date.month &&
            d.day == date.day;
      case 'monthly':
        // Matches if same day-of-week AND same week-of-month as specificDate.
        if (cls.specificDate == null) {
          return classDays.contains(dayName) && date.day <= 7;
        }
        final parts = cls.specificDate!.split('-');
        if (parts.length < 3) return false;
        final ref = DateTime(
            int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
        final refWeek = ((ref.day - 1) ~/ 7) + 1;
        final selWeek = ((date.day - 1) ~/ 7) + 1;
        return classDays.contains(dayName) && selWeek == refWeek;
      case 'weekly':
      default:
        return classDays.contains(dayName);
    }
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

    try {
      // Duplicate check — no date range in Firestore to avoid composite index; filter in Dart
      final existingSnap = await FirebaseFirestore.instance
          .collection('bookings')
          .where('userId', isEqualTo: uid)
          .where('classId', isEqualTo: classId)
          .get();

      final alreadyBooked = existingSnap.docs.any((d) {
        final bd = d['bookingDate'];
        if (bd == null) return false;
        final dt = (bd as Timestamp).toDate();
        return dt.year == _selectedDate.year &&
            dt.month == _selectedDate.month &&
            dt.day == _selectedDate.day;
      });

      if (alreadyBooked) {
        if (context.mounted) {
          AppToast.warning(context, "Already registered for ${cls.mode}");
        }
        return;
      }

      // Credit check + capacity check in parallel
      final results = await Future.wait([
        UserService.hasEnoughCredits(uid),
        ClassService.getBookingCount(classId, _selectedDate),
      ]);

      final hasCredits = results[0] as bool;
      final booked = results[1] as int;

      if (!hasCredits) {
        if (context.mounted) {
          AppToast.error(
              context, "No credits — purchase a membership plan first");
        }
        return;
      }

      final capacity = cls.effectiveCapacity(_selectedDate);
      if (capacity > 0 && booked >= capacity) {
        if (context.mounted) {
          AppToast.error(context, "Class is full");
        }
        return;
      }

      // Create booking
      final bookingRef =
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

      unawaited(ConfigService.logActivityEvent(
        eventType: 'Booked',
        classId: classId,
        className: cls.mode,
        sessionDate: _selectedDate,
        sessionTime: cls.startTime,
        userId: uid,
        userName: FirebaseAuth.instance.currentUser?.displayName ?? uid,
        bookedByRole: 'client',
        bookingId: bookingRef.id,
      ));

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
        try {
          await EmailService.sendBookingEmail(
            email: email,
            className: cls.mode,
            classTime: cls.startTime,
          );
        } catch (e) {
          debugPrint('Booking email failed: $e');
          if (context.mounted) {
            AppToast.warning(
                context, 'Booked, but confirmation email failed: $e');
          }
        }
      }

      await NotificationService.showBookingConfirmed(cls.mode);
      await NotificationService.scheduleClassNotifications(
          cls.mode, _selectedDate, cls.startTime);

      if (context.mounted) {
        AppToast.success(
            context, '${cls.mode} booked for ${_formatDate(_selectedDate)}');
      }
    } catch (e, st) {
      debugPrint('Booking error: $e\n$st');
      if (context.mounted) {
        AppToast.error(context, 'Booking failed: ${e.toString()}');
      }
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
          _DateCarousel(
            selectedDate: _selectedDate,
            onSelect: (d) => setState(() => _selectedDate = d),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: StreamBuilder<List<ClassModel>>(
              stream: ClassService.streamClasses(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting &&
                    !snapshot.hasData) {
                  return const Center(
                      child: CircularProgressIndicator(color: AppColors.primary));
                }
                final all = snapshot.data ?? [];
                final classes = all
                    .where((c) =>
                        c.isActive &&
                        _matchesDate(c, _selectedDate) &&
                        !c.isCancelledOn(_selectedDate))
                    .toList();

                if (classes.isEmpty) {
                  return _emptyState(all.isEmpty
                      ? 'No classes available'
                      : 'No classes on $_selectedDayName');
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

// ── Date carousel ────────────────────────────────────────────────────────────

class _DateCarousel extends StatefulWidget {
  final DateTime selectedDate;
  final ValueChanged<DateTime> onSelect;
  const _DateCarousel({required this.selectedDate, required this.onSelect});

  @override
  State<_DateCarousel> createState() => _DateCarouselState();
}

class _DateCarouselState extends State<_DateCarousel> {
  static const _dayCount = 60;
  static const _tileWidth = 60.0;
  static const _abbr = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  final _controller = ScrollController();
  late final DateTime _baseDate;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _baseDate = DateTime(now.year, now.month, now.day);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToSelected());
  }

  @override
  void didUpdateWidget(covariant _DateCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_isSameDay(oldWidget.selectedDate, widget.selectedDate)) {
      _scrollToSelected();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  void _scrollToSelected() {
    if (!_controller.hasClients) return;
    final index = widget.selectedDate.difference(_baseDate).inDays;
    if (index < 0 || index >= _dayCount) return;
    final target = (index * _tileWidth) - 100;
    _controller.animateTo(
      target.clamp(0.0, _controller.position.maxScrollExtent),
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 66,
      child: ListView.builder(
        controller: _controller,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        itemCount: _dayCount,
        itemBuilder: (context, i) {
          final date = _baseDate.add(Duration(days: i));
          final selected = _isSameDay(date, widget.selectedDate);
          return GestureDetector(
            onTap: () => widget.onSelect(date),
            child: Container(
              width: _tileWidth - 8,
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                color: selected ? AppColors.primary : AppColors.card,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: selected
                      ? AppColors.primary
                      : AppColors.divider,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _abbr[date.weekday - 1],
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: selected
                          ? Colors.white
                          : AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${date.day}',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color:
                          selected ? Colors.white : AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
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
                    memCacheHeight: 380,
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
                  groupSize: item.effectiveCapacity(selectedDate).toString(),
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

class _CapacitySection extends StatefulWidget {
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
  State<_CapacitySection> createState() => _CapacitySectionState();
}

class _CapacitySectionState extends State<_CapacitySection> {
  bool _booking = false;

  Future<void> _handleBook() async {
    if (_booking) return;
    setState(() => _booking = true);
    try {
      await widget.onBook(context);
    } finally {
      if (mounted) setState(() => _booking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final startOfDay = DateTime(
        widget.selectedDate.year, widget.selectedDate.month, widget.selectedDate.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    // Query by classId only — Dart-side date filter avoids composite index requirement
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('bookings')
          .where('classId', isEqualTo: widget.classId)
          .snapshots(),
      builder: (context, snap) {
        final allDocs = snap.data?.docs ?? [];
        final currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';
        final todayDocs = allDocs.where((d) {
          final data = d.data() as Map<String, dynamic>;
          if (data['status'] == 'cancelled_by_trainer') return false;
          final bd = data['bookingDate'];
          if (bd == null) return false;
          final dt = (bd as Timestamp).toDate();
          return !dt.isBefore(startOfDay) && dt.isBefore(endOfDay);
        }).toList();
        final booked = todayDocs.length;
        final alreadyBooked = todayDocs
            .any((d) => (d.data() as Map<String, dynamic>)['userId'] == currentUid);
        final capacity = int.tryParse(widget.groupSize) ?? 0;
        final isFull = capacity > 0 && booked >= capacity;
        final pct = capacity > 0 ? (booked / capacity).clamp(0.0, 1.0) : 0.0;

        return FutureBuilder<int>(
          future: WaitingListService.getWaitingCount(
              widget.classId, widget.selectedDate),
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
                if (alreadyBooked)
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: null,
                      icon: const Icon(Icons.check_circle_outline, size: 18),
                      label: const Text('Already Booked'),
                      style: ElevatedButton.styleFrom(
                        disabledBackgroundColor:
                            const Color(0xFF00D4AA).withValues(alpha: 0.15),
                        disabledForegroundColor: const Color(0xFF00D4AA),
                      ),
                    ),
                  )
                else if (!isFull)
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _booking ? null : _handleBook,
                      child: _booking
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Text('Book Now'),
                    ),
                  )
                else ...[
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => widget.onJoinWaitingList(context),
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

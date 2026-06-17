import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../models/class_model.dart';
import '../../services/google_sheet_service.dart';
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
    const months = [
      'Jan','Feb','Mar','Apr','May','Jun',
      'Jul','Aug','Sep','Oct','Nov','Dec'
    ];
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

  Future<int> _currentMonthBookings() async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final startOfMonth = DateTime(DateTime.now().year, DateTime.now().month, 1);
    final result = await FirebaseFirestore.instance
        .collection("bookings")
        .where("userId", isEqualTo: uid)
        .get();
    return result.docs.where((d) {
      final date = (d["createdAt"] as Timestamp).toDate();
      return date.isAfter(startOfMonth);
    }).length;
  }

  Future<void> _createBooking(
    BuildContext context,
    String classId,
    String displayName,
    String bookingTime,
  ) async {
    final uid = FirebaseAuth.instance.currentUser!.uid;

    final existing = await FirebaseFirestore.instance
        .collection("bookings")
        .where("userId", isEqualTo: uid)
        .where("className", isEqualTo: classId)
        .get();

    if (existing.docs.isNotEmpty) {
      if (context.mounted) {
        AppToast.warning(context, "You're already registered for $displayName");
      }
      return;
    }

    final userDoc = await FirebaseFirestore.instance
        .collection("users")
        .doc(uid)
        .get();

    final limit = (userDoc.data() as Map<String, dynamic>?)?["monthlyLimit"] ?? 0;
    final count = await _currentMonthBookings();

    if (limit > 0 && count >= limit) {
      if (context.mounted) {
        AppToast.error(context, "Monthly booking limit reached");
      }
      return;
    }

    await FirebaseFirestore.instance.collection("bookings").add({
      "userId": uid,
      "className": classId,
      "displayName": displayName,
      "bookingType": "class",
      "bookingDay": _selectedDayName,
      "bookingDate": Timestamp.fromDate(_selectedDate),
      "bookingTime": bookingTime,
      "createdAt": Timestamp.now(),
    });

    final email = FirebaseAuth.instance.currentUser?.email?.isNotEmpty == true
        ? FirebaseAuth.instance.currentUser!.email!
        : (userDoc.data() as Map<String, dynamic>?)?["email"]?.toString() ?? "";

    if (email.isNotEmpty) {
      await EmailService.sendBookingEmail(
        email: email,
        className: displayName,
        classTime: bookingTime,
      );
    }

    await NotificationService.showBookingConfirmed(displayName);
    await NotificationService.scheduleClassNotifications(
      displayName,
      _selectedDate,
      bookingTime,
    );

    if (context.mounted) {
      AppToast.success(
        context,
        '$displayName booked for ${_formatDate(_selectedDate)}',
      );
    }
  }

  Future<int> _getBookingCount(String classId) async {
    final result = await FirebaseFirestore.instance
        .collection("bookings")
        .where("className", isEqualTo: classId)
        .get();
    return result.docs.length;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Classes")),
      body: Column(
        children: [
          _DateBar(
            label: _formatDate(_selectedDate),
            onTap: _pickDate,
          ),
          Expanded(
            child: FutureBuilder<List<ClassModel>>(
              future: GoogleSheetService.getClasses(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(color: AppColors.primary),
                  );
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
                    final item = classes[index];
                    final classId =
                        "${item.day}_${item.mode}_${item.startTime}";
                    return _ClassCard(
                      item: item,
                      classId: classId,
                      onBook: (ctx) => _createBooking(
                          ctx, classId, item.mode, item.startTime),
                      getCount: _getBookingCount,
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
            border: Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
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

class _ClassCard extends StatelessWidget {
  final ClassModel item;
  final String classId;
  final Future<void> Function(BuildContext) onBook;
  final Future<int> Function(String) getCount;

  const _ClassCard({
    required this.item,
    required this.classId,
    required this.onBook,
    required this.getCount,
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
            child: CachedNetworkImage(
              imageUrl: item.image,
              fit: BoxFit.cover,
              fadeInDuration: const Duration(milliseconds: 400),
              fadeOutDuration: const Duration(milliseconds: 200),
              placeholder: (context, url) => Container(
                color: AppColors.surface,
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.fitness_center,
                          size: 42,
                          color: AppColors.primary.withValues(alpha: 0.4)),
                      const SizedBox(height: 8),
                      const Text('Loading...',
                          style: TextStyle(
                              color: AppColors.textMuted, fontSize: 12)),
                    ],
                  ),
                ),
              ),
              errorWidget: (context, url, error) => Container(
                color: AppColors.surface,
                child: const Center(
                  child: Icon(Icons.fitness_center,
                      size: 42, color: AppColors.textMuted),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.mode,
                        style: const TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: AppColors.primary.withValues(alpha: 0.4)),
                      ),
                      child: Text(
                        item.type,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
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
                FutureBuilder<int>(
                  future: getCount(classId),
                  builder: (context, snap) {
                    final booked = snap.data ?? 0;
                    final capacity = int.tryParse(item.groupSize) ?? 0;
                    final isFull = capacity > 0 && booked >= capacity;
                    final pct =
                        capacity > 0 ? (booked / capacity).clamp(0.0, 1.0) : 0.0;

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
                                  fontWeight: FontWeight.w600,
                                ),
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
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed:
                                isFull ? null : () => onBook(context),
                            style: ElevatedButton.styleFrom(
                              disabledBackgroundColor: AppColors.divider,
                              disabledForegroundColor: AppColors.textMuted,
                            ),
                            child: Text(isFull ? 'Class Full' : 'Book Now'),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ],
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

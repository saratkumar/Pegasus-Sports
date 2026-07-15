import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../models/class_model.dart';
import '../../models/admin_request_model.dart';
import '../../models/user_model.dart';
import '../../services/class_service.dart';
import '../../services/config_service.dart';
import '../../services/user_service.dart';
import '../../services/notifications.dart';
import '../../utils/app_colors.dart';
import '../../utils/app_toast.dart';

class TrainerHomeScreen extends StatefulWidget {
  const TrainerHomeScreen({super.key});

  @override
  State<TrainerHomeScreen> createState() => _TrainerHomeScreenState();
}

class _TrainerHomeScreenState extends State<TrainerHomeScreen> {
  DateTime _selectedDate = DateTime.now();
  String _trainerName = '';
  List<ClassModel> _allClasses = [];
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
    final results = await Future.wait([
      UserService.getCurrentUser(),
      ClassService.getClasses(),
    ]);
    if (!mounted) return;
    setState(() {
      _trainerName = (results[0] as UserModel?)?.name ?? '';
      _allClasses = results[1] as List<ClassModel>;
      _loading = false;
    });
  }

  List<ClassModel> get _classesForDate => _allClasses.where((cls) {
        if (cls.coach.trim().toLowerCase() != _trainerName.trim().toLowerCase()) {
          return false;
        }
        if (!cls.isActive) return false;
        if (cls.isCancelledOn(_selectedDate)) return false;
        return _matchesDate(cls, _selectedDate);
      }).toList();

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

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
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

  String _fmt(DateTime d) {
    const m = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${d.day} ${m[d.month - 1]} ${d.year}';
  }

  Future<void> _cancelClass(ClassModel cls) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Request Session Cancellation?',
            style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
        content: Text(
          'Send a cancellation request to admin for ${cls.mode} on ${_fmt(_selectedDate)}?\n\n'
          'Admin will approve the cancellation (clients refunded) or reassign another trainer.',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Back', style: TextStyle(color: AppColors.primary))),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.error, foregroundColor: Colors.white),
              child: const Text('Send Request')),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      final me = FirebaseAuth.instance.currentUser!;
      final d = _selectedDate;
      final dateStr =
          '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

      await FirebaseFirestore.instance.collection('adminRequests').add(
        AdminRequestModel(
          type: 'session_cancel',
          requestedBy: me.uid,
          requestedByName:
              _trainerName.isNotEmpty ? _trainerName : (me.displayName ?? me.email ?? ''),
          classId: cls.effectiveId,
          className: cls.mode,
          sessionDate: dateStr,
          amount: 0,
          note: 'Trainer requested cancellation of ${cls.mode} on $dateStr',
          createdAt: DateTime.now(),
        ).toFirestore(),
      );
      unawaited(ConfigService.logActivityEvent(
        eventType: 'Session Cancel Requested',
        classId: cls.effectiveId,
        className: cls.mode,
        sessionDate: DateTime.parse(dateStr),
        sessionTime: cls.startTime,
        userId: me.uid,
        userName: _trainerName.isNotEmpty
            ? _trainerName
            : (me.displayName ?? me.email ?? ''),
        bookedByRole: 'trainer',
        creditsUsed: 0,
      ));

      await NotificationService.showNewAdminRequest('session_cancel');

      if (mounted) {
        AppToast.success(context, 'Cancellation request sent to admin for approval');
      }
    } catch (e, st) {
      debugPrint('_cancelClass error: $e\n$st');
      if (mounted) AppToast.error(context, 'Request failed: ${e.toString()}');
    }
  }

  Future<void> _requestSlotIncrease(ClassModel cls) async {
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) {
        int slots = 1;
        return StatefulBuilder(
          builder: (ctx, setS) => AlertDialog(
            backgroundColor: AppColors.card,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            title: const Text('Request Slot Increase',
                style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Current capacity: ${cls.groupSize}',
                    style: const TextStyle(color: AppColors.textSecondary)),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                        icon: const Icon(Icons.remove_circle_outline),
                        onPressed: slots > 1 ? () => setS(() => slots--) : null),
                    Text('$slots extra',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                    IconButton(
                        icon: const Icon(Icons.add_circle_outline, color: AppColors.primary),
                        onPressed: () => setS(() => slots++)),
                  ],
                ),
              ],
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel', style: TextStyle(color: AppColors.textMuted))),
              ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, slots),
                  child: const Text('Send Request')),
            ],
          ),
        );
      },
    );
    if (result == null) return;

    final me = FirebaseAuth.instance.currentUser!;
    final d = _selectedDate;
    final dateStr =
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    await FirebaseFirestore.instance.collection('adminRequests').add(
      AdminRequestModel(
        type: 'slot_increase',
        requestedBy: me.uid,
        requestedByName: me.displayName ?? me.email ?? '',
        classId: cls.effectiveId,
        className: cls.mode,
        sessionDate: dateStr,
        amount: result,
        note: 'Extra slots requested for ${cls.mode} on $dateStr',
        createdAt: DateTime.now(),
      ).toFirestore(),
    );
    unawaited(ConfigService.logActivityEvent(
      eventType: 'Slot Increase Requested',
      classId: cls.effectiveId,
      className: cls.mode,
      sessionDate: DateTime.parse(dateStr),
      sessionTime: cls.startTime,
      userId: me.uid,
      userName: me.displayName ?? me.email ?? '',
      bookedByRole: 'trainer',
      creditsUsed: result,
    ));
    await NotificationService.showNewAdminRequest('slot_increase');
    if (mounted) AppToast.success(context, 'Slot increase request sent to admin');
  }

  Future<void> _bookForClient(ClassModel cls) async {
    final clients = await UserService.getUsersByRole('client');
    if (!mounted) return;

    final selected = await showDialog<UserModel>(
      context: context,
      builder: (ctx) => _ClientPickerDialog(clients: clients),
    );
    if (selected == null) return;

    final hasCredits = await UserService.hasEnoughCredits(selected.uid);
    if (!hasCredits) {
      if (!mounted) return;
      final req = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.card,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: const Text('No Credits',
              style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
          content: Text('${selected.name} has no credits. Request admin to add credits?',
              style: const TextStyle(color: AppColors.textSecondary)),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel', style: TextStyle(color: AppColors.textMuted))),
            ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Request Credits')),
          ],
        ),
      );
      if (req == true) {
        final me = FirebaseAuth.instance.currentUser!;
        await FirebaseFirestore.instance.collection('adminRequests').add(
          AdminRequestModel(
            type: 'credit_request',
            requestedBy: me.uid,
            requestedByName: me.displayName ?? me.email ?? '',
            targetUserId: selected.uid,
            targetUserName: selected.name,
            classId: cls.effectiveId,
            className: cls.mode,
            amount: 1,
            note: 'Trainer booking on behalf of client',
            createdAt: DateTime.now(),
          ).toFirestore(),
        );
        unawaited(ConfigService.logActivityEvent(
          eventType: 'Credit Request Submitted',
          classId: cls.effectiveId,
          className: cls.mode,
          sessionDate: DateTime.now(),
          sessionTime: cls.startTime,
          userId: me.uid,
          userName: me.displayName ?? me.email ?? '',
          bookedByRole: 'trainer',
          creditsUsed: 1,
          note: 'For client: ${selected.name}',
        ));
        await NotificationService.showNewAdminRequest('credit_request');
        if (mounted) {
          AppToast.success(context, 'Credit request sent to admin for ${selected.name}');
        }
      }
      return;
    }

    final me = FirebaseAuth.instance.currentUser!;
    final bookingRef = await FirebaseFirestore.instance.collection('bookings').add({
      'userId': selected.uid,
      'classId': cls.effectiveId,
      'displayName': cls.mode,
      'bookingType': 'class',
      'bookingDay': _dayNames[_selectedDate.weekday - 1],
      'bookingDate': Timestamp.fromDate(_selectedDate),
      'bookingTime': cls.startTime,
      'createdAt': Timestamp.now(),
      'bookedBy': me.uid,
      'bookedByRole': 'trainer',
      'creditsUsed': 1,
    });
    unawaited(ConfigService.logActivityEvent(
      eventType: 'Booked',
      classId: cls.effectiveId,
      className: cls.mode,
      sessionDate: _selectedDate,
      sessionTime: cls.startTime,
      userId: selected.uid,
      userName: selected.name,
      bookedByRole: 'trainer',
      bookingId: bookingRef.id,
    ));
    await UserService.deductCredit(selected.uid);
    if (mounted) AppToast.success(context, '${cls.mode} booked for ${selected.name}');
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
          body: Center(child: CircularProgressIndicator(color: AppColors.primary)));
    }

    final classes = _classesForDate;
    return Scaffold(
      body: Column(
        children: [
          _DateBar(date: _selectedDate, fmt: _fmt, onTap: _pickDate),
          Expanded(
            child: RefreshIndicator(
              color: AppColors.primary,
              onRefresh: _loadData,
              child: classes.isEmpty
                  ? ListView(
                      children: [
                        SizedBox(
                          height: 300,
                          child: Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.event_busy,
                                    size: 48, color: AppColors.textMuted),
                                const SizedBox(height: 12),
                                Text(
                                  'No sessions on ${_dayNames[_selectedDate.weekday - 1]}',
                                  style: const TextStyle(
                                      color: AppColors.textSecondary, fontSize: 15),
                                ),
                                const SizedBox(height: 8),
                                if (_trainerName.isEmpty)
                                  const Text(
                                    'Profile name not set — contact admin',
                                    style: TextStyle(fontSize: 12, color: AppColors.error),
                                    textAlign: TextAlign.center,
                                  )
                                else
                                  Text(
                                    'Showing classes where coach = "$_trainerName"\n'
                                    'Make sure this matches exactly in the Classes sheet.',
                                    style: const TextStyle(
                                        fontSize: 12, color: AppColors.textMuted),
                                    textAlign: TextAlign.center,
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(14),
                      itemCount: classes.length,
                      itemBuilder: (_, i) => _TrainerClassCard(
                        cls: classes[i],
                        date: _selectedDate,
                        getEnrollment: (id) => ClassService.getBookingCount(id, _selectedDate),
                        onCancel: _cancelClass,
                        onSlotRequest: _requestSlotIncrease,
                        onBookForClient: _bookForClient,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Shared date bar ───────────────────────────────────────────────────────────

class _DateBar extends StatelessWidget {
  final DateTime date;
  final String Function(DateTime) fmt;
  final VoidCallback onTap;
  const _DateBar({required this.date, required this.fmt, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.bg,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
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
              const Icon(Icons.calendar_today, color: AppColors.primary, size: 18),
              const SizedBox(width: 12),
              Text(fmt(date),
                  style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w600)),
              const Spacer(),
              const Icon(Icons.keyboard_arrow_down, color: AppColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Trainer class card ────────────────────────────────────────────────────────

class _TrainerClassCard extends StatelessWidget {
  final ClassModel cls;
  final DateTime date;
  final Future<int> Function(String) getEnrollment;
  final Future<void> Function(ClassModel) onCancel;
  final Future<void> Function(ClassModel) onSlotRequest;
  final Future<void> Function(ClassModel) onBookForClient;

  const _TrainerClassCard({
    required this.cls,
    required this.date,
    required this.getEnrollment,
    required this.onCancel,
    required this.onSlotRequest,
    required this.onBookForClient,
  });

  @override
  Widget build(BuildContext context) {
    final capacity = cls.effectiveCapacity(date);
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(cls.mode,
                    style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(cls.type,
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.primary, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _info(Icons.schedule, '${cls.startTime} · ${cls.duration}'),
          _info(Icons.location_on_outlined, '${cls.location} · ${cls.detailLocation}'),
          const SizedBox(height: 12),
          FutureBuilder<int>(
            future: getEnrollment(cls.effectiveId),
            builder: (context, snap) {
              final enrolled = snap.data ?? 0;
              final full = capacity > 0 && enrolled >= capacity;
              return Row(
                children: [
                  const Icon(Icons.people_outline, size: 15, color: AppColors.textMuted),
                  const SizedBox(width: 6),
                  Text('$enrolled / $capacity enrolled',
                      style: TextStyle(
                          fontSize: 13,
                          color: full ? AppColors.error : AppColors.textSecondary,
                          fontWeight: FontWeight.w600)),
                  if (full) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.error.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text('FULL',
                          style: TextStyle(
                              fontSize: 10, color: AppColors.error, fontWeight: FontWeight.w700)),
                    ),
                  ],
                ],
              );
            },
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _btn(Icons.person_add_outlined, 'Book for Client', AppColors.primary,
                  () => onBookForClient(cls)),
              _btn(Icons.add_box_outlined, 'More Slots', const Color(0xFF00D4AA),
                  () => onSlotRequest(cls)),
              _btn(Icons.cancel_outlined, 'Cancel', AppColors.error,
                  () => onCancel(cls)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _info(IconData icon, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          children: [
            Icon(icon, size: 14, color: AppColors.textMuted),
            const SizedBox(width: 6),
            Expanded(
                child: Text(text,
                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary))),
          ],
        ),
      );

  Widget _btn(IconData icon, String label, Color color, VoidCallback onTap) =>
      OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 14, color: color),
        label: Text(label, style: TextStyle(color: color, fontSize: 12)),
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: color.withValues(alpha: 0.5)),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
}

// ── Client picker dialog ──────────────────────────────────────────────────────

class _ClientPickerDialog extends StatefulWidget {
  final List<UserModel> clients;
  const _ClientPickerDialog({required this.clients});

  @override
  State<_ClientPickerDialog> createState() => _ClientPickerDialogState();
}

class _ClientPickerDialogState extends State<_ClientPickerDialog> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final filtered = widget.clients
        .where((c) =>
            c.name.toLowerCase().contains(_search.toLowerCase()) ||
            c.email.toLowerCase().contains(_search.toLowerCase()))
        .toList();

    return AlertDialog(
      backgroundColor: AppColors.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: const Text('Select Client',
          style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
      content: SizedBox(
        width: double.maxFinite,
        height: 350,
        child: Column(
          children: [
            TextField(
              onChanged: (v) => setState(() => _search = v),
              decoration: InputDecoration(
                hintText: 'Search client...',
                prefixIcon: const Icon(Icons.search, size: 18),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: ListView.builder(
                itemCount: filtered.length,
                itemBuilder: (_, i) => ListTile(
                  leading: CircleAvatar(
                    backgroundColor: AppColors.primary.withValues(alpha: 0.15),
                    child: Text(
                      filtered[i].name.isNotEmpty ? filtered[i].name[0] : '?',
                      style: const TextStyle(
                          color: AppColors.primary, fontWeight: FontWeight.w700),
                    ),
                  ),
                  title: Text(filtered[i].name,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                  subtitle: Text('${filtered[i].credits} credits',
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textSecondary)),
                  onTap: () => Navigator.pop(context, filtered[i]),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel', style: TextStyle(color: AppColors.textMuted)),
        ),
      ],
    );
  }
}

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../models/class_model.dart';
import '../../models/admin_request_model.dart';
import '../../models/user_model.dart';
import '../../services/class_service.dart';
import '../../services/user_service.dart';
import '../../utils/app_colors.dart';
import '../../utils/app_toast.dart';

class TrainerHomeScreen extends StatefulWidget {
  const TrainerHomeScreen({super.key});

  @override
  State<TrainerHomeScreen> createState() => _TrainerHomeScreenState();
}

class _TrainerHomeScreenState extends State<TrainerHomeScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  DateTime _selectedDate = DateTime.now();

  static const _dayNames = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday',
    'Friday', 'Saturday', 'Sunday',
  ];

  String get _selectedDayName => _dayNames[_selectedDate.weekday - 1];

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

  String _formatDate(DateTime d) {
    const months = [
      'Jan','Feb','Mar','Apr','May','Jun',
      'Jul','Aug','Sep','Oct','Nov','Dec'
    ];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
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

  Future<int> _getEnrollmentCount(String classId) async {
    return ClassService.getBookingCount(classId, _selectedDate);
  }

  Future<void> _cancelClass(ClassModel cls) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Cancel This Session?',
            style: TextStyle(
                color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
        content: Text(
          'Cancel ${cls.mode} on ${_formatDate(_selectedDate)}?\n\nAll enrolled clients will be notified and credits refunded.',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep', style: TextStyle(color: AppColors.primary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error, foregroundColor: Colors.white),
            child: const Text('Cancel Session'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    // Mark all bookings for this class+date as cancelled and refund credits
    final startOfDay =
        DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    final bookingsSnap = await FirebaseFirestore.instance
        .collection('bookings')
        .where('classId', isEqualTo: cls.effectiveId)
        .where('bookingDate',
            isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
        .where('bookingDate', isLessThan: Timestamp.fromDate(endOfDay))
        .get();

    final batch = FirebaseFirestore.instance.batch();
    for (final doc in bookingsSnap.docs) {
      batch.update(doc.reference, {'status': 'cancelled_by_trainer'});
      final userId = doc['userId'] as String?;
      final creditsUsed = (doc.data()['creditsUsed'] as int?) ?? 1;
      if (userId != null && creditsUsed > 0) {
        UserService.addCredits(userId, creditsUsed);
      }
    }
    await batch.commit();

    if (mounted) AppToast.success(context, '${cls.mode} session cancelled');
  }

  Future<void> _requestSlotIncrease(ClassModel cls) async {
    int extraSlots = 1;
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) {
        int slots = 1;
        return StatefulBuilder(
          builder: (ctx, setS) => AlertDialog(
            backgroundColor: AppColors.card,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18)),
            title: const Text('Request Slot Increase',
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Current capacity: ${cls.groupSize}',
                    style:
                        const TextStyle(color: AppColors.textSecondary)),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline),
                      onPressed: slots > 1
                          ? () => setS(() => slots--)
                          : null,
                    ),
                    Text('$slots extra',
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w700)),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline,
                          color: AppColors.primary),
                      onPressed: () => setS(() => slots++),
                    ),
                  ],
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel',
                    style: TextStyle(color: AppColors.textMuted)),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, slots),
                child: const Text('Send Request'),
              ),
            ],
          ),
        );
      },
    );
    if (result == null) return;
    extraSlots = result;

    final me = FirebaseAuth.instance.currentUser!;
    final req = AdminRequestModel(
      type: 'slot_increase',
      requestedBy: me.uid,
      requestedByName: me.displayName ?? me.email ?? '',
      classId: cls.effectiveId,
      className: cls.mode,
      amount: extraSlots,
      createdAt: DateTime.now(),
    );
    await FirebaseFirestore.instance
        .collection('adminRequests')
        .add(req.toFirestore());

    if (mounted) {
      AppToast.success(
          context, 'Slot increase request sent to admin');
    }
  }

  Future<void> _bookForClient(ClassModel cls) async {
    final clients = await UserService.getUsersByRole('client');
    if (!mounted) return;

    final selectedUser = await showDialog<UserModel>(
      context: context,
      builder: (ctx) => _ClientPickerDialog(clients: clients),
    );
    if (selectedUser == null) return;

    final hasCredits = await UserService.hasEnoughCredits(selectedUser.uid);

    if (!hasCredits) {
      // No credits — ask trainer if they want to request admin to add credits
      if (!mounted) return;
      final requestCredit = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.card,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: const Text('No Credits',
              style: TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w700)),
          content: Text(
            '${selectedUser.name} has no credits. Request admin to add credits?',
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel',
                  style: TextStyle(color: AppColors.textMuted)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Request Credits'),
            ),
          ],
        ),
      );

      if (requestCredit == true) {
        final me = FirebaseAuth.instance.currentUser!;
        final req = AdminRequestModel(
          type: 'credit_request',
          requestedBy: me.uid,
          requestedByName: me.displayName ?? me.email ?? '',
          targetUserId: selectedUser.uid,
          targetUserName: selectedUser.name,
          classId: cls.effectiveId,
          className: cls.mode,
          amount: 1,
          note: 'Trainer booking on behalf of client',
          createdAt: DateTime.now(),
        );
        await FirebaseFirestore.instance
            .collection('adminRequests')
            .add(req.toFirestore());
        if (mounted) {
          AppToast.info(context,
              'Credit request sent to admin for ${selectedUser.name}');
        }
      }
      return;
    }

    // Has credits — create booking and deduct credit
    final me = FirebaseAuth.instance.currentUser!;
    await FirebaseFirestore.instance.collection('bookings').add({
      'userId': selectedUser.uid,
      'classId': cls.effectiveId,
      'displayName': cls.mode,
      'bookingType': 'class',
      'bookingDay': _selectedDayName,
      'bookingDate': Timestamp.fromDate(_selectedDate),
      'bookingTime': cls.startTime,
      'createdAt': Timestamp.now(),
      'bookedBy': me.uid,
      'bookedByRole': 'trainer',
      'creditsUsed': 1,
    });
    await UserService.deductCredit(selectedUser.uid);

    if (mounted) {
      AppToast.success(
          context, '${cls.mode} booked for ${selectedUser.name}');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Trainer Panel'),
        bottom: TabBar(
          controller: _tab,
          indicatorColor: AppColors.primary,
          labelColor: AppColors.textPrimary,
          unselectedLabelColor: AppColors.textMuted,
          tabs: const [
            Tab(text: 'My Classes'),
            Tab(text: 'Requests'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          _ClassesTab(
            selectedDate: _selectedDate,
            selectedDayName: _selectedDayName,
            formatDate: _formatDate,
            onPickDate: _pickDate,
            getEnrollment: _getEnrollmentCount,
            onCancel: _cancelClass,
            onSlotRequest: _requestSlotIncrease,
            onBookForClient: _bookForClient,
          ),
          _MyRequestsTab(),
        ],
      ),
    );
  }
}

// ── Classes tab ──────────────────────────────────────────────────────────────

class _ClassesTab extends StatelessWidget {
  final DateTime selectedDate;
  final String selectedDayName;
  final String Function(DateTime) formatDate;
  final VoidCallback onPickDate;
  final Future<int> Function(String) getEnrollment;
  final Future<void> Function(ClassModel) onCancel;
  final Future<void> Function(ClassModel) onSlotRequest;
  final Future<void> Function(ClassModel) onBookForClient;

  const _ClassesTab({
    required this.selectedDate,
    required this.selectedDayName,
    required this.formatDate,
    required this.onPickDate,
    required this.getEnrollment,
    required this.onCancel,
    required this.onSlotRequest,
    required this.onBookForClient,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Date picker bar
        Container(
          color: AppColors.bg,
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: GestureDetector(
            onTap: onPickDate,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.calendar_today,
                      color: AppColors.primary, size: 18),
                  const SizedBox(width: 12),
                  Text(formatDate(selectedDate),
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
        ),
        Expanded(
          child: StreamBuilder<List<ClassModel>>(
            stream: ClassService.streamClasses(),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(
                    child: CircularProgressIndicator(
                        color: AppColors.primary));
              }
              final all = snap.data ?? [];
              final classes =
                  all.where((c) => c.day == selectedDayName).toList();
              if (classes.isEmpty) {
                return Center(
                  child: Text('No classes on $selectedDayName',
                      style: const TextStyle(
                          color: AppColors.textSecondary)),
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.all(14),
                itemCount: classes.length,
                itemBuilder: (context, i) => _TrainerClassCard(
                  cls: classes[i],
                  date: selectedDate,
                  getEnrollment: getEnrollment,
                  onCancel: onCancel,
                  onSlotRequest: onSlotRequest,
                  onBookForClient: onBookForClient,
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

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
    final capacity = int.tryParse(cls.groupSize) ?? 0;
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(cls.type,
                    style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _info(Icons.schedule, '${cls.startTime} · ${cls.duration}'),
          _info(Icons.location_on_outlined,
              '${cls.location} · ${cls.detailLocation}'),
          const SizedBox(height: 12),
          FutureBuilder<int>(
            future: getEnrollment(cls.effectiveId),
            builder: (context, snap) {
              final enrolled = snap.data ?? 0;
              final isFull = capacity > 0 && enrolled >= capacity;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.people_outline,
                          size: 15, color: AppColors.textMuted),
                      const SizedBox(width: 6),
                      Text(
                        '$enrolled / $capacity enrolled',
                        style: TextStyle(
                            fontSize: 13,
                            color: isFull
                                ? AppColors.error
                                : AppColors.textSecondary,
                            fontWeight: FontWeight.w600),
                      ),
                      if (isFull) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.error.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text('FULL',
                              style: TextStyle(
                                  fontSize: 10,
                                  color: AppColors.error,
                                  fontWeight: FontWeight.w700)),
                        ),
                      ],
                    ],
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _actionButton(
                Icons.person_add_outlined,
                'Book for Client',
                AppColors.primary,
                () => onBookForClient(cls),
              ),
              _actionButton(
                Icons.add_box_outlined,
                'Request More Slots',
                const Color(0xFF00D4AA),
                () => onSlotRequest(cls),
              ),
              _actionButton(
                Icons.cancel_outlined,
                'Cancel Session',
                AppColors.error,
                () => onCancel(cls),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _info(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(icon, size: 14, color: AppColors.textMuted),
          const SizedBox(width: 6),
          Expanded(
            child: Text(text,
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textSecondary)),
          ),
        ],
      ),
    );
  }

  Widget _actionButton(
      IconData icon, String label, Color color, VoidCallback onTap) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 14, color: color),
      label: Text(label, style: TextStyle(color: color, fontSize: 12)),
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: color.withValues(alpha: 0.5)),
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}

// ── My Requests tab ─────────────────────────────────────────────────────────

class _MyRequestsTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('adminRequests')
          .where('requestedBy', isEqualTo: uid)
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(
              child: CircularProgressIndicator(color: AppColors.primary));
        }
        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) {
          return const Center(
            child: Text('No requests yet',
                style: TextStyle(color: AppColors.textSecondary)),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(14),
          itemCount: docs.length,
          itemBuilder: (context, i) {
            final data = docs[i].data() as Map<String, dynamic>;
            final type = data['type'] ?? '';
            final status = data['status'] ?? 'pending';
            final statusColor = status == 'approved'
                ? const Color(0xFF00D4AA)
                : status == 'rejected'
                    ? AppColors.error
                    : const Color(0xFFFFAB40);

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
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          type == 'credit_request'
                              ? 'Credit Request — ${data['targetUserName'] ?? ''}'
                              : 'Slot Increase — ${data['className'] ?? ''}',
                          style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary),
                        ),
                        const SizedBox(height: 4),
                        Text('+${data['amount']} ${type == 'credit_request' ? 'credits' : 'slots'}',
                            style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary)),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      status.toUpperCase(),
                      style: TextStyle(
                          fontSize: 10,
                          color: statusColor,
                          fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

// ── Client picker dialog ─────────────────────────────────────────────────────

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
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: const Text('Select Client',
          style: TextStyle(
              color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
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
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 10),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: ListView.builder(
                itemCount: filtered.length,
                itemBuilder: (_, i) {
                  final c = filtered[i];
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor:
                          AppColors.primary.withValues(alpha: 0.15),
                      child: Text(c.name.isNotEmpty ? c.name[0] : '?',
                          style: const TextStyle(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w700)),
                    ),
                    title: Text(c.name,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary)),
                    subtitle: Text('${c.credits} credits',
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.textSecondary)),
                    onTap: () => Navigator.pop(context, c),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel',
              style: TextStyle(color: AppColors.textMuted)),
        ),
      ],
    );
  }
}

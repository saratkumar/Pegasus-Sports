import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../models/admin_request_model.dart';
import '../../models/qr_payment_request_model.dart';
import '../../models/user_model.dart';
import '../../services/user_service.dart';
import '../../services/class_service.dart';
import '../../services/config_service.dart';
import '../../services/notifications.dart';
import '../../services/qr_payment_service.dart';
import '../../services/request_notification_service.dart';
import '../../services/waiting_list_service.dart';
import '../../utils/app_colors.dart';
import '../../utils/app_toast.dart';
import '../../widgets/timeline_range_selector.dart';

class AdminRequestsScreen extends StatefulWidget {
  const AdminRequestsScreen({super.key});

  @override
  State<AdminRequestsScreen> createState() => _AdminRequestsScreenState();
}

class _AdminRequestsScreenState extends State<AdminRequestsScreen>
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
        title: const Text('Requests'),
        bottom: TabBar(
          controller: _tab,
          indicatorColor: AppColors.primary,
          labelColor: AppColors.textPrimary,
          unselectedLabelColor: AppColors.textMuted,
          tabs: const [
            Tab(text: 'Pending'),
            Tab(text: 'Resolved'),
            Tab(text: 'QR Payments'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          _RequestList(statusFilter: 'pending'),
          _RequestList(statusFilter: null, excludePending: true),
          const _QrPaymentsTab(),
        ],
      ),
    );
  }
}

// ── QR Payments tab ─────────────────────────────────────────────────────────

class _QrPaymentsTab extends StatefulWidget {
  const _QrPaymentsTab();

  @override
  State<_QrPaymentsTab> createState() => _QrPaymentsTabState();
}

class _QrPaymentsTabState extends State<_QrPaymentsTab> {
  bool _showResolved = false;
  DateTimeRange? _range;
  Future<List<Map<String, String>>>? _logFuture;

  @override
  void initState() {
    super.initState();
    _logFuture = ConfigService.getActivityLog();
  }

  void _reloadLog() {
    setState(() => _logFuture = ConfigService.getActivityLog());
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
          child: Row(
            children: [
              ChoiceChip(
                label: const Text('Pending'),
                selected: !_showResolved,
                onSelected: (_) => setState(() => _showResolved = false),
                selectedColor: AppColors.primary.withValues(alpha: 0.15),
                labelStyle: TextStyle(
                    color: !_showResolved
                        ? AppColors.primary
                        : AppColors.textSecondary,
                    fontWeight:
                        !_showResolved ? FontWeight.w700 : FontWeight.w400),
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('Resolved'),
                selected: _showResolved,
                onSelected: (_) => setState(() => _showResolved = true),
                selectedColor: AppColors.primary.withValues(alpha: 0.15),
                labelStyle: TextStyle(
                    color: _showResolved
                        ? AppColors.primary
                        : AppColors.textSecondary,
                    fontWeight:
                        _showResolved ? FontWeight.w700 : FontWeight.w400),
              ),
            ],
          ),
        ),
        // Resolved QR requests are deleted from Firestore right after being
        // archived to the Activity Log Sheet (see QrPaymentService.approve/
        // reject), so "Resolved" is sourced from the Sheet, bounded to this
        // timeline window — any doc still in Firestore here only means the
        // Sheet archive itself failed (fallback, not the normal case).
        if (_showResolved)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
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
                  tooltip: 'Reload activity log',
                  onPressed: _reloadLog,
                ),
              ],
            ),
          ),
        Expanded(
          child: _showResolved ? _buildResolved() : _buildPending(),
        ),
      ],
    );
  }

  Widget _buildPending() {
    return StreamBuilder<List<QrPaymentRequestModel>>(
      stream: QrPaymentService.streamPending(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting &&
            !snap.hasData) {
          return const Center(
              child: CircularProgressIndicator(color: AppColors.primary));
        }
        final reqs = snap.data ?? [];
        if (reqs.isEmpty) {
          return const Center(
            child: Text('No pending QR payments',
                style: TextStyle(color: AppColors.textSecondary)),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(14),
          itemCount: reqs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, i) => _QrPaymentCard(req: reqs[i]),
        );
      },
    );
  }

  // Resolved QR payments are read from the Activity Log Sheet only — once
  // archived there, the Firestore qrPaymentRequests doc is deleted (see
  // QrPaymentService.approve/reject), so the Sheet is treated as the sole
  // source of truth for this tab rather than merging in a Firestore
  // fallback.
  Widget _buildResolved() {
    return FutureBuilder<List<Map<String, String>>>(
      future: _logFuture,
      builder: (context, logSnap) {
        final loading = logSnap.connectionState == ConnectionState.waiting &&
            !logSnap.hasData;
        if (loading) {
          return const Center(
              child: CircularProgressIndicator(color: AppColors.primary));
        }
        if (logSnap.hasError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('Could not load the Activity Log',
                    style: TextStyle(color: AppColors.textSecondary)),
                const SizedBox(height: 8),
                TextButton(onPressed: _reloadLog, child: const Text('Retry')),
              ],
            ),
          );
        }

        final logRows = (logSnap.data ?? [])
            .where((r) =>
                (r['eventType'] == 'QR Payment Approved' ||
                    r['eventType'] == 'QR Payment Rejected') &&
                isWithinRange(r['timestamp'], _range ?? defaultDateRange()))
            .toList()
          ..sort((a, b) => (b['timestamp'] ?? '').compareTo(a['timestamp'] ?? ''));

        if (logRows.isEmpty) {
          return const Center(
            child: Text('No resolved QR payments in this window',
                style: TextStyle(color: AppColors.textSecondary)),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(14),
          itemCount: logRows.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, i) => _QrPaymentLogCard(row: logRows[i]),
        );
      },
    );
  }
}

/// Read-only card for a resolved QR payment sourced from the Activity Log
/// Sheet (as opposed to [_QrPaymentCard], which is Firestore-backed and
/// only has data for the pending/un-archived-fallback cases).
class _QrPaymentLogCard extends StatelessWidget {
  final Map<String, String> row;
  const _QrPaymentLogCard({required this.row});

  @override
  Widget build(BuildContext context) {
    final approved = row['eventType'] == 'QR Payment Approved';
    final color = approved ? const Color(0xFF00D4AA) : AppColors.error;
    final ts = DateTime.tryParse(row['timestamp'] ?? '')?.toLocal();
    final dateLabel = ts == null ? '' : formatWithWeekday(ts);

    return Container(
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
                child: Text(row['className'] ?? '',
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary)),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text((approved ? 'APPROVED' : 'REJECTED'),
                    style: TextStyle(
                        fontSize: 10,
                        color: color,
                        fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text('Client: ${row['userName'] ?? ''}',
              style: const TextStyle(
                  fontSize: 12, color: AppColors.textSecondary)),
          if ((row['note'] ?? '').isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(row['note']!,
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textSecondary)),
          ],
          if (dateLabel.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(dateLabel,
                style:
                    const TextStyle(fontSize: 11, color: AppColors.textMuted)),
          ],
        ],
      ),
    );
  }
}

class _QrPaymentCard extends StatefulWidget {
  final QrPaymentRequestModel req;
  const _QrPaymentCard({required this.req});

  @override
  State<_QrPaymentCard> createState() => _QrPaymentCardState();
}

class _QrPaymentCardState extends State<_QrPaymentCard> {
  bool _processing = false;

  Color get _statusColor {
    switch (widget.req.status) {
      case 'approved':
        return const Color(0xFF00D4AA);
      case 'rejected':
        return AppColors.error;
      default:
        return const Color(0xFFFFAB40);
    }
  }

  Future<void> _approve() async {
    final refCtrl = TextEditingController();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Confirm Payment Received',
            style: TextStyle(
                color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                '${widget.req.userName} · ${widget.req.planName} · '
                '${widget.req.currency} ${widget.req.amount.toStringAsFixed(2)}',
                style: const TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: 14),
            TextField(
              controller: refCtrl,
              decoration: InputDecoration(
                labelText: 'Payment Reference (optional)',
                helperText: 'Bank transfer ID etc — leave blank to omit from the invoice',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel', style: TextStyle(color: AppColors.textMuted))),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00D4AA), foregroundColor: Colors.white),
              child: const Text('Confirm & Activate')),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _processing = true);
    try {
      await QrPaymentService.approve(widget.req,
          paymentRef: refCtrl.text.trim().isEmpty ? null : refCtrl.text.trim());
      if (mounted) AppToast.success(context, 'Payment confirmed — plan activated & invoice emailed');
    } catch (e) {
      if (mounted) AppToast.error(context, 'Failed: $e');
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  Future<void> _reject() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Reject this payment claim?',
            style: TextStyle(
                color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
        content: const Text(
            "Use this if the payment never actually arrived. The client will be notified by email.",
            style: TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel', style: TextStyle(color: AppColors.primary))),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.error, foregroundColor: Colors.white),
              child: const Text('Reject')),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _processing = true);
    try {
      await QrPaymentService.reject(widget.req);
      if (mounted) AppToast.info(context, 'Request rejected');
    } catch (e) {
      if (mounted) AppToast.error(context, 'Failed: $e');
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final req = widget.req;
    final isPending = req.status == 'pending';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: isPending
                ? const Color(0xFFFFAB40).withValues(alpha: 0.4)
                : AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(req.planName,
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _statusColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(req.status.toUpperCase(),
                    style: TextStyle(
                        fontSize: 10, color: _statusColor, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text('Client: ${req.userName} (${req.userEmail})',
              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          const SizedBox(height: 3),
          Text('${req.currency} ${req.amount.toStringAsFixed(2)} · ${req.credits} credits',
              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          if (req.paymentRef != null) ...[
            const SizedBox(height: 3),
            Text('Ref: ${req.paymentRef}',
                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          ],
          if (isPending) ...[
            const SizedBox(height: 14),
            if (_processing)
              const Center(
                  child: SizedBox(
                      height: 24,
                      width: 24,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppColors.primary)))
            else
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _reject,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.error,
                        side: BorderSide(color: AppColors.error.withValues(alpha: 0.5)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Text('Reject'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _approve,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00D4AA),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Text('Confirm Payment'),
                    ),
                  ),
                ],
              ),
          ],
        ],
      ),
    );
  }
}

class _RequestList extends StatelessWidget {
  final String? statusFilter;
  final bool excludePending;

  const _RequestList({this.statusFilter, this.excludePending = false});

  @override
  Widget build(BuildContext context) {
    // When filtering by status, skip orderBy to avoid composite index — sort in Dart
    final stream = statusFilter != null
        ? FirebaseFirestore.instance
            .collection('adminRequests')
            .where('status', isEqualTo: statusFilter)
            .snapshots()
        : FirebaseFirestore.instance
            .collection('adminRequests')
            .orderBy('createdAt', descending: true)
            .snapshots();

    return StreamBuilder<QuerySnapshot>(
      stream: stream,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return const Center(
              child: CircularProgressIndicator(color: AppColors.primary));
        }
        if (snap.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Text('Failed to load requests: ${snap.error}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.error)),
            ),
          );
        }
        var docs = snap.data?.docs ?? [];
        if (excludePending) {
          docs = docs
              .where((d) => (d['status'] as String?) != 'pending')
              .toList();
        }
        // Sort newest-first in Dart
        docs.sort((a, b) {
          final ta = (a['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
          final tb = (b['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
          return tb.compareTo(ta);
        });
        if (docs.isEmpty) {
          return const Center(
            child: Text('No requests',
                style: TextStyle(color: AppColors.textSecondary)),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(14),
          itemCount: docs.length,
          itemBuilder: (context, i) {
            final req = AdminRequestModel.fromFirestore(docs[i]);
            return _RequestCard(request: req);
          },
        );
      },
    );
  }
}

// ── Request card ──────────────────────────────────────────────────────────────

class _RequestCard extends StatefulWidget {
  final AdminRequestModel request;
  const _RequestCard({required this.request});

  @override
  State<_RequestCard> createState() => _RequestCardState();
}

class _RequestCardState extends State<_RequestCard> {
  bool _processing = false;

  AdminRequestModel get req => widget.request;

  // ── Helpers ────────────────────────────────────────────────────────────────

  Color get _statusColor {
    switch (req.status) {
      case 'approved':
      case 'approved_cancel':
      case 'reassigned':
        return const Color(0xFF00D4AA);
      case 'rejected':
        return AppColors.error;
      default:
        return const Color(0xFFFFAB40);
    }
  }

  String get _statusLabel {
    switch (req.status) {
      case 'approved_cancel':
        return 'CANCELLED';
      case 'reassigned':
        return 'REASSIGNED';
      default:
        return req.status.toUpperCase();
    }
  }

  String get _typeLabel {
    switch (req.type) {
      case 'credit_request':
        return 'Credit Request';
      case 'session_cancel':
        return 'Session Cancellation Request';
      case 'appointment_booking':
        return 'Appointment Booking Request';
      default:
        return 'Slot Increase Request';
    }
  }

  // ── Standard approve / reject (credit_request & slot_increase) ────────────

  Future<void> _resolve(bool approved) async {
    setState(() => _processing = true);
    try {
      final adminUid = FirebaseAuth.instance.currentUser?.uid ?? '';

      // Rejecting an appointment_booking frees the slot immediately, no
      // matter what — approving leaves it locked (occupied by this
      // confirmed booking).
      if (!approved && req.type == 'appointment_booking' && req.classId != null) {
        await FirebaseFirestore.instance
            .collection('appointmentSlots')
            .doc(req.classId)
            .update({'activeRequestId': null});
      }

      if (approved) {
        if (req.type == 'credit_request' && req.targetUserId != null) {
          await UserService.addCredits(req.targetUserId!, req.amount);
        } else if (req.type == 'slot_increase' && req.classId != null) {
          final cls = await ClassService.getClass(req.classId!);
          if (cls != null) {
            final sessionDate = req.sessionDate;
            if (sessionDate != null) {
              // Temporary override — does NOT change the permanent groupSize
              final newCap =
                  (int.tryParse(cls.groupSize) ?? 0) + req.amount;
              await FirebaseFirestore.instance
                  .collection('classes')
                  .doc(req.classId)
                  .update({'sessionSlotOverrides.$sessionDate': newCap});
              // Log it
              await FirebaseFirestore.instance
                  .collection('sessionLogs')
                  .add({
                'type': 'slot_override',
                'classId': req.classId,
                'className': req.className ?? '',
                'sessionDate': sessionDate,
                'extraSlots': req.amount,
                'newCapacity': newCap,
                'requestId': req.id,
                'requestedBy': req.requestedByName,
                'createdAt': Timestamp.now(),
              });
              // Pull in anyone waiting for this exact session, up to the
              // number of newly opened slots
              await WaitingListService.admitFromWaitingList(
                classId: req.classId!,
                bookingDate: DateTime.parse(sessionDate),
                bookingTime: cls.startTime,
                className: req.className ?? cls.mode,
                count: req.amount,
              );
            } else {
              // Legacy request without sessionDate — still do permanent update
              await ClassService.updateGroupSize(
                  req.classId!, (int.tryParse(cls.groupSize) ?? 0) + req.amount);
            }
          }
        }
      }

      // Resolved requests don't stay in Firestore — archive to the Sheet's
      // ActivityLog, then remove the Firestore record entirely. If the
      // archive write fails, keep the Firestore record (status-flipped)
      // instead of losing the only copy of what happened.
      final typeLabel = switch (req.type) {
        'credit_request' => 'Credit Request',
        'appointment_booking' => 'Appointment Booking',
        _ => 'Slot Increase',
      };
      // appointment_booking's sessionDate holds a weekday label ("Monday"),
      // not a real ISO date — only session_cancel/slot_increase's
      // sessionDate is DateTime.parse-able.
      final isAppointment = req.type == 'appointment_booking';
      final archived = await ConfigService.logActivityEvent(
        eventType: '$typeLabel ${approved ? 'Approved' : 'Rejected'}',
        classId: req.classId ?? '',
        className: req.className ?? '',
        sessionDate: (!isAppointment && req.sessionDate != null)
            ? DateTime.parse(req.sessionDate!)
            : req.createdAt,
        sessionTime: '',
        userId: req.requestedBy,
        userName: req.requestedByName,
        bookedByRole: 'trainer',
        creditsUsed: req.amount,
        bookingId: req.id ?? '',
        note: req.targetUserName != null
            ? 'For client: ${req.targetUserName}. ${req.note}'
            : req.note,
      );

      // Resolved requests stay in Firestore (status-flipped, never deleted)
      // so they show up under Requests > Resolved — the Sheet archive above
      // is an additional audit trail (Activity Log), not a replacement.
      await FirebaseFirestore.instance
          .collection('adminRequests')
          .doc(req.id)
          .update({
        'status': approved ? 'approved' : 'rejected',
        'resolvedAt': Timestamp.now(),
        'resolvedBy': adminUid,
      });

      unawaited(RequestNotificationService.notifyRequesterOfResolution(
        requesterUid: req.requestedBy,
        typeLabel: typeLabel,
        approved: approved,
      ));

      if (mounted) {
        AppToast.success(
            context,
            approved
                ? 'Request approved'
                : 'Request rejected'
                    '${archived ? '' : ' (Activity Log archive failed — request still resolved)'}');
      }
    } catch (e) {
      if (mounted) AppToast.error(context, 'Failed: ${e.toString()}');
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  // ── Approve cancellation (session_cancel) ─────────────────────────────────

  Future<void> _approveSessionCancel() async {
    setState(() => _processing = true);
    try {
      final adminUid = FirebaseAuth.instance.currentUser?.uid ?? '';

      if (req.classId != null && req.sessionDate != null) {
        final parts = req.sessionDate!.split('-');
        if (parts.length == 3) {
          final date = DateTime(
              int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
          final end = date.add(const Duration(days: 1));

          // Fetch all bookings for the class, filter session date in Dart
          final allSnap = await FirebaseFirestore.instance
              .collection('bookings')
              .where('classId', isEqualTo: req.classId)
              .get();
          final sessionDocs = allSnap.docs.where((d) {
            final data = d.data();
            if (data['status'] == 'cancelled_by_trainer') return false;
            final bd = data['bookingDate'];
            if (bd == null) return false;
            final dt = (bd as Timestamp).toDate();
            return !dt.isBefore(date) && dt.isBefore(end);
          }).toList();

          // Mark bookings cancelled
          final batch = FirebaseFirestore.instance.batch();
          for (final doc in sessionDocs) {
            batch.update(doc.reference, {'status': 'cancelled_by_trainer'});
          }
          await batch.commit();

          for (final doc in sessionDocs) {
            final data = doc.data();
            final uid = data['userId']?.toString() ?? '';
            final bd = (data['bookingDate'] as Timestamp).toDate();
            unawaited(() async {
              final userDoc = await FirebaseFirestore.instance
                  .collection('users')
                  .doc(uid)
                  .get();
              final userName = userDoc.data()?['name']?.toString() ?? uid;
              await ConfigService.logActivityEvent(
                eventType: 'Cancelled by Trainer',
                classId: req.classId!,
                className:
                    req.className ?? data['displayName']?.toString() ?? '',
                sessionDate: bd,
                sessionTime: data['bookingTime']?.toString() ?? '',
                userId: uid,
                userName: userName,
                bookedByRole: data['bookedByRole']?.toString() ?? 'client',
                creditsUsed: data['creditsUsed'] as int? ?? 1,
                bookingId: doc.id,
              );
            }());
          }

          // Refund credits in parallel
          final refunds = <Future>[];
          for (final doc in sessionDocs) {
            final uid = doc['userId'] as String?;
            final credits = doc['creditsUsed'] as int? ?? 1;
            if (uid != null && credits > 0) {
              refunds.add(UserService.addCredits(uid, credits));
            }
          }
          if (refunds.isNotEmpty) await Future.wait(refunds);

          // Notify clients
          if (sessionDocs.isNotEmpty) {
            await NotificationService.showSessionCancelApproved(
                req.className ?? 'session');
          }
        }
      }

      // Mark the session date as cancelled on the class document
      if (req.classId != null && req.sessionDate != null) {
        // Fetch class to check occurrence type
        final clsSnap = await FirebaseFirestore.instance
            .collection('classes')
            .doc(req.classId)
            .get();
        final isOnce = (clsSnap.data()?['occurrence'] as String?) == 'once';

        await FirebaseFirestore.instance
            .collection('classes')
            .doc(req.classId)
            .update(isOnce
                // One-off class: deactivate entirely so it disappears everywhere
                ? {'isActive': false, 'updatedAt': FieldValue.serverTimestamp()}
                // Recurring class: only block that specific date
                : {
                    'cancelledDates':
                        FieldValue.arrayUnion([req.sessionDate]),
                    'updatedAt': FieldValue.serverTimestamp(),
                  });

        // Write audit log
        await FirebaseFirestore.instance.collection('sessionLogs').add({
          'type': 'session_cancelled',
          'classId': req.classId,
          'className': req.className ?? '',
          'coach': req.requestedByName,
          'sessionDate': req.sessionDate,
          'cancelledAt': Timestamp.now(),
          'cancelledBy': adminUid,
          'reason': 'trainer_request',
          'requestId': req.id,
          'classDeactivated': isOnce,
        });
      }

      final archived = await ConfigService.logActivityEvent(
        eventType: 'Session Cancel Request Approved',
        classId: req.classId ?? '',
        className: req.className ?? '',
        sessionDate: req.sessionDate != null
            ? DateTime.parse(req.sessionDate!)
            : req.createdAt,
        sessionTime: '',
        userId: req.requestedBy,
        userName: req.requestedByName,
        bookedByRole: 'trainer',
        creditsUsed: 0,
        bookingId: req.id ?? '',
        note: req.note,
      );

      await FirebaseFirestore.instance
          .collection('adminRequests')
          .doc(req.id)
          .update({
        'status': 'approved_cancel',
        'resolvedAt': Timestamp.now(),
        'resolvedBy': adminUid,
      });

      unawaited(RequestNotificationService.notifyRequesterOfResolution(
        requesterUid: req.requestedBy,
        typeLabel: 'Session Cancellation Request',
        approved: true,
      ));

      if (mounted) {
        AppToast.success(
            context,
            'Cancellation approved — bookings cancelled & credits refunded'
            '${archived ? '' : ' (Activity Log archive failed — request still resolved)'}');
      }
    } catch (e, st) {
      debugPrint('_approveSessionCancel: $e\n$st');
      if (mounted) AppToast.error(context, 'Failed: ${e.toString()}');
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  // ── Reassign trainer (session_cancel) ─────────────────────────────────────

  Future<void> _reassignTrainer() async {
    // Load coaches then show picker
    List<UserModel> coaches;
    try {
      coaches = await ClassService.getCoaches();
    } catch (e) {
      if (mounted) AppToast.error(context, 'Could not load trainers');
      return;
    }
    if (!mounted) return;

    final selected = await showDialog<UserModel>(
      context: context,
      builder: (ctx) => _TrainerPickerDialog(
        coaches: coaches,
        currentCoach: req.requestedByName,
      ),
    );
    if (selected == null || !mounted) return;

    setState(() => _processing = true);
    try {
      final adminUid = FirebaseAuth.instance.currentUser?.uid ?? '';

      // Update class coach permanently
      if (req.classId != null) {
        await ClassService.updateCoach(req.classId!, selected.name);
      }

      // Notify old trainer they've been removed
      await NotificationService.showTrainerRemoved(req.className ?? '');
      // Notify new trainer they've been assigned
      await NotificationService.showTrainerAssigned(
          req.className ?? '', req.sessionDate ?? '');

      final archived = await ConfigService.logActivityEvent(
        eventType: 'Session Reassigned',
        classId: req.classId ?? '',
        className: req.className ?? '',
        sessionDate: req.sessionDate != null
            ? DateTime.parse(req.sessionDate!)
            : req.createdAt,
        sessionTime: '',
        userId: req.requestedBy,
        userName: req.requestedByName,
        bookedByRole: 'trainer',
        creditsUsed: 0,
        bookingId: req.id ?? '',
        note: 'Reassigned to ${selected.name}',
      );

      await FirebaseFirestore.instance
          .collection('adminRequests')
          .doc(req.id)
          .update({
        'status': 'reassigned',
        'resolvedAt': Timestamp.now(),
        'resolvedBy': adminUid,
        'newTrainer': selected.name,
      });

      unawaited(RequestNotificationService.notifyRequesterOfResolution(
        requesterUid: req.requestedBy,
        typeLabel: 'Session Cancellation Request',
        approved: true,
        outcomeLabel: 'Reassigned',
        note: 'Reassigned to ${selected.name}',
      ));

      if (mounted) {
        AppToast.success(
            context,
            'Session reassigned to ${selected.name}'
            '${archived ? '' : ' (Activity Log archive failed — request still resolved)'}');
      }
    } catch (e, st) {
      debugPrint('_reassignTrainer: $e\n$st');
      if (mounted) AppToast.error(context, 'Failed: ${e.toString()}');
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  // ── Info row helper ────────────────────────────────────────────────────────

  Widget _info(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text('$label:',
                style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isPending = req.status == 'pending';
    final isSessionCancel = req.type == 'session_cancel';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: isPending
                ? const Color(0xFFFFAB40).withValues(alpha: 0.4)
                : AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title + status badge
          Row(
            children: [
              Expanded(
                child: Text(
                  _typeLabel,
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _statusColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _statusLabel,
                  style: TextStyle(
                      fontSize: 10,
                      color: _statusColor,
                      fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Info rows — vary by type
          if (isSessionCancel) ...[
            _info('Trainer', req.requestedByName),
            _info('Class', req.className ?? '—'),
            _info('Session Date', req.sessionDate ?? '—'),
            if (req.newTrainer != null) _info('New Trainer', req.newTrainer!),
          ] else if (req.type == 'credit_request') ...[
            _info('Trainer', req.requestedByName),
            _info('Client', req.targetUserName ?? '—'),
            _info('Credits requested', '${req.amount}'),
          ] else if (req.type == 'appointment_booking') ...[
            _info('Client', req.requestedByName),
            _info('Appointment', req.className ?? '—'),
            _info('Day', req.sessionDate ?? '—'),
          ] else ...[
            _info('Trainer', req.requestedByName),
            _info('Class', req.className ?? '—'),
            _info('Extra slots requested', '${req.amount}'),
          ],

          if (req.note.isNotEmpty) ...[
            const SizedBox(height: 3),
            _info('Note', req.note),
          ],

          // Action buttons — only for pending requests
          if (isPending) ...[
            const SizedBox(height: 14),
            if (_processing)
              const Center(
                  child: SizedBox(
                      height: 24,
                      width: 24,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppColors.primary)))
            else if (isSessionCancel)
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _approveSessionCancel,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF00D4AA),
                        side: const BorderSide(color: Color(0xFF00D4AA)),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Text('Approve Cancel'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _reassignTrainer,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Text('Reassign Trainer'),
                    ),
                  ),
                ],
              )
            else
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _resolve(false),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.error,
                        side: BorderSide(
                            color: AppColors.error.withValues(alpha: 0.5)),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Text('Reject'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => _resolve(true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00D4AA),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Text('Approve'),
                    ),
                  ),
                ],
              ),
          ],
        ],
      ),
    );
  }
}

// ── Trainer picker dialog ─────────────────────────────────────────────────────

class _TrainerPickerDialog extends StatelessWidget {
  final List<UserModel> coaches;
  final String currentCoach;

  const _TrainerPickerDialog(
      {required this.coaches, required this.currentCoach});

  @override
  Widget build(BuildContext context) {
    final available =
        coaches.where((c) => c.name != currentCoach).toList();

    return AlertDialog(
      backgroundColor: AppColors.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: const Text('Assign New Trainer',
          style: TextStyle(
              color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
      content: SizedBox(
        width: double.maxFinite,
        child: available.isEmpty
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text('No other trainers available.',
                    style: TextStyle(color: AppColors.textSecondary)),
              )
            : ListView.separated(
                shrinkWrap: true,
                itemCount: available.length,
                separatorBuilder: (_, __) =>
                    const Divider(height: 1, color: AppColors.divider),
                itemBuilder: (ctx, i) {
                  final coach = available[i];
                  return ListTile(
                    leading: const CircleAvatar(
                      backgroundColor: Color(0xFF1A1A2E),
                      child: Icon(Icons.person_outline,
                          color: AppColors.primary, size: 20),
                    ),
                    title: Text(coach.name,
                        style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w600)),
                    subtitle: Text(coach.role,
                        style: const TextStyle(
                            color: AppColors.textMuted, fontSize: 12)),
                    onTap: () => Navigator.pop(ctx, coach),
                  );
                },
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

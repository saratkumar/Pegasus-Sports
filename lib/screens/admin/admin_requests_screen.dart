import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../models/admin_request_model.dart';
import '../../services/user_service.dart';
import '../../services/class_service.dart';
import '../../utils/app_colors.dart';
import '../../utils/app_toast.dart';

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
        title: const Text('Requests'),
        bottom: TabBar(
          controller: _tab,
          indicatorColor: AppColors.primary,
          labelColor: AppColors.textPrimary,
          unselectedLabelColor: AppColors.textMuted,
          tabs: const [
            Tab(text: 'Pending'),
            Tab(text: 'Resolved'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          _RequestList(statusFilter: 'pending'),
          _RequestList(statusFilter: null, excludePending: true),
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
    Query query = FirebaseFirestore.instance
        .collection('adminRequests')
        .orderBy('createdAt', descending: true);

    if (statusFilter != null) {
      query = query.where('status', isEqualTo: statusFilter);
    }

    return StreamBuilder<QuerySnapshot>(
      stream: query.snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(
              child: CircularProgressIndicator(color: AppColors.primary));
        }
        var docs = snap.data?.docs ?? [];
        if (excludePending) {
          docs = docs
              .where((d) => (d['status'] as String?) != 'pending')
              .toList();
        }
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

class _RequestCard extends StatelessWidget {
  final AdminRequestModel request;
  const _RequestCard({required this.request});

  @override
  Widget build(BuildContext context) {
    final isPending = request.status == 'pending';
    final statusColor = request.status == 'approved'
        ? const Color(0xFF00D4AA)
        : request.status == 'rejected'
            ? AppColors.error
            : const Color(0xFFFFAB40);

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
          Row(
            children: [
              Expanded(
                child: Text(
                  request.type == 'credit_request'
                      ? 'Credit Request'
                      : 'Slot Increase Request',
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  request.status.toUpperCase(),
                  style: TextStyle(
                      fontSize: 10,
                      color: statusColor,
                      fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (request.type == 'credit_request') ...[
            _info('Trainer', request.requestedByName),
            _info('Client', request.targetUserName ?? '—'),
            _info('Credits requested', '${request.amount}'),
          ] else ...[
            _info('Trainer', request.requestedByName),
            _info('Class', request.className ?? '—'),
            _info('Extra slots requested', '${request.amount}'),
          ],
          if (request.note.isNotEmpty) ...[
            const SizedBox(height: 6),
            _info('Note', request.note),
          ],
          if (isPending) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _resolve(context, false),
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
                    onPressed: () => _resolve(context, true),
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

  Widget _info(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text('$label:',
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textMuted)),
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

  Future<void> _resolve(BuildContext context, bool approved) async {
    final adminUid = FirebaseAuth.instance.currentUser?.uid ?? '';

    final update = <String, dynamic>{
      'status': approved ? 'approved' : 'rejected',
      'resolvedAt': Timestamp.now(),
      'resolvedBy': adminUid,
    };

    await FirebaseFirestore.instance
        .collection('adminRequests')
        .doc(request.id)
        .update(update);

    if (approved) {
      if (request.type == 'credit_request' &&
          request.targetUserId != null) {
        await UserService.addCredits(
            request.targetUserId!, request.amount);
      } else if (request.type == 'slot_increase' &&
          request.classId != null) {
        final cls = await ClassService.getClass(request.classId!);
        if (cls != null) {
          final current = int.tryParse(cls.groupSize) ?? 0;
          await ClassService.updateGroupSize(
              request.classId!, current + request.amount);
        }
      }
    }

    if (context.mounted) {
      AppToast.success(
          context, approved ? 'Request approved' : 'Request rejected');
    }
  }
}

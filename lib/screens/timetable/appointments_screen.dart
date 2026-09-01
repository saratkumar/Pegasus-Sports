import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../models/admin_request_model.dart';
import '../../models/appointment_model.dart';
import '../../services/appointment_service.dart';
import '../../utils/app_colors.dart';
import '../../utils/app_toast.dart';
import '../../utils/error_reporter.dart';

/// One-on-one appointment slots (e.g. personal training). Booking a slot
/// reserves it as pending — a trainer/admin must acknowledge it (see
/// admin_requests_screen.dart) before it's confirmed. Only one active
/// request can hold a slot at a time.
class AppointmentsScreen extends StatelessWidget {
  const AppointmentsScreen({super.key});

  Future<void> _book(BuildContext context, AppointmentSlotModel slot) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      await AppointmentService.requestBooking(
        slot: slot,
        userId: user.uid,
        userName: user.displayName ?? user.email ?? 'Client',
      );
      if (context.mounted) {
        AppToast.success(context,
            'Requested — waiting for the coach to confirm ${slot.appointmentName}');
      }
    } catch (e, st) {
      if (context.mounted) {
        reportError(
          context,
          e,
          st,
          userMessage: friendlyMessage(
              e, 'Could not book this appointment. Please try again.'),
          reason: 'Appointment booking failed',
        );
      }
    }
  }

  Future<void> _cancel(BuildContext context, AdminRequestModel req) async {
    if (req.id == null || req.classId == null) return;
    await AppointmentService.cancelMyRequest(req.id!, req.classId!);
    if (context.mounted) AppToast.success(context, 'Request cancelled');
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    return Scaffold(
      appBar: AppBar(title: const Text('Appointments')),
      body: uid.isEmpty
          ? const SizedBox()
          : StreamBuilder<List<AppointmentSlotModel>>(
              stream: AppointmentService.streamSlots(),
              builder: (context, slotSnap) {
                if (slotSnap.connectionState == ConnectionState.waiting &&
                    !slotSnap.hasData) {
                  return const Center(
                      child: CircularProgressIndicator(color: AppColors.primary));
                }
                final slots =
                    (slotSnap.data ?? []).where((s) => s.isActive).toList();

                return StreamBuilder<List<AdminRequestModel>>(
                  stream: AppointmentService.streamMyRequests(uid),
                  builder: (context, reqSnap) {
                    final myRequests = reqSnap.data ?? [];

                    if (slots.isEmpty) {
                      return const Center(
                        child: Text('No appointment slots available',
                            style: TextStyle(color: AppColors.textSecondary)),
                      );
                    }

                    return ListView.builder(
                      padding: const EdgeInsets.all(14),
                      itemCount: slots.length,
                      itemBuilder: (context, i) {
                        final slot = slots[i];
                        // Ignore resolved-and-rejected requests here — they
                        // don't block re-booking and shouldn't show as
                        // "yours" on a now-free slot.
                        final matches = myRequests.where((r) =>
                            r.classId == slot.id &&
                            (r.status == 'pending' || r.status == 'approved'));
                        final myRequest =
                            matches.isEmpty ? null : matches.first;
                        return _SlotCard(
                          slot: slot,
                          myRequest: myRequest,
                          onBook: () => _book(context, slot),
                          onCancel: myRequest != null
                              ? () => _cancel(context, myRequest)
                              : null,
                        );
                      },
                    );
                  },
                );
              },
            ),
    );
  }
}

class _SlotCard extends StatelessWidget {
  final AppointmentSlotModel slot;
  final AdminRequestModel? myRequest;
  final VoidCallback onBook;
  final VoidCallback? onCancel;

  const _SlotCard({
    required this.slot,
    required this.myRequest,
    required this.onBook,
    required this.onCancel,
  });

  ({String label, Color color}) get _status {
    if (myRequest != null && myRequest!.status == 'pending') {
      return (label: 'Your request is pending', color: const Color(0xFFFFAB40));
    }
    if (myRequest != null && myRequest!.status == 'approved') {
      return (label: 'Confirmed for you', color: const Color(0xFF00D4AA));
    }
    if (!slot.isFree) {
      return (label: 'Taken', color: AppColors.textMuted);
    }
    return (label: 'Available', color: AppColors.primary);
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    final canBook = slot.isFree && myRequest == null;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(slot.appointmentName,
                      style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary)),
                  const SizedBox(height: 3),
                  Text('${slot.coach} · ${slot.day} · ${slot.time}',
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textSecondary)),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: status.color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(status.label,
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: status.color)),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            if (onCancel != null)
              OutlinedButton(
                onPressed: onCancel,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.error,
                  side: BorderSide(color: AppColors.error.withValues(alpha: 0.5)),
                ),
                child: const Text('Cancel'),
              )
            else
              ElevatedButton(
                onPressed: canBook ? onBook : null,
                child: const Text('Book'),
              ),
          ],
        ),
      ),
    );
  }
}

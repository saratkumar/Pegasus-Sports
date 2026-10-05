import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/admin_request_model.dart';
import '../models/appointment_model.dart';
import '../models/dependent_model.dart';
import 'request_notification_service.dart';

/// Backs the Appointments feature (one-on-one slots). The slot catalog
/// lives in Firestore (admin-managed, replacing the old public Google
/// Sheet CSV). Booking a slot doesn't confirm it immediately — it creates
/// a 'appointment_booking' adminRequests doc that a trainer/admin must
/// acknowledge, same review flow as credit/slot-increase requests (see
/// admin_requests_screen.dart).
class AppointmentService {
  static final _slotsCol =
      FirebaseFirestore.instance.collection('appointmentSlots');
  static final _requestsCol =
      FirebaseFirestore.instance.collection('adminRequests');

  // ── Slot catalog (admin CRUD) ───────────────────────────────────────────

  static Stream<List<AppointmentSlotModel>> streamSlots() {
    return _slotsCol
        .snapshots()
        .map((s) => s.docs.map(AppointmentSlotModel.fromFirestore).toList());
  }

  static Future<String> createSlot(AppointmentSlotModel slot) async {
    final ref = await _slotsCol.add({
      ...slot.toFirestore(),
      'activeRequestId': null,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  static Future<void> updateSlot(String id, AppointmentSlotModel slot) async {
    await _slotsCol.doc(id).update(slot.toFirestore());
  }

  static Future<void> deleteSlot(String id) async {
    await _slotsCol.doc(id).delete();
  }

  /// Safety valve for admin — force a slot back to free (e.g. a stuck or
  /// no-show booking) without going through the normal reject flow.
  static Future<void> forceRelease(String slotId) async {
    await _slotsCol.doc(slotId).update({'activeRequestId': null});
  }

  // ── Booking ──────────────────────────────────────────────────────────────

  /// Reserves [slotId] as pending. Transactional against the slot doc's
  /// activeRequestId field so two clients tapping "Book" on the same slot
  /// at once can't both succeed. [attendee] is the parent's child profile
  /// the appointment is for (null = the account holder).
  static Future<void> requestBooking({
    required AppointmentSlotModel slot,
    required String userId,
    required String userName,
    DependentModel? attendee,
  }) async {
    final slotRef = _slotsCol.doc(slot.id);
    final requestRef = _requestsCol.doc();
    await FirebaseFirestore.instance.runTransaction((tx) async {
      final slotSnap = await tx.get(slotRef);
      if (!slotSnap.exists) throw Exception('This slot no longer exists');
      final data = slotSnap.data() as Map<String, dynamic>;
      if (data['activeRequestId'] != null) {
        throw Exception('This slot is no longer available');
      }
      final request = AdminRequestModel(
        type: 'appointment_booking',
        requestedBy: userId,
        requestedByName: userName,
        classId: slot.id,
        className: slot.appointmentName,
        sessionDate: slot.day,
        amount: 0,
        note: 'Coach: ${slot.coach} · ${slot.time}',
        createdAt: DateTime.now(),
        attendeeId: attendee?.id,
        attendeeName: attendee?.name,
      );
      tx.set(requestRef, request.toFirestore());
      tx.update(slotRef, {'activeRequestId': requestRef.id});
    });
    unawaited(RequestNotificationService.notifyAdminsOfNewRequest(
      typeLabel: 'Appointment Booking Request',
      requesterName: userName,
      summary: '${slot.appointmentName} · ${slot.day} ${slot.time} · Coach: ${slot.coach}'
          '${attendee == null ? '' : ' · for junior ${attendee.name}'}',
    ));
  }

  /// Client cancelling their own still-pending request — frees the slot.
  static Future<void> cancelMyRequest(
      String requestId, String slotId) async {
    final slotRef = _slotsCol.doc(slotId);
    final requestRef = _requestsCol.doc(requestId);
    await FirebaseFirestore.instance.runTransaction((tx) async {
      tx.delete(requestRef);
      tx.update(slotRef, {'activeRequestId': null});
    });
  }

  static Stream<List<AdminRequestModel>> streamMyRequests(String userId) {
    return _requestsCol
        .where('type', isEqualTo: 'appointment_booking')
        .where('requestedBy', isEqualTo: userId)
        .snapshots()
        .map((s) => s.docs.map(AdminRequestModel.fromFirestore).toList());
  }
}

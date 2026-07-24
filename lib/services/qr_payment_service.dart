import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/qr_payment_request_model.dart';
import '../models/user_model.dart';
import 'config_service.dart';
import 'invoice_service.dart';
import 'request_notification_service.dart';
import 'user_service.dart';

/// Backs the "pay via business QR code" flow: user scans the admin's
/// configured QR (outside the app, in their own banking app), taps
/// "I've Paid", and that queues a request an admin must manually confirm
/// before the membership activates — there's no automated way to verify a
/// QR/bank-transfer payment actually landed, so admin confirmation is the
/// trust boundary here, not Stripe.
class QrPaymentService {
  static final _configDoc =
      FirebaseFirestore.instance.collection('appMeta').doc('paymentQr');
  static final _requestsCol =
      FirebaseFirestore.instance.collection('qrPaymentRequests');

  // ── QR config (admin-managed) ───────────────────────────────────────────

  static Stream<Map<String, dynamic>?> streamConfig() {
    return _configDoc.snapshots().map((d) => d.data());
  }

  static Future<void> setConfig({
    required String imageUrl,
    required String caption,
  }) async {
    await _configDoc.set({
      'imageUrl': imageUrl,
      'caption': caption,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // ── Requests ─────────────────────────────────────────────────────────────

  static Future<void> submitRequest({
    required String planName,
    required int credits,
    required double amount,
    required int validityDays,
    String note = '',
  }) async {
    final user = await UserService.getCurrentUser();
    if (user == null) throw Exception('Not signed in');

    final request = QrPaymentRequestModel(
      userId: user.uid,
      userName: user.name,
      userEmail: user.email,
      planName: planName,
      credits: credits,
      amount: amount,
      validityDays: validityDays,
      note: note,
      createdAt: DateTime.now(),
    );
    await _requestsCol.add(request.toFirestore());

    await RequestNotificationService.notifyAdminsOfNewRequest(
      typeLabel: 'QR Payment Confirmation',
      requesterName: user.name,
      summary: '$planName · $amount SGD',
    );
  }

  static Stream<List<QrPaymentRequestModel>> streamPending() {
    return _requestsCol
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .map((s) => s.docs.map(QrPaymentRequestModel.fromFirestore).toList()
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt)));
  }

  static Stream<List<QrPaymentRequestModel>> streamMyRequests(String uid) {
    return _requestsCol
        .where('userId', isEqualTo: uid)
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .map((s) => s.docs.map(QrPaymentRequestModel.fromFirestore).toList());
  }

  /// Grants the membership, records the transaction, and emails the
  /// invoice (with or without [paymentRef] — see cash payment's identical
  /// "don't fabricate a reference" rule).
  static Future<void> approve(
    QrPaymentRequestModel req, {
    String? paymentRef,
  }) async {
    final adminUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final now = DateTime.now();
    final endDate = req.validityDays > 0
        ? now.add(Duration(days: req.validityDays))
        : now.add(const Duration(days: 365));

    await UserService.purchaseMembership(
      req.userId,
      MembershipEntry(
        planName: req.planName,
        credits: req.credits,
        startDate: now,
        endDate: endDate,
        purchasedAt: now,
      ),
    );

    final txRef = FirebaseFirestore.instance.collection('transactions').doc();
    final internalRef = 'qr_${txRef.id}';
    final invoiceNumber = InvoiceService.generateInvoiceNumber(internalRef);

    await txRef.set({
      'invoiceNumber': invoiceNumber,
      'paymentIntentId': internalRef,
      if (paymentRef != null && paymentRef.isNotEmpty) 'clientPaymentRef': paymentRef,
      'paymentMethod': 'qr',
      'clientUid': req.userId,
      'clientName': req.userName,
      'clientEmail': req.userEmail,
      'planName': req.planName,
      'credits': req.credits,
      'amount': req.amount,
      'currency': req.currency,
      'validityDays': req.validityDays,
      'createdAt': FieldValue.serverTimestamp(),
    });

    final (sheetRecorded, emailSent, invoiceError) =
        await InvoiceService.processWithInvoice(
      invoiceNumber: invoiceNumber,
      paymentIntentId: internalRef,
      clientName: req.userName,
      clientEmail: req.userEmail,
      planName: req.planName,
      credits: req.credits,
      amount: req.amount,
      currency: req.currency,
      displayPaymentRef: paymentRef,
      validityDays: req.validityDays,
    );
    if (sheetRecorded && emailSent) {
      // Durably recorded in the Sheet and the customer has their invoice —
      // nothing left for Firestore to hold onto.
      await txRef.delete();
    } else {
      await txRef.update({
        'invoiceEmailSent': emailSent,
        'sheetRecorded': sheetRecorded,
        if (invoiceError != null) 'invoiceEmailError': invoiceError,
      });
    }

    // Once resolved, this doc's job is done — archive it to the Sheet's
    // ActivityLog (same pattern as credit/slot-increase requests) and
    // remove it from Firestore rather than leaving it there forever. The
    // transaction record lives on in the Sheet's Transactions tab (and, if
    // the Sheet write above failed, in the `transactions` collection as a
    // fallback), so nothing about the payment history is lost.
    final archived = await ConfigService.logActivityEvent(
      eventType: 'QR Payment Approved',
      classId: '',
      className: req.planName,
      sessionDate: DateTime.now(),
      sessionTime: '',
      userId: req.userId,
      userName: req.userName,
      bookedByRole: 'client',
      creditsUsed: req.credits,
      note: '${req.currency} ${req.amount.toStringAsFixed(2)}'
          '${paymentRef != null && paymentRef.isNotEmpty ? ' · Ref: $paymentRef' : ''}',
    );
    if (archived) {
      await _requestsCol.doc(req.id).delete();
    } else {
      await _requestsCol.doc(req.id).update({
        'status': 'approved',
        'resolvedAt': Timestamp.now(),
        'resolvedBy': adminUid,
        if (paymentRef != null && paymentRef.isNotEmpty) 'paymentRef': paymentRef,
      });
    }

    await RequestNotificationService.notifyRequesterOfResolution(
      requesterUid: req.userId,
      typeLabel: 'QR Payment (${req.planName})',
      approved: true,
    );
  }

  static Future<void> reject(QrPaymentRequestModel req) async {
    final adminUid = FirebaseAuth.instance.currentUser?.uid ?? '';

    final archived = await ConfigService.logActivityEvent(
      eventType: 'QR Payment Rejected',
      classId: '',
      className: req.planName,
      sessionDate: DateTime.now(),
      sessionTime: '',
      userId: req.userId,
      userName: req.userName,
      bookedByRole: 'client',
      creditsUsed: req.credits,
      note: '${req.currency} ${req.amount.toStringAsFixed(2)}',
    );
    if (archived) {
      await _requestsCol.doc(req.id).delete();
    } else {
      await _requestsCol.doc(req.id).update({
        'status': 'rejected',
        'resolvedAt': Timestamp.now(),
        'resolvedBy': adminUid,
      });
    }

    await RequestNotificationService.notifyRequesterOfResolution(
      requesterUid: req.userId,
      typeLabel: 'QR Payment (${req.planName})',
      approved: false,
    );
  }
}

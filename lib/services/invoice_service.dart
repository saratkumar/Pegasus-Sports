import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'config_service.dart';
import 'invoice_pdf_service.dart';

class InvoiceService {
  /// Derives the invoice number from the Stripe [paymentIntentId] (globally
  /// unique) instead of a timestamp modulo, which previously repeated every
  /// 10 seconds and could hand two different payments the same number.
  static String generateInvoiceNumber(String paymentIntentId) {
    final now = DateTime.now();
    final ref = paymentIntentId.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
    final suffix =
        (ref.length >= 8 ? ref.substring(ref.length - 8) : ref.padLeft(8, '0'))
            .toUpperCase();
    return 'PSAS-'
        '${now.year}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}'
        '-$suffix';
  }

  /// Records the transaction in the Google Sheet Transactions tab and emails
  /// the invoice as a PDF attachment. Both outcomes are reported back —
  /// [sheetRecorded] and [emailSent] — so the caller can decide whether it's
  /// safe to delete the Firestore `transactions` doc (only once the Sheet is
  /// the durable copy AND the customer actually got their invoice) instead
  /// of losing the only record of a failed write. [error] carries the raw
  /// email-send failure detail, if any.
  ///
  /// [recordToSheet]/[sendEmail] let a retry (see TransactionsScreen's
  /// "Needs Attention" list) redo only whichever half failed last time —
  /// pass `false` for the half that already succeeded, or a retry would
  /// write a duplicate row to the Sheet / send a second email.
  static Future<(bool sheetRecorded, bool emailSent, String? error)>
      processWithInvoice({
    required String invoiceNumber,
    required String paymentIntentId,
    required String clientName,
    required String clientEmail,
    required String planName,
    required int credits,
    required double amount,
    required String currency,
    // What actually prints as "Payment Ref" on the client-facing invoice —
    // a real Stripe ID, or an admin-entered reference for cash payments.
    // Null omits the line entirely rather than showing an internal,
    // system-generated id that means nothing to the client.
    String? displayPaymentRef,
    String? couponCode,
    double? originalAmount,
    bool recordToSheet = true,
    bool sendEmail = true,
  }) async {
    final now = DateTime.now();
    final dateStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    var sheetRecorded = !recordToSheet;
    var emailSent = !sendEmail;
    String? error;
    final tasks = <Future>[];
    if (recordToSheet) {
      tasks.add(() async {
        try {
          await _recordToSheet(
            invoiceNumber: invoiceNumber,
            paymentIntentId: paymentIntentId,
            clientName: clientName,
            clientEmail: clientEmail,
            planName: planName,
            credits: credits,
            amount: amount,
            currency: currency,
            date: dateStr,
          );
          sheetRecorded = true;
        } catch (_) {
          // Reported via the returned flag — no rethrow.
        }
      }());
    }
    if (sendEmail) {
      tasks.add(() async {
        try {
          await _sendEmail(
            invoiceNumber: invoiceNumber,
            clientName: clientName,
            clientEmail: clientEmail,
            planName: planName,
            credits: credits,
            amount: amount,
            currency: currency,
            displayPaymentRef: displayPaymentRef,
            couponCode: couponCode,
            originalAmount: originalAmount,
            date: dateStr,
          );
          emailSent = true;
        } catch (e) {
          error = e.toString();
        }
      }());
    }
    await Future.wait(tasks);
    return (sheetRecorded, emailSent, error);
  }

  static Future<void> _recordToSheet({
    required String invoiceNumber,
    required String paymentIntentId,
    required String clientName,
    required String clientEmail,
    required String planName,
    required int credits,
    required double amount,
    required String currency,
    required String date,
  }) async {
    await ConfigService.recordTransaction(
      invoiceNumber: invoiceNumber,
      paymentIntentId: paymentIntentId,
      clientName: clientName,
      clientEmail: clientEmail,
      planName: planName,
      credits: credits,
      amount: amount,
      currency: currency,
      date: date,
    );
  }

  /// Queues an invoice email — with the PDF invoice as an attachment, not
  /// just details inline in the body — via the Firebase "Trigger Email"
  /// Extension (watches the `mail` collection, sends via Gmail SMTP).
  /// Success here only means the document was queued, not that the email
  /// was actually delivered.
  static Future<void> _sendEmail({
    required String invoiceNumber,
    required String clientName,
    required String clientEmail,
    required String planName,
    required int credits,
    required double amount,
    required String currency,
    String? displayPaymentRef,
    String? couponCode,
    double? originalAmount,
    required String date,
  }) async {
    final refLine = (displayPaymentRef != null && displayPaymentRef.isNotEmpty)
        ? '<p>Payment Ref: $displayPaymentRef</p>'
        : '';
    final pdfBytes = await InvoicePdfService.buildBytes(
      invoiceNumber: invoiceNumber,
      paymentRef: displayPaymentRef,
      clientName: clientName,
      clientEmail: clientEmail,
      planName: planName,
      credits: credits,
      amount: amount,
      currency: currency,
      couponCode: couponCode,
      originalAmount: originalAmount,
    );
    await FirebaseFirestore.instance.collection('mail').add({
      'to': [clientEmail],
      'message': {
        'subject': 'Invoice $invoiceNumber — PSAS',
        'html': '''
          <div style="font-family: sans-serif; color: #0A0A0A;">
            <h2 style="color: #FF7A00;">Invoice $invoiceNumber</h2>
            <p>Date: $date</p>
            <p>Plan: $planName ($credits credits)</p>
            <p>Amount: $currency ${amount.toStringAsFixed(2)}</p>
            $refLine
            <p>Your invoice is attached as a PDF.</p>
            <p>Thank you, $clientName.</p>
            <p style="color: #666666; font-size: 12px;">Questions or clarifications: <a href="mailto:admin.psas@gmail.com">admin.psas@gmail.com</a></p>
          </div>
        ''',
        'attachments': [
          {
            'filename': '$invoiceNumber.pdf',
            'content': base64Encode(pdfBytes),
            'encoding': 'base64',
            'contentType': 'application/pdf',
          },
        ],
      },
    });
  }
}

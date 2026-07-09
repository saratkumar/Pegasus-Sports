import 'package:emailjs/emailjs.dart';
import 'config_service.dart';

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

  /// Records the transaction in the Google Sheet Transactions tab and sends
  /// an invoice email via EmailJS. The Sheet write is best-effort (failures
  /// are swallowed since it's a secondary record), but returns whether the
  /// invoice email itself succeeded — plus the raw error detail on failure —
  /// so the caller can surface a diagnosable message instead of a silent drop.
  static Future<(bool sent, String? error)> processWithInvoice({
    required String invoiceNumber,
    required String paymentIntentId,
    required String clientName,
    required String clientEmail,
    required String planName,
    required int credits,
    required double amount,
    required String currency,
  }) async {
    final now = DateTime.now();
    final dateStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    var emailSent = false;
    String? error;
    await Future.wait([
      _recordToSheet(
        invoiceNumber: invoiceNumber,
        paymentIntentId: paymentIntentId,
        clientName: clientName,
        clientEmail: clientEmail,
        planName: planName,
        credits: credits,
        amount: amount,
        currency: currency,
        date: dateStr,
      ).catchError((_) {}),
      () async {
        try {
          await _sendEmail(
            invoiceNumber: invoiceNumber,
            clientName: clientName,
            clientEmail: clientEmail,
            planName: planName,
            credits: credits,
            amount: amount,
            currency: currency,
            paymentIntentId: paymentIntentId,
            date: dateStr,
          );
          emailSent = true;
        } catch (e) {
          error = e.toString();
        }
      }(),
    ]);
    return (emailSent, error);
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

  static Future<void> _sendEmail({
    required String invoiceNumber,
    required String clientName,
    required String clientEmail,
    required String planName,
    required int credits,
    required double amount,
    required String currency,
    required String paymentIntentId,
    required String date,
  }) async {
    final serviceId = await ConfigService.get('emailjs_service_id');
    final templateId = await ConfigService.get('emailjs_template_id');
    final publicKey = await ConfigService.get('emailjs_public_key');

    await send(
      serviceId,
      templateId,
      {
        'to_name': clientName,
        'to_email': clientEmail,
        'invoice_number': invoiceNumber,
        'invoice_date': date,
        'plan_name': planName,
        'credits': credits.toString(),
        'amount': amount.toStringAsFixed(2),
        'currency': currency,
        'payment_ref': paymentIntentId,
      },
      Options(publicKey: publicKey),
    );
  }
}

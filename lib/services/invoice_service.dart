import 'package:emailjs/emailjs.dart';
import 'config_service.dart';

class InvoiceService {
  static String generateInvoiceNumber() {
    final now = DateTime.now();
    final seq = (now.millisecondsSinceEpoch % 10000).toString().padLeft(4, '0');
    return 'PSAS-'
        '${now.year}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}'
        '-$seq';
  }

  /// Records the transaction in the Google Sheet Transactions tab
  /// and sends an invoice email via EmailJS.
  /// Failures are caught silently so a post-payment error never blocks the user.
  static Future<void> process({
    required String paymentIntentId,
    required String clientName,
    required String clientEmail,
    required String planName,
    required int credits,
    required double amount,
    required String currency,
  }) async {
    final invoiceNumber = generateInvoiceNumber();
    final now = DateTime.now();
    final dateStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    await Future.wait([
      _recordToSheet(
        invoiceNumber: invoiceNumber,
        paymentIntentId: paymentIntentId,
        clientName: clientName,
        clientEmail: clientEmail,
        planName: planName,
        credits: credits,
        amount: amount,
        currency: currency.toUpperCase(),
        date: dateStr,
      ).catchError((_) {}),
      _sendEmail(
        invoiceNumber: invoiceNumber,
        clientName: clientName,
        clientEmail: clientEmail,
        planName: planName,
        credits: credits,
        amount: amount,
        currency: currency.toUpperCase(),
        paymentIntentId: paymentIntentId,
        date: dateStr,
      ).catchError((_) {}),
    ]);
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

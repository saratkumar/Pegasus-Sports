import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

const _supportEmail = 'admin.psas@gmail.com';

/// Builds the PDF invoice document — as raw bytes for emailing as an
/// attachment, or shared via the OS share sheet for a manual download.
class InvoicePdfService {
  static Future<Uint8List> buildBytes({
    required String invoiceNumber,
    String? paymentRef,
    required String clientName,
    required String clientEmail,
    required String planName,
    required int credits,
    required double amount,
    required String currency,
    String? couponCode,
    double? originalAmount,
  }) async {
    final now = DateTime.now();
    final dateStr =
        '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';

    final logoBytes = await rootBundle.load('assets/images/logo.png');
    final logoImage = pw.MemoryImage(logoBytes.buffer.asUint8List());

    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Row(
                    children: [
                      pw.Image(logoImage, width: 36, height: 36),
                      pw.SizedBox(width: 10),
                      pw.Text('PSAS',
                          style: pw.TextStyle(
                              fontSize: 24, fontWeight: pw.FontWeight.bold)),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text('INVOICE',
                          style: pw.TextStyle(
                              fontSize: 18, fontWeight: pw.FontWeight.bold)),
                      pw.Text(invoiceNumber, style: const pw.TextStyle(fontSize: 11)),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 24),
              pw.Text('Date: $dateStr', style: const pw.TextStyle(fontSize: 11)),
              if (paymentRef != null && paymentRef.isNotEmpty) ...[
                pw.SizedBox(height: 4),
                pw.Text('Payment Ref: $paymentRef',
                    style: const pw.TextStyle(fontSize: 11)),
              ],
              pw.SizedBox(height: 20),
              pw.Text('Billed To',
                  style: pw.TextStyle(
                      fontSize: 11, fontWeight: pw.FontWeight.bold)),
              pw.Text(clientName, style: const pw.TextStyle(fontSize: 12)),
              if (clientEmail.isNotEmpty)
                pw.Text(clientEmail, style: const pw.TextStyle(fontSize: 11)),
              pw.SizedBox(height: 24),
              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey400),
                columnWidths: const {
                  0: pw.FlexColumnWidth(3),
                  1: pw.FlexColumnWidth(1),
                  2: pw.FlexColumnWidth(1.5),
                },
                children: [
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                    children: [
                      _cell('Plan', bold: true),
                      _cell('Credits', bold: true),
                      _cell('Amount', bold: true),
                    ],
                  ),
                  pw.TableRow(children: [
                    _cell(planName),
                    _cell('$credits'),
                    _cell('$currency ${(originalAmount ?? amount).toStringAsFixed(2)}'),
                  ]),
                  if (couponCode != null)
                    pw.TableRow(children: [
                      _cell('Coupon: $couponCode'),
                      _cell(''),
                      _cell('- $currency ${((originalAmount ?? amount) - amount).toStringAsFixed(2)}'),
                    ]),
                ],
              ),
              pw.SizedBox(height: 16),
              pw.Align(
                alignment: pw.Alignment.centerRight,
                child: pw.Text('Total: $currency ${amount.toStringAsFixed(2)}',
                    style: pw.TextStyle(
                        fontSize: 14, fontWeight: pw.FontWeight.bold)),
              ),
              pw.SizedBox(height: 32),
              pw.Text('Thank you for your business.',
                  style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey700)),
              pw.SizedBox(height: 4),
              pw.Text('Questions or clarifications: $_supportEmail',
                  style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey700)),
            ],
          );
        },
      ),
    );

    return doc.save();
  }

  /// Manual on-demand download via the OS share sheet — not used by the
  /// automatic purchase flows (those email the PDF as an attachment
  /// instead, see InvoiceService), kept for a future "resend/download"
  /// admin action.
  static Future<void> shareInvoice({
    required String invoiceNumber,
    String? paymentRef,
    required String clientName,
    required String clientEmail,
    required String planName,
    required int credits,
    required double amount,
    required String currency,
    String? couponCode,
    double? originalAmount,
  }) async {
    final bytes = await buildBytes(
      invoiceNumber: invoiceNumber,
      paymentRef: paymentRef,
      clientName: clientName,
      clientEmail: clientEmail,
      planName: planName,
      credits: credits,
      amount: amount,
      currency: currency,
      couponCode: couponCode,
      originalAmount: originalAmount,
    );
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$invoiceNumber.pdf');
    await file.writeAsBytes(bytes);
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'application/pdf')],
      subject: 'Invoice $invoiceNumber',
    );
  }

  static pw.Widget _cell(String text, {bool bold = false}) => pw.Padding(
        padding: const pw.EdgeInsets.all(6),
        child: pw.Text(text,
            style: pw.TextStyle(
                fontSize: 10,
                fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
      );
}

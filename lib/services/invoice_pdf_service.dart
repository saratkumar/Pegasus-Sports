import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

/// Builds a downloadable PDF invoice and opens the OS share sheet so the
/// user can save/send it — used as the primary invoice delivery mechanism
/// instead of depending on the (currently unconfigured) EmailJS email step.
class InvoicePdfService {
  static Future<void> shareInvoice({
    required String invoiceNumber,
    required String paymentRef,
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
                  pw.Text('PSAS',
                      style: pw.TextStyle(
                          fontSize: 24, fontWeight: pw.FontWeight.bold)),
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
              pw.SizedBox(height: 4),
              pw.Text('Payment Ref: $paymentRef',
                  style: const pw.TextStyle(fontSize: 11)),
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
            ],
          );
        },
      ),
    );

    final bytes = await doc.save();
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

import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

const _supportEmail = 'admin.psas@gmail.com';

// Sender is always PSAS itself — fixed business details, not per-invoice data.
const _senderEmail = 'info@psas.sg';
const _senderEntity = 'PEGASUS SPORTS ACADEMY SINGAPORE PTE. LTD.';
const _senderAddress = '471A Upper Serangoon Crescent, #07-378, Hougang Parkview';
const _senderPostalCode = '531471';
const _senderCountry = 'Singapore';
const _senderContactName = 'Andrei Dueck';
const _senderRegNo = '202204061H';
const _taxRateLabel = 'Supply from Non GST registered company (Tax Rate 0%)';

// PayNow / bank details — printed on every invoice as a standing reference
// (this is a receipt, not a bill, but customers still look these up for
// refund/reconciliation purposes).
const _paynowUen = '202204061H';
const _bankName = 'OCBC Bank';
const _bankSwiftCode = 'OCBCSGSG';
const _bankAccountNo = '601797772001-SGD';

const _months = [
  '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// Builds the PDF invoice document — as raw bytes for emailing as an
/// attachment, or shared via the OS share sheet for a manual download.
///
/// This is a post-payment receipt-style invoice (generated only once a
/// purchase has already gone through), so it deliberately omits due date,
/// payment terms, and purchase order no. — fields that only make sense on a
/// bill issued before payment.
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
    int? validityDays,
  }) async {
    final now = DateTime.now();
    final dateStr = '${now.day.toString().padLeft(2, '0')} ${_months[now.month]} ${now.year}';

    final logoBytes = await rootBundle.load('assets/images/logo.png');
    final logoImage = pw.MemoryImage(logoBytes.buffer.asUint8List());

    final unitPrice = originalAmount ?? amount;
    final discount = (originalAmount ?? amount) - amount;
    var description = 'Includes $credits Training Sessions';
    if (validityDays != null && validityDays > 0) {
      description += ', Valid for $validityDays days';
    }
    if (couponCode != null && couponCode.isNotEmpty) {
      description += ' (Coupon: $couponCode)';
    }

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
                  pw.Text('INVOICE',
                      style: pw.TextStyle(
                          fontSize: 22, fontWeight: pw.FontWeight.bold)),
                ],
              ),
              pw.SizedBox(height: 20),
              _sectionBox([
                _kv('Invoice no.', invoiceNumber),
                _kv('Issue date', dateStr),
                _kv('Currency', currency),
                _kv('Tax rate', _taxRateLabel),
                if (paymentRef != null && paymentRef.isNotEmpty)
                  _kv('Payment ref.', paymentRef),
              ]),
              pw.SizedBox(height: 16),
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Expanded(
                    child: _infoColumn('Recipient information', [
                      _kv('Email address', clientEmail),
                      _kv('Entity name', clientName),
                    ]),
                  ),
                  pw.SizedBox(width: 20),
                  pw.Expanded(
                    child: _infoColumn('Sender information', [
                      _kv('Email address', _senderEmail),
                      _kv('Entity name', _senderEntity),
                      _kv('Address', _senderAddress),
                      _kv('Postal code', _senderPostalCode),
                      _kv('Country', _senderCountry),
                      _kv('Contact name', _senderContactName),
                      _kv('Business reg. no.', _senderRegNo),
                    ]),
                  ),
                ],
              ),
              pw.SizedBox(height: 20),
              pw.Text('Details',
                  style: pw.TextStyle(
                      fontSize: 11, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 6),
              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey400),
                columnWidths: const {
                  0: pw.FlexColumnWidth(2.2),
                  1: pw.FlexColumnWidth(3),
                  2: pw.FlexColumnWidth(0.8),
                  3: pw.FlexColumnWidth(0.8),
                  4: pw.FlexColumnWidth(1.3),
                  5: pw.FlexColumnWidth(1.3),
                  6: pw.FlexColumnWidth(1.3),
                },
                children: [
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                    children: [
                      _cell('Part/service no.', bold: true),
                      _cell('Description', bold: true),
                      _cell('UOM', bold: true),
                      _cell('Qty', bold: true),
                      _cell('Unit price', bold: true),
                      _cell('Discount', bold: true),
                      _cell('Total', bold: true),
                    ],
                  ),
                  pw.TableRow(children: [
                    _cell(planName),
                    _cell(description),
                    _cell('unit'),
                    _cell('1.00'),
                    _cell(unitPrice.toStringAsFixed(2)),
                    _cell(discount.toStringAsFixed(2)),
                    _cell(amount.toStringAsFixed(2)),
                  ]),
                ],
              ),
              pw.SizedBox(height: 16),
              pw.Align(
                alignment: pw.Alignment.centerRight,
                child: pw.SizedBox(
                  width: 220,
                  child: pw.Column(
                    children: [
                      _totalRow('Amount before tax', currency, amount),
                      _totalRow('Tax amount', currency, 0),
                      pw.Divider(color: PdfColors.grey400, height: 10),
                      _totalRow('Total amount', currency, amount, bold: true),
                    ],
                  ),
                ),
              ),
              pw.SizedBox(height: 28),
              pw.Text('Payment received in full — thank you, $clientName!',
                  style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey700)),
              pw.SizedBox(height: 4),
              pw.Text('Questions or clarifications: $_supportEmail',
                  style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey700)),
              pw.SizedBox(height: 20),
              pw.Container(
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  color: PdfColors.grey100,
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                ),
                child: pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.BarcodeWidget(
                      data: _payNowQrPayload(),
                      barcode: pw.Barcode.qrCode(),
                      width: 64,
                      height: 64,
                      drawText: false,
                    ),
                    pw.SizedBox(width: 12),
                    pw.Expanded(
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text('PayNow UEN: $_paynowUen',
                              style: pw.TextStyle(
                                  fontSize: 10, fontWeight: pw.FontWeight.bold)),
                          pw.SizedBox(height: 6),
                          pw.Row(
                            children: [
                              _bankDetail('Bank name', _bankName),
                              _bankDetail('Swift code', _bankSwiftCode),
                              _bankDetail('Account no.', _bankAccountNo),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
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
    int? validityDays,
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
      validityDays: validityDays,
    );
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$invoiceNumber.pdf');
    await file.writeAsBytes(bytes);
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'application/pdf')],
      subject: 'Invoice $invoiceNumber',
    );
  }

  static pw.Widget _sectionBox(List<pw.Widget> rows) => pw.Container(
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(
          color: PdfColors.grey100,
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
        ),
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: rows),
      );

  static pw.Widget _infoColumn(String title, List<pw.Widget> rows) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(title,
              style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 6),
          ...rows,
        ],
      );

  static pw.Widget _kv(String label, String value) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 3),
        child: pw.Text('$label: $value', style: const pw.TextStyle(fontSize: 10)),
      );

  static pw.Widget _bankDetail(String label, String value) => pw.Expanded(
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(label,
                style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
            pw.Text(value,
                style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
          ],
        ),
      );

  /// Builds a static Singapore PayNow SGQR payload (EMVCo QR Code
  /// Specification for Payment Systems) so the printed QR is genuinely
  /// scannable by banking apps, not just decorative — encodes the PayNow
  /// UEN with an editable amount (no fixed amount, since this is a receipt
  /// rather than a bill).
  static String _payNowQrPayload() {
    String field(String id, String value) =>
        '$id${value.length.toString().padLeft(2, '0')}$value';

    final payNowTemplate = field('00', 'SG.PAYNOW') +
        field('01', '2') + // proxy type: 2 = UEN
        field('02', _paynowUen) +
        field('03', '1'); // amount editable

    const merchantName = 'PEGASUS SPORTS ACADEMY';
    final payload = [
      field('00', '01'), // payload format indicator
      field('01', '11'), // static QR
      field('26', payNowTemplate),
      field('52', '0000'), // merchant category code (unclassified)
      field('53', '702'), // transaction currency: SGD
      field('58', 'SG'),
      field('59', merchantName),
      field('60', 'Singapore'),
      '6304', // CRC tag + length; value appended below
    ].join();

    final crc = _crc16Ccitt(payload).toRadixString(16).toUpperCase().padLeft(4, '0');
    return '$payload$crc';
  }

  /// CRC-16/CCITT-FALSE (poly 0x1021, init 0xFFFF) — the checksum algorithm
  /// mandated by the EMVCo QR spec that PayNow SGQR codes are built on.
  static int _crc16Ccitt(String data) {
    var crc = 0xFFFF;
    for (final byte in data.codeUnits) {
      crc ^= byte << 8;
      for (var i = 0; i < 8; i++) {
        crc = (crc & 0x8000) != 0 ? ((crc << 1) ^ 0x1021) & 0xFFFF : (crc << 1) & 0xFFFF;
      }
    }
    return crc;
  }

  static pw.Widget _totalRow(String label, String currency, double amount,
          {bool bold = false}) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 2),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(label,
                style: pw.TextStyle(
                    fontSize: bold ? 12 : 10,
                    fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
            pw.Text('$currency ${amount.toStringAsFixed(2)}',
                style: pw.TextStyle(
                    fontSize: bold ? 12 : 10,
                    fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
          ],
        ),
      );

  static pw.Widget _cell(String text, {bool bold = false}) => pw.Padding(
        padding: const pw.EdgeInsets.all(6),
        child: pw.Text(text,
            style: pw.TextStyle(
                fontSize: 9,
                fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
      );
}

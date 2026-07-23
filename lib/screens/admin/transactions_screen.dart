import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../services/config_service.dart';
import '../../services/invoice_service.dart';
import '../../utils/app_colors.dart';
import '../../utils/app_toast.dart';
import '../../widgets/timeline_range_selector.dart';

/// Transaction history now reads from the Google Sheet Transactions tab —
/// the durable copy — not Firestore. A `transactions` doc only exists
/// transiently while a purchase is being processed; it's deleted once the
/// Sheet write and invoice email both succeed (see InvoiceService /
/// QrPaymentService.approve / cash_payment_screen / memberships_screen).
/// Anything still sitting in Firestore here therefore means one of those
/// two steps failed and needs attention — shown as "Needs Attention" above
/// the Sheet-backed list, with a retry action.
class TransactionsScreen extends StatefulWidget {
  const TransactionsScreen({super.key});

  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends State<TransactionsScreen> {
  final _search = TextEditingController();
  String _query = '';
  DateTimeRange? _range;
  late Future<List<Map<String, String>>> _rowsFuture;

  @override
  void initState() {
    super.initState();
    _rowsFuture = ConfigService.getTransactions();
    _search.addListener(() {
      if (!mounted) return;
      setState(() => _query = _search.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _reload() {
    setState(() => _rowsFuture = ConfigService.getTransactions());
  }

  List<Map<String, String>> _filter(List<Map<String, String>> rows) {
    final inRange =
        rows.where((r) => isWithinRange(r['date'], _range ?? defaultDateRange())).toList();
    if (_query.isEmpty) return inRange;
    return inRange.where((r) {
      final name = (r['clientName'] ?? '').toLowerCase();
      final email = (r['clientEmail'] ?? '').toLowerCase();
      final plan = (r['planName'] ?? '').toLowerCase();
      final inv = (r['invoiceNumber'] ?? '').toLowerCase();
      return name.contains(_query) ||
          email.contains(_query) ||
          plan.contains(_query) ||
          inv.contains(_query);
    }).toList();
  }

  Future<void> _retryInvoice(QueryDocumentSnapshot doc) async {
    final data = doc.data() as Map<String, dynamic>;
    // Only redo whichever half failed last time — the other half already
    // succeeded and must not be repeated (would duplicate the Sheet row /
    // resend the email).
    final alreadySheetRecorded = data['sheetRecorded'] == true;
    final alreadyEmailSent = data['invoiceEmailSent'] == true;
    try {
      final (sheetRecorded, emailSent, error) =
          await InvoiceService.processWithInvoice(
        invoiceNumber: (data['invoiceNumber'] ?? '').toString(),
        paymentIntentId: (data['paymentIntentId'] ?? '').toString(),
        clientName: (data['clientName'] ?? '').toString(),
        clientEmail: (data['clientEmail'] ?? '').toString(),
        planName: (data['planName'] ?? '').toString(),
        credits: (data['credits'] as num?)?.toInt() ?? 0,
        amount: (data['amount'] as num?)?.toDouble() ?? 0,
        currency: (data['currency'] ?? 'SGD').toString(),
        displayPaymentRef: data['clientPaymentRef']?.toString(),
        couponCode: data['couponCode']?.toString(),
        originalAmount: (data['originalAmount'] as num?)?.toDouble(),
        recordToSheet: !alreadySheetRecorded,
        sendEmail: !alreadyEmailSent,
      );
      if (sheetRecorded && emailSent) {
        await doc.reference.delete();
        if (mounted) {
          AppToast.success(context, 'Invoice sent and recorded — resolved');
          _reload();
        }
      } else {
        await doc.reference.update({
          'invoiceEmailSent': emailSent,
          'sheetRecorded': sheetRecorded,
          if (error != null) 'invoiceEmailError': error,
        });
        if (mounted) {
          AppToast.error(context,
              'Still failing: ${!sheetRecorded ? 'Sheet write' : ''}${!sheetRecorded && !emailSent ? ' & ' : ''}${!emailSent ? 'email' : ''}');
        }
      }
    } catch (e) {
      if (mounted) AppToast.error(context, 'Retry failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Transaction History'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Reload',
            onPressed: _reload,
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Needs Attention (stuck Firestore records) ──────────────────
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('transactions')
                .orderBy('createdAt', descending: true)
                .snapshots(),
            builder: (context, snap) {
              final docs = snap.data?.docs ?? [];
              if (docs.isEmpty) return const SizedBox.shrink();
              return Container(
                margin: const EdgeInsets.fromLTRB(14, 14, 14, 0),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                  border:
                      Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.warning_amber_rounded,
                            size: 16, color: AppColors.warning),
                        const SizedBox(width: 6),
                        Text('Needs Attention (${docs.length})',
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: AppColors.warning)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'These purchases went through, but the invoice email '
                      'and/or Sheet record failed — retry to resolve.',
                      style:
                          TextStyle(fontSize: 11, color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 10),
                    ...docs.map((d) => _StuckTransactionCard(
                        doc: d, onRetry: () => _retryInvoice(d))),
                  ],
                ),
              );
            },
          ),
          // ── Timeline + search ────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
            child: DateRangeFilterBar(
              value: _range,
              onChanged: (r) => setState(() => _range = r),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
            child: TextField(
              controller: _search,
              decoration: InputDecoration(
                hintText: 'Search by name, email, plan…',
                hintStyle:
                    const TextStyle(color: AppColors.textMuted, fontSize: 13),
                prefixIcon:
                    const Icon(Icons.search, size: 18, color: AppColors.textMuted),
                suffixIcon: _query.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear,
                            size: 16, color: AppColors.textMuted),
                        onPressed: () => _search.clear(),
                      )
                    : null,
                filled: true,
                fillColor: AppColors.surface,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none),
              ),
            ),
          ),
          // ── Sheet-backed list ────────────────────────────────────────
          Expanded(
            child: FutureBuilder<List<Map<String, String>>>(
              future: _rowsFuture,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting &&
                    !snap.hasData) {
                  return const Center(
                      child:
                          CircularProgressIndicator(color: AppColors.primary));
                }
                if (snap.hasError) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.cloud_off,
                            size: 48, color: AppColors.textMuted),
                        const SizedBox(height: 12),
                        const Text('Could not load transactions',
                            style: TextStyle(color: AppColors.textSecondary)),
                        const SizedBox(height: 6),
                        Text(snap.error.toString(),
                            style: const TextStyle(
                                color: AppColors.textMuted, fontSize: 11),
                            textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        TextButton(onPressed: _reload, child: const Text('Retry')),
                      ],
                    ),
                  );
                }

                final all = snap.data ?? [];
                final filtered = _filter(all);

                double totalRevenue = 0;
                int totalCredits = 0;
                for (final r in filtered) {
                  totalRevenue += double.tryParse(r['amount'] ?? '') ?? 0;
                  totalCredits += int.tryParse(r['credits'] ?? '') ?? 0;
                }
                final currency =
                    filtered.isNotEmpty ? (filtered.first['currency'] ?? 'SGD') : 'SGD';

                return Column(
                  children: [
                    Container(
                      margin: const EdgeInsets.fromLTRB(14, 10, 14, 0),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 14),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: AppColors.primary.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          _SummaryChip(
                            label: 'Total Revenue',
                            value: '$currency ${totalRevenue.toStringAsFixed(2)}',
                            icon: Icons.payments_outlined,
                            color: AppColors.primary,
                          ),
                          const SizedBox(width: 12),
                          _SummaryChip(
                            label: 'Credits Sold',
                            value: totalCredits.toString(),
                            icon: Icons.confirmation_number_outlined,
                            color: const Color(0xFF00D4AA),
                          ),
                          const SizedBox(width: 12),
                          _SummaryChip(
                            label: 'Transactions',
                            value: filtered.length.toString(),
                            icon: Icons.receipt_long_outlined,
                            color: const Color(0xFFB388FF),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: filtered.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.receipt_long,
                                      size: 52, color: AppColors.textMuted),
                                  const SizedBox(height: 12),
                                  Text(
                                    _query.isEmpty
                                        ? 'No transactions in this window'
                                        : 'No results for "$_query"',
                                    style: const TextStyle(
                                        color: AppColors.textSecondary,
                                        fontSize: 14),
                                  ),
                                ],
                              ),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.fromLTRB(14, 10, 14, 24),
                              itemCount: filtered.length,
                              itemBuilder: (_, i) =>
                                  _SheetTransactionCard(row: filtered[i]),
                            ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ── Needs-attention card (Firestore-backed, stuck record) ──────────────────

class _StuckTransactionCard extends StatefulWidget {
  final QueryDocumentSnapshot doc;
  final VoidCallback onRetry;
  const _StuckTransactionCard({required this.doc, required this.onRetry});

  @override
  State<_StuckTransactionCard> createState() => _StuckTransactionCardState();
}

class _StuckTransactionCardState extends State<_StuckTransactionCard> {
  bool _retrying = false;

  @override
  Widget build(BuildContext context) {
    final data = widget.doc.data() as Map<String, dynamic>;
    final name = (data['clientName'] ?? '—').toString();
    final plan = (data['planName'] ?? '—').toString();
    final amount = (data['amount'] as num? ?? 0).toDouble();
    final currency = (data['currency'] ?? 'SGD').toString();
    final error = data['invoiceEmailError']?.toString();
    final sheetRecorded = data['sheetRecorded'] == true;
    final emailSent = data['invoiceEmailSent'] == true;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$name · $plan · $currency ${amount.toStringAsFixed(2)}',
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary)),
                const SizedBox(height: 3),
                Text(
                  '${sheetRecorded ? 'Sheet ✓' : 'Sheet ✗'} · ${emailSent ? 'Email ✓' : 'Email ✗'}'
                  '${error != null ? ' · $error' : ''}',
                  style:
                      const TextStyle(fontSize: 10, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _retrying
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppColors.warning))
              : TextButton(
                  onPressed: () async {
                    setState(() => _retrying = true);
                    widget.onRetry();
                    if (mounted) setState(() => _retrying = false);
                  },
                  child: const Text('Retry'),
                ),
        ],
      ),
    );
  }
}

// ── Summary chip ──────────────────────────────────────────────────────────────

class _SummaryChip extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _SummaryChip({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 13, color: color),
              const SizedBox(width: 4),
              Flexible(
                child: Text(label,
                    style: TextStyle(
                        fontSize: 10,
                        color: color,
                        fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(value,
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary),
              overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

// ── Transaction card (Sheet-backed) ─────────────────────────────────────────

class _SheetTransactionCard extends StatelessWidget {
  final Map<String, String> row;
  const _SheetTransactionCard({required this.row});

  String _formatDate(String? raw) {
    if (raw == null || raw.isEmpty) return '—';
    final dt = DateTime.tryParse(raw);
    if (dt == null) return raw;
    return formatWithWeekday(dt);
  }

  @override
  Widget build(BuildContext context) {
    final amount = double.tryParse(row['amount'] ?? '') ?? 0;
    final currency = row['currency'] ?? 'SGD';
    final credits = int.tryParse(row['credits'] ?? '') ?? 0;
    final date = _formatDate(row['date']);
    final name = row['clientName'] ?? '—';
    final email = row['clientEmail'] ?? '';
    final plan = row['planName'] ?? '—';
    final invoice = row['invoiceNumber'] ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(currency,
                    style: const TextStyle(
                        fontSize: 9,
                        color: AppColors.primary,
                        fontWeight: FontWeight.w700)),
                Text(amount.toStringAsFixed(0),
                    style: const TextStyle(
                        fontSize: 17,
                        color: AppColors.primary,
                        fontWeight: FontWeight.w800)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(name,
                          style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary)),
                    ),
                    Text(date,
                        style: const TextStyle(
                            fontSize: 11, color: AppColors.textMuted)),
                  ],
                ),
                if (email.isNotEmpty)
                  Text(email,
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.textMuted)),
                const SizedBox(height: 5),
                Row(
                  children: [
                    _Tag(plan, color: AppColors.primary),
                    const SizedBox(width: 6),
                    _Tag('$credits credits',
                        color: const Color(0xFF00D4AA)),
                  ],
                ),
                if (invoice.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('# $invoice',
                        style: const TextStyle(
                            fontSize: 10, color: AppColors.textMuted)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  final String label;
  final Color color;
  const _Tag(this.label, {required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 10, color: color, fontWeight: FontWeight.w600)),
    );
  }
}

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../utils/app_colors.dart';

class TransactionsScreen extends StatefulWidget {
  const TransactionsScreen({super.key});

  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends State<TransactionsScreen> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
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

  List<QueryDocumentSnapshot> _filter(List<QueryDocumentSnapshot> docs) {
    if (_query.isEmpty) return docs;
    return docs.where((d) {
      final data = d.data() as Map<String, dynamic>;
      final name = (data['clientName'] ?? '').toString().toLowerCase();
      final email = (data['clientEmail'] ?? '').toString().toLowerCase();
      final plan = (data['planName'] ?? '').toString().toLowerCase();
      final inv = (data['invoiceNumber'] ?? '').toString().toLowerCase();
      return name.contains(_query) ||
          email.contains(_query) ||
          plan.contains(_query) ||
          inv.contains(_query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Transaction History')),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('transactions')
            .orderBy('createdAt', descending: true)
            .snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
            return const Center(
                child: CircularProgressIndicator(color: AppColors.primary));
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
                ],
              ),
            );
          }

          final all = snap.data?.docs ?? [];
          final filtered = _filter(all);

          // Summary from all (unfiltered)
          double totalRevenue = 0;
          int totalCredits = 0;
          for (final doc in all) {
            final d = doc.data() as Map<String, dynamic>;
            totalRevenue += (d['amount'] as num? ?? 0).toDouble();
            totalCredits += (d['credits'] as num? ?? 0).toInt();
          }
          final currency = all.isNotEmpty
              ? ((all.first.data() as Map)['currency'] ?? 'SGD').toString()
              : 'SGD';

          return Column(
            children: [
              // Summary bar
              Container(
                margin: const EdgeInsets.fromLTRB(14, 14, 14, 0),
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
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
                      value: all.length.toString(),
                      icon: Icons.receipt_long_outlined,
                      color: const Color(0xFFB388FF),
                    ),
                  ],
                ),
              ),
              // Search
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
                child: TextField(
                  controller: _search,
                  decoration: InputDecoration(
                    hintText: 'Search by name, email, plan…',
                    hintStyle: const TextStyle(
                        color: AppColors.textMuted, fontSize: 13),
                    prefixIcon: const Icon(Icons.search,
                        size: 18, color: AppColors.textMuted),
                    suffixIcon: _query.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear,
                                size: 16, color: AppColors.textMuted),
                            onPressed: () => _search.clear(),
                          )
                        : null,
                    filled: true,
                    fillColor: AppColors.surface,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none),
                  ),
                ),
              ),
              // List
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
                                  ? 'No transactions yet'
                                  : 'No results for "$_query"',
                              style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 14),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding:
                            const EdgeInsets.fromLTRB(14, 4, 14, 24),
                        itemCount: filtered.length,
                        itemBuilder: (_, i) => _TransactionCard(
                            doc: filtered[i]),
                      ),
              ),
            ],
          );
        },
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

// ── Transaction card ──────────────────────────────────────────────────────────

class _TransactionCard extends StatelessWidget {
  final QueryDocumentSnapshot doc;
  const _TransactionCard({required this.doc});

  String _formatDate(dynamic raw) {
    try {
      final dt = raw is Timestamp ? raw.toDate() : DateTime.parse(raw.toString());
      const months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ];
      return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
    } catch (_) {
      return '—';
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = doc.data() as Map<String, dynamic>;
    final amount = (data['amount'] as num? ?? 0).toDouble();
    final currency = (data['currency'] ?? 'SGD').toString();
    final credits = (data['credits'] as num? ?? 0).toInt();
    final date = _formatDate(data['createdAt']);
    final name = (data['clientName'] ?? '—').toString();
    final email = (data['clientEmail'] ?? '').toString();
    final plan = (data['planName'] ?? '—').toString();
    final invoice = (data['invoiceNumber'] ?? '').toString();

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
          // Amount badge
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

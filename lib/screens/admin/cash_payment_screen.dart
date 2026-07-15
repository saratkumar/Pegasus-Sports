import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import '../../models/membership_plan_model.dart';
import '../../models/user_model.dart';
import '../../services/invoice_pdf_service.dart';
import '../../services/invoice_service.dart';
import '../../services/membership_plan_service.dart';
import '../../services/user_service.dart';
import '../../utils/app_colors.dart';
import '../../utils/app_toast.dart';

/// Lets an admin record a membership sale paid in cash (or any other
/// off-app method) — grants the membership/credits and generates the same
/// downloadable PDF invoice a Stripe purchase would, without touching Stripe.
class CashPaymentScreen extends StatefulWidget {
  const CashPaymentScreen({super.key});

  @override
  State<CashPaymentScreen> createState() => _CashPaymentScreenState();
}

class _CashPaymentScreenState extends State<CashPaymentScreen> {
  List<UserModel> _clients = [];
  List<MembershipPlanModel> _plans = [];
  bool _loading = true;
  bool _saving = false;

  UserModel? _selectedClient;
  MembershipPlanModel? _selectedPlan;
  late final TextEditingController _amount;
  late final TextEditingController _credits;
  late final TextEditingController _invoiceNumber;

  @override
  void initState() {
    super.initState();
    _amount = TextEditingController();
    _credits = TextEditingController();
    _invoiceNumber = TextEditingController();
    _loadData();
  }

  @override
  void dispose() {
    _amount.dispose();
    _credits.dispose();
    _invoiceNumber.dispose();
    super.dispose();
  }

  /// Reserves a fresh invoice number with no payment attached yet — for
  /// handing to a client before cash actually changes hands. Not persisted
  /// anywhere; the admin notes it down (or pastes it straight into the
  /// field below) and it's only recorded once a payment is actually filed.
  void _generateInvoiceNumber() {
    final seed = '${DateTime.now().microsecondsSinceEpoch}'
        '${Random().nextInt(999999)}';
    final number = InvoiceService.generateInvoiceNumber(seed);
    setState(() => _invoiceNumber.text = number);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Invoice Number Reserved',
            style: TextStyle(
                color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
        content: SelectableText(number,
            style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: AppColors.primary)),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: number));
              AppToast.info(context, 'Copied to clipboard');
            },
            child: const Text('Copy'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  Future<void> _loadData() async {
    try {
      final results = await Future.wait([
        UserService.getUsersByRole('client'),
        MembershipPlanService.getActivePlans(),
      ]);
      if (!mounted) return;
      setState(() {
        _clients = results[0] as List<UserModel>;
        _plans = results[1] as List<MembershipPlanModel>;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      AppToast.error(context, 'Failed to load clients/plans: $e');
    }
  }

  void _onPlanSelected(MembershipPlanModel? plan) {
    setState(() {
      _selectedPlan = plan;
      if (plan != null) {
        _amount.text = plan.price.toStringAsFixed(2);
        _credits.text = plan.credits.toString();
      }
    });
  }

  Future<void> _submit() async {
    final client = _selectedClient;
    final plan = _selectedPlan;
    if (client == null || plan == null) {
      AppToast.error(context, 'Select a client and a plan');
      return;
    }
    final amount = double.tryParse(_amount.text.trim());
    final credits = int.tryParse(_credits.text.trim());
    if (amount == null || amount < 0) {
      AppToast.error(context, 'Enter a valid amount');
      return;
    }
    if (credits == null || credits <= 0) {
      AppToast.error(context, 'Enter a valid credit amount');
      return;
    }

    setState(() => _saving = true);
    try {
      final now = DateTime.now();
      final endDate = plan.validityDays > 0
          ? now.add(Duration(days: plan.validityDays))
          : now.add(const Duration(days: 365));

      await UserService.purchaseMembership(
        client.uid,
        MembershipEntry(
          planName: plan.name,
          credits: credits,
          startDate: now,
          endDate: endDate,
          purchasedAt: now,
        ),
      );

      final txRef = FirebaseFirestore.instance.collection('transactions').doc();
      final paymentRef = 'cash_${txRef.id}';
      final reused = _invoiceNumber.text.trim();
      final invoiceNumber =
          reused.isNotEmpty ? reused : InvoiceService.generateInvoiceNumber(paymentRef);

      await txRef.set({
        'invoiceNumber': invoiceNumber,
        'paymentIntentId': paymentRef,
        'paymentMethod': 'cash',
        'clientUid': client.uid,
        'clientName': client.name,
        'clientEmail': client.email,
        'planName': plan.name,
        'credits': credits,
        'amount': amount,
        'currency': 'SGD',
        'createdAt': FieldValue.serverTimestamp(),
      });

      // Best-effort background attempt: write to the Google Sheet and email
      // the invoice if EmailJS happens to be configured. Silent either way —
      // the PDF below is the actual invoice delivery method for now.
      InvoiceService.processWithInvoice(
        invoiceNumber: invoiceNumber,
        paymentIntentId: paymentRef,
        clientName: client.name,
        clientEmail: client.email,
        planName: plan.name,
        credits: credits,
        amount: amount,
        currency: 'SGD',
      ).then((result) {
        final (emailSent, error) = result;
        return txRef.update({
          'invoiceEmailSent': emailSent,
          if (error != null) 'invoiceEmailError': error,
        });
      }).catchError((_) {});

      if (mounted) {
        AppToast.success(context,
            '${plan.name} activated for ${client.name} (+$credits credits)');
        setState(() {
          _selectedClient = null;
          _selectedPlan = null;
          _amount.clear();
          _credits.clear();
          _invoiceNumber.clear();
        });
      }

      try {
        await InvoicePdfService.shareInvoice(
          invoiceNumber: invoiceNumber,
          paymentRef: paymentRef,
          clientName: client.name,
          clientEmail: client.email,
          planName: plan.name,
          credits: credits,
          amount: amount,
          currency: 'SGD',
        );
      } catch (e) {
        if (mounted) {
          AppToast.error(context, 'Could not generate invoice PDF: $e');
        }
      }
    } catch (e) {
      if (mounted) {
        AppToast.error(context, e.toString().replaceFirst('Exception: ', ''));
      }
    }
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Record Cash Payment')),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text(
                  'Use this when a client pays outside the app (cash, bank transfer, etc). '
                  'It grants the membership immediately and emails an invoice just like a card payment.',
                  style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<UserModel>(
                  initialValue: _selectedClient,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'Client',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                  items: _clients
                      .map((c) => DropdownMenuItem(
                            value: c,
                            child: Text('${c.name} (${c.email})',
                                overflow: TextOverflow.ellipsis),
                          ))
                      .toList(),
                  onChanged: (v) => setState(() => _selectedClient = v),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<MembershipPlanModel>(
                  initialValue: _selectedPlan,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'Plan',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                  items: _plans
                      .map((p) => DropdownMenuItem(
                            value: p,
                            child: Text('${p.name} — \$${p.price.toStringAsFixed(2)}',
                                overflow: TextOverflow.ellipsis),
                          ))
                      .toList(),
                  onChanged: _onPlanSelected,
                ),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: TextFormField(
                      controller: _amount,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: 'Amount Paid (SGD)',
                        border:
                            OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _credits,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'Credits to Grant',
                        border:
                            OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                      ),
                    ),
                  ),
                ]),
                if (_selectedPlan != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Validity: ${_selectedPlan!.validityDays > 0 ? '${_selectedPlan!.validityDays} days from today' : '1 year (no expiry plan)'}',
                    style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                  ),
                ],
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _invoiceNumber,
                        decoration: InputDecoration(
                          labelText: 'Invoice Number (optional)',
                          helperText:
                              'Leave blank to auto-generate, or paste one reserved earlier',
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10)),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    OutlinedButton(
                      onPressed: _generateInvoiceNumber,
                      child: const Text('Generate'),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: _saving ? null : _submit,
                  style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 48)),
                  child: _saving
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Text('Record Payment & Activate'),
                ),
              ],
            ),
    );
  }
}

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import '../../models/coupon_model.dart';
import '../../models/membership_plan_model.dart';
import '../../models/user_model.dart';
import '../../services/coupon_service.dart';
import '../../services/invoice_pdf_service.dart';
import '../../services/invoice_service.dart';
import '../../services/membership_plan_service.dart';
import '../../services/payment_service.dart';
import '../../services/user_service.dart';
import '../../utils/app_colors.dart';
import '../../utils/app_toast.dart';
import '../../utils/plan_category_style.dart';

class MembershipScreen extends StatefulWidget {
  const MembershipScreen({super.key});

  @override
  State<MembershipScreen> createState() => _MembershipScreenState();
}

class _MembershipScreenState extends State<MembershipScreen> {
  String? _selectedCategory;

  @override
  void initState() {
    super.initState();
    MembershipPlanService.ensureSeeded();
  }

  Future<void> _openCheckout(
      BuildContext context, MembershipPlanModel plan) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.bg,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _CheckoutSheet(
        plan: plan,
        onConfirm: (coupon, finalAmount) =>
            _purchase(context, plan, coupon: coupon, finalAmount: finalAmount),
      ),
    );
  }

  Future<void> _purchase(
    BuildContext context,
    MembershipPlanModel plan, {
    CouponModel? coupon,
    required double finalAmount,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    if (!context.mounted) return;

    try {
      String paymentRef;
      if (finalAmount > 0) {
        paymentRef = await PaymentService.processPayment(
          planName: plan.name,
          amount: finalAmount,
          currency: 'sgd',
        );
      } else {
        // Coupon covers the full price — no charge to process.
        paymentRef = 'coupon_${DateTime.now().millisecondsSinceEpoch}';
      }

      // Payment succeeded — activate membership in Firestore
      final now = DateTime.now();
      final endDate = plan.validityDays > 0
          ? now.add(Duration(days: plan.validityDays))
          : now.add(const Duration(days: 365));

      final entry = MembershipEntry(
        planName: plan.name,
        credits: plan.credits,
        startDate: now,
        endDate: endDate,
        purchasedAt: now,
      );

      await UserService.purchaseMembership(uid, entry);
      if (coupon?.id != null) {
        await CouponService.redeem(coupon!.id!);
      }

      final currentUser = FirebaseAuth.instance.currentUser;
      final invoiceNumber = InvoiceService.generateInvoiceNumber(paymentRef);

      // Write to Firestore transactions collection (primary source for admin UI)
      final txDoc = await FirebaseFirestore.instance.collection('transactions').add({
        'invoiceNumber': invoiceNumber,
        'paymentIntentId': paymentRef,
        'clientUid': uid,
        'clientName': currentUser?.displayName ?? 'Member',
        'clientEmail': currentUser?.email ?? '',
        'planName': plan.name,
        'credits': plan.credits,
        'amount': finalAmount,
        'currency': 'SGD',
        if (coupon != null) 'couponCode': coupon.code,
        if (coupon != null) 'originalAmount': plan.price,
        'createdAt': FieldValue.serverTimestamp(),
      });

      // Best-effort background attempt: write to the Google Sheet and email
      // the invoice if EmailJS happens to be configured. Silent either way —
      // the PDF below is the actual invoice delivery method for now.
      InvoiceService.processWithInvoice(
        invoiceNumber: invoiceNumber,
        paymentIntentId: paymentRef,
        clientName: currentUser?.displayName ?? 'Member',
        clientEmail: currentUser?.email ?? '',
        planName: plan.name,
        credits: plan.credits,
        amount: finalAmount,
        currency: 'SGD',
      ).then((result) {
        final (emailSent, error) = result;
        return txDoc.update({
          'invoiceEmailSent': emailSent,
          if (error != null) 'invoiceEmailError': error,
        });
      }).catchError((_) {});

      if (context.mounted) {
        AppToast.success(
            context, '${plan.name} activated! +${plan.credits} credits added');
      }

      try {
        await InvoicePdfService.shareInvoice(
          invoiceNumber: invoiceNumber,
          paymentRef: paymentRef,
          clientName: currentUser?.displayName ?? 'Member',
          clientEmail: currentUser?.email ?? '',
          planName: plan.name,
          credits: plan.credits,
          amount: finalAmount,
          currency: 'SGD',
          couponCode: coupon?.code,
          originalAmount: coupon != null ? plan.price : null,
        );
      } catch (e) {
        if (context.mounted) {
          AppToast.error(context, 'Could not generate invoice PDF: $e');
        }
      }
    } on StripeException catch (e) {
      if (e.error.code != FailureCode.Canceled && context.mounted) {
        AppToast.error(context, e.error.localizedMessage ?? 'Payment failed');
      }
    } catch (e) {
      if (context.mounted) {
        AppToast.error(context, e.toString().replaceFirst('Exception: ', ''));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: const Text('Membership Plans')),
      body: uid.isEmpty
          ? const SizedBox()
          : StreamBuilder<List<MembershipPlanModel>>(
              stream: MembershipPlanService.streamPlans(),
              builder: (context, planSnap) {
                if (planSnap.connectionState == ConnectionState.waiting &&
                    !planSnap.hasData) {
                  return const Center(
                      child: CircularProgressIndicator(color: AppColors.primary));
                }
                final allPlans =
                    (planSnap.data ?? []).where((p) => p.isActive).toList();
                final categories = <String>[];
                for (final p in allPlans) {
                  if (!categories.contains(p.category)) categories.add(p.category);
                }
                if (categories.isEmpty) {
                  return const Center(
                    child: Text('No membership plans available yet',
                        style: TextStyle(color: AppColors.textSecondary)),
                  );
                }
                if (_selectedCategory == null ||
                    !categories.contains(_selectedCategory)) {
                  _selectedCategory = categories.first;
                }
                final plans = allPlans
                    .where((p) => p.category == _selectedCategory)
                    .toList();

                return StreamBuilder<UserModel?>(
                  stream: UserService.currentUserStream(),
                  builder: (ctx, snap) {
                    final user = snap.data;
                    final activePlans =
                        user?.memberships.where((m) => m.isActive).toList() ?? [];

                    return Column(
                      children: [
                        if (user != null)
                          _CreditsAndPlansBanner(user: user, activePlans: activePlans),
                        const SizedBox(height: 8),
                        _CategoryBar(
                          categories: categories,
                          selected: _selectedCategory!,
                          onSelect: (c) => setState(() => _selectedCategory = c),
                        ),
                        Expanded(
                          child: ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                            itemCount: plans.length,
                            itemBuilder: (_, i) {
                              final plan = plans[i];
                              final color = PlanCategoryStyle.of(plan.category).color;
                              final isOwned =
                                  activePlans.any((m) => m.planName == plan.name);
                              return _PlanCard(
                                plan: plan,
                                color: color,
                                isOwned: isOwned,
                                onSelect: () => _openCheckout(context, plan),
                              );
                            },
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
    );
  }
}

// ── Category selector ─────────────────────────────────────────────────────────

class _CategoryBar extends StatelessWidget {
  final List<String> categories;
  final String selected;
  final ValueChanged<String> onSelect;

  const _CategoryBar(
      {required this.categories, required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: categories.length,
        itemBuilder: (context, i) {
          final cat = categories[i];
          final style = PlanCategoryStyle.of(cat);
          final isSelected = cat == selected;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => onSelect(cat),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: isSelected
                      ? style.color.withValues(alpha: 0.15)
                      : AppColors.surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isSelected
                        ? style.color.withValues(alpha: 0.5)
                        : AppColors.divider,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(style.icon,
                        size: 15,
                        color: isSelected ? style.color : AppColors.textMuted),
                    const SizedBox(width: 6),
                    Text(cat,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                          color: isSelected ? style.color : AppColors.textSecondary,
                        )),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ── Credits + active plans banner ────────────────────────────────────────────

class _CreditsAndPlansBanner extends StatelessWidget {
  final UserModel user;
  final List<MembershipEntry> activePlans;

  const _CreditsAndPlansBanner(
      {required this.user, required this.activePlans});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primary.withValues(alpha: 0.18),
            AppColors.primary.withValues(alpha: 0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.toll_rounded,
                  color: AppColors.primary, size: 20),
              const SizedBox(width: 8),
              Text(
                '${user.credits} Credits',
                style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary),
              ),
            ],
          ),
          if (activePlans.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text('Active Plans',
                style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            ...activePlans.map((m) => _ActivePlanRow(entry: m)),
          ] else ...[
            const SizedBox(height: 6),
            const Text('No active plans — purchase one below',
                style: TextStyle(
                    fontSize: 12, color: AppColors.textSecondary)),
          ],
        ],
      ),
    );
  }
}

class _ActivePlanRow extends StatelessWidget {
  final MembershipEntry entry;
  const _ActivePlanRow({required this.entry});

  @override
  Widget build(BuildContext context) {
    // Compare date boundaries only so time-of-day doesn't skew the count
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final endDay = DateTime(
        entry.endDate.year, entry.endDate.month, entry.endDate.day);
    final daysLeft = endDay.difference(today).inDays;
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          const Icon(Icons.verified_rounded,
              color: AppColors.primary, size: 14),
          const SizedBox(width: 8),
          Expanded(
            child: Text(entry.planName,
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary)),
          ),
          Text('$daysLeft days left',
              style: TextStyle(
                  fontSize: 11,
                  color: daysLeft < 7 ? AppColors.error : AppColors.textMuted,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

// ── Plan card ────────────────────────────────────────────────────────────────

class _PlanCard extends StatelessWidget {
  final MembershipPlanModel plan;
  final Color color;
  final bool isOwned;
  final VoidCallback onSelect;

  const _PlanCard({
    required this.plan,
    required this.color,
    required this.isOwned,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final priceStr =
        '\$${plan.price % 1 == 0 ? plan.price.toInt() : plan.price.toStringAsFixed(2)}';

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isOwned ? color.withValues(alpha: 0.7) : AppColors.divider,
          width: isOwned ? 1.5 : 1,
        ),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  color.withValues(alpha: 0.15),
                  color.withValues(alpha: 0.04),
                ],
              ),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(17)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (plan.badge != null)
                        Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(plan.badge!,
                              style: TextStyle(
                                  fontSize: 10,
                                  color: color,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.5)),
                        ),
                      Text(plan.name,
                          style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary)),
                      const SizedBox(height: 3),
                      Text(plan.subtitle,
                          style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary)),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    RichText(
                      text: TextSpan(
                        children: [
                          TextSpan(
                            text: priceStr,
                            style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                color: color),
                          ),
                          if (plan.priceLabel != null)
                            TextSpan(
                              text: plan.priceLabel,
                              style: TextStyle(
                                  fontSize: 12,
                                  color: color.withValues(alpha: 0.7)),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.toll_rounded, size: 12, color: color),
                        const SizedBox(width: 4),
                        Text('${plan.credits} credits',
                            style: TextStyle(
                                fontSize: 11,
                                color: color,
                                fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 14),
            child: Column(
              children: [
                Row(
                  children: [
                    Icon(Icons.schedule_rounded,
                        size: 13, color: AppColors.textMuted),
                    const SizedBox(width: 6),
                    Text(
                      plan.validityDays > 0
                          ? 'Valid: ${plan.validityDays} days'
                          : 'Valid: See T&Cs',
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textMuted),
                    ),
                  ],
                ),
                if (plan.features.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  const Divider(color: AppColors.divider, height: 1),
                  const SizedBox(height: 10),
                  ...plan.features.map((f) => Padding(
                        padding: const EdgeInsets.only(bottom: 5),
                        child: Row(
                          children: [
                            Icon(Icons.check_circle_rounded,
                                size: 13, color: color),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(f,
                                  style: const TextStyle(
                                      fontSize: 12,
                                      color: AppColors.textSecondary)),
                            ),
                          ],
                        ),
                      )),
                ],
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: isOwned ? null : onSelect,
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          isOwned ? AppColors.divider : color.withValues(alpha: 0.15),
                      foregroundColor: isOwned ? AppColors.textMuted : color,
                      elevation: 0,
                      side: BorderSide(
                          color: isOwned
                              ? AppColors.divider
                              : color.withValues(alpha: 0.4)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text(
                      isOwned ? 'Active Plan' : 'Purchase Plan',
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 14),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Checkout sheet (with optional coupon) ─────────────────────────────────────

class _CheckoutSheet extends StatefulWidget {
  final MembershipPlanModel plan;
  final Future<void> Function(CouponModel? coupon, double finalAmount) onConfirm;

  const _CheckoutSheet({required this.plan, required this.onConfirm});

  @override
  State<_CheckoutSheet> createState() => _CheckoutSheetState();
}

class _CheckoutSheetState extends State<_CheckoutSheet> {
  final _couponCtrl = TextEditingController();
  CouponModel? _appliedCoupon;
  String? _error;
  bool _validating = false;
  bool _processing = false;

  Future<void> _confirm() async {
    setState(() => _processing = true);
    await widget.onConfirm(_appliedCoupon, _finalAmount);
    if (mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
    _couponCtrl.dispose();
    super.dispose();
  }

  double get _finalAmount => _appliedCoupon != null
      ? _appliedCoupon!.applyTo(widget.plan.price)
      : widget.plan.price;

  Future<void> _applyCoupon() async {
    final code = _couponCtrl.text.trim();
    if (code.isEmpty) return;
    setState(() {
      _validating = true;
      _error = null;
    });
    try {
      final coupon = await CouponService.validate(code);
      setState(() => _appliedCoupon = coupon);
    } catch (e) {
      setState(() {
        _appliedCoupon = null;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
    if (mounted) setState(() => _validating = false);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_processing,
      child: Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.plan.name,
              style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 4),
          Text(widget.plan.subtitle,
              style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
          const SizedBox(height: 20),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _couponCtrl,
                textCapitalization: TextCapitalization.characters,
                enabled: _appliedCoupon == null,
                decoration: InputDecoration(
                  labelText: 'Coupon code (optional)',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
              ),
            ),
            const SizedBox(width: 10),
            if (_appliedCoupon == null)
              ElevatedButton(
                onPressed: (_validating || _processing) ? null : _applyCoupon,
                child: _validating
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Text('Apply'),
              )
            else
              OutlinedButton(
                onPressed: _processing
                    ? null
                    : () => setState(() {
                          _appliedCoupon = null;
                          _couponCtrl.clear();
                          _error = null;
                        }),
                child: const Text('Remove'),
              ),
          ]),
          if (_error != null) ...[
            const SizedBox(height: 6),
            Text(_error!, style: const TextStyle(fontSize: 12, color: AppColors.error)),
          ],
          if (_appliedCoupon != null) ...[
            const SizedBox(height: 6),
            Text(
                '"${_appliedCoupon!.code}" applied — '
                '${_appliedCoupon!.discountType == 'percent' ? '${_appliedCoupon!.value.toStringAsFixed(0)}% off' : '\$${_appliedCoupon!.value.toStringAsFixed(2)} off'}',
                style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF00D4AA),
                    fontWeight: FontWeight.w600)),
          ],
          const SizedBox(height: 20),
          const Divider(color: AppColors.divider),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Total',
                  style: TextStyle(fontSize: 14, color: AppColors.textSecondary)),
              Row(children: [
                if (_appliedCoupon != null) ...[
                  Text('\$${widget.plan.price.toStringAsFixed(2)}',
                      style: const TextStyle(
                          fontSize: 14,
                          color: AppColors.textMuted,
                          decoration: TextDecoration.lineThrough)),
                  const SizedBox(width: 8),
                ],
                Text('\$${_finalAmount.toStringAsFixed(2)}',
                    style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primary)),
              ]),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _processing ? null : _confirm,
              child: _processing
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : Text(_finalAmount > 0 ? 'Confirm & Pay' : 'Confirm (Free)'),
            ),
          ),
        ],
      ),
      ),
    );
  }
}

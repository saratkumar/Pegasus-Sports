import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import '../../models/coupon_model.dart';
import '../../models/membership_plan_model.dart';
import '../../models/user_model.dart';
import '../../services/coupon_service.dart';
import '../../services/invoice_service.dart';
import '../../services/membership_plan_service.dart';
import '../../services/payment_service.dart';
import '../../services/qr_payment_service.dart';
import '../../services/user_service.dart';
import '../../utils/app_colors.dart';
import '../../utils/app_toast.dart';
import '../../utils/error_reporter.dart';
import '../../utils/plan_category_style.dart';
import '../../utils/stripe_fee_estimator.dart';

class MembershipScreen extends StatefulWidget {
  const MembershipScreen({super.key});

  @override
  State<MembershipScreen> createState() => _MembershipScreenState();
}

class _MembershipScreenState extends State<MembershipScreen> {
  String? _selectedCategory;
  // TODO(debug): isolates presentPaymentSheet() from all of this app's own
  // navigation (checkout bottom sheet, loading dialog) to test whether the
  // Stripe SDK call works at all with zero Flutter modals/routes involved.
  // Remove once the "sheet never appears" hang is root-caused.
  String? _debugStripeStatus;

  @override
  void initState() {
    super.initState();
    MembershipPlanService.ensureSeeded();
  }

  Future<void> _debugTestStripeDirectly(BuildContext context) async {
    setState(() => _debugStripeStatus = 'Starting...');
    try {
      await PaymentService.processPayment(
        planName: 'Debug Test',
        netAmount: 1.0,
        currency: 'sgd',
        cardRegion: 'domestic',
        cardBrand: 'visa_mc',
        onStep: (step) {
          if (mounted) setState(() => _debugStripeStatus = step);
        },
      );
      if (mounted) setState(() => _debugStripeStatus = 'Sheet completed!');
    } catch (e) {
      if (mounted) setState(() => _debugStripeStatus = 'Error: $e');
    }
  }

  Future<void> _openCheckout(
      BuildContext context, MembershipPlanModel plan) async {
    // The checkout sheet only collects the coupon/card-tier choice and pops
    // with the result — it does NOT run the purchase itself. Stripe's
    // presentPaymentSheet() must never be called while another Flutter modal
    // (this sheet) is still open/mid-transition: a known flutter_stripe/iOS
    // quirk where the native sheet then never appears and the call hangs
    // forever with no error at all. Running _purchase only after this modal
    // has fully closed avoids that entirely.
    final result =
        await showModalBottomSheet<(CouponModel?, double, String, String)>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.bg,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _CheckoutSheet(plan: plan),
    );
    if (result == null || !context.mounted) return;
    final (coupon, finalAmount, cardRegion, cardBrand) = result;
    await _purchase(context, plan,
        coupon: coupon,
        finalAmount: finalAmount,
        cardRegion: cardRegion,
        cardBrand: cardBrand);
  }

  Future<void> _purchase(
    BuildContext context,
    MembershipPlanModel plan, {
    CouponModel? coupon,
    required double finalAmount,
    required String cardRegion,
    required String cardBrand,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    if (!context.mounted) return;

    // Shown only now that the checkout sheet has fully closed (see
    // _openCheckout) — Stripe's presentPaymentSheet() must never run while
    // another Flutter modal is still open/mid-transition.
    final statusNotifier = ValueNotifier<String?>(null);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: Center(
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(color: AppColors.primary),
                ValueListenableBuilder<String?>(
                  valueListenable: statusNotifier,
                  builder: (_, status, __) => status == null
                      ? const SizedBox()
                      : Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(status,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondary)),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    void closeLoadingDialog() {
      if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
    }

    try {
      String paymentRef;
      double? feeAmount;
      double? grossAmount;
      if (finalAmount > 0) {
        final payment = await PaymentService.processPayment(
          planName: plan.name,
          netAmount: finalAmount,
          currency: 'sgd',
          cardRegion: cardRegion,
          cardBrand: cardBrand,
          // TODO(debug): temporary status breadcrumbs to localize the Stripe
          // "sheet never appears" hang live on a test device, without waiting
          // on Crashlytics' timeout + next-launch upload delay. Remove once
          // root-caused.
          onStep: (step) => statusNotifier.value = step,
        );
        paymentRef = payment.paymentIntentId;
        feeAmount = payment.feeAmount;
        grossAmount = payment.grossAmount;
        // Payment confirmed server-side (verifies with Stripe before
        // activating) — replaces trusting the client's own Firestore write.
        await PaymentService.confirmMembershipPayment(
          paymentIntentId: paymentRef,
          planName: plan.name,
          credits: plan.credits,
          validityDays: plan.validityDays,
        );
        // Partial-discount coupon (still a real charge) — redemption count
        // tracking only, not a security boundary like free redemption is.
        if (coupon?.id != null) {
          await CouponService.redeem(coupon!.id!);
        }
      } else {
        // Coupon covers the full price — no charge to process. Coupon
        // validation + redemption + membership activation all happen
        // atomically server-side rather than trusting the client.
        if (coupon == null) {
          throw Exception('A coupon is required for a free membership');
        }
        paymentRef = 'coupon_${DateTime.now().millisecondsSinceEpoch}';
        await PaymentService.redeemFreeMembership(
          planName: plan.name,
          credits: plan.credits,
          validityDays: plan.validityDays,
          couponCode: coupon.code,
        );
      }

      final currentUser = FirebaseAuth.instance.currentUser;
      final invoiceNumber = InvoiceService.generateInvoiceNumber(paymentRef);

      // Stripe's PaymentIntent description was set to the plan name at
      // creation (before the invoice number existed) — overwrite it now so
      // the Dashboard reflects the real invoice number. Skip for coupon-only
      // purchases, which never created a real PaymentIntent.
      if (finalAmount > 0) {
        unawaited(
            PaymentService.setInvoiceDescription(paymentRef, invoiceNumber));
      }

      // Write to Firestore transactions collection — a transient working
      // record only; deleted below once the Sheet write + invoice email
      // both succeed, since the Sheet becomes the durable copy.
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
        'validityDays': plan.validityDays,
        if (coupon != null) 'couponCode': coupon.code,
        if (coupon != null) 'originalAmount': plan.price,
        if (feeAmount != null) 'feeAmount': feeAmount,
        if (grossAmount != null) 'grossAmount': grossAmount,
        if (feeAmount != null) 'cardRegion': cardRegion,
        if (feeAmount != null) 'cardBrand': cardBrand,
        'createdAt': FieldValue.serverTimestamp(),
      });

      // Mirror to the Google Sheet and email the PDF invoice — awaited so
      // the outcome is known before deciding whether the Firestore
      // transaction doc is still needed (see below).
      final (sheetRecorded, emailSent, invoiceError) =
          await InvoiceService.processWithInvoice(
        invoiceNumber: invoiceNumber,
        paymentIntentId: paymentRef,
        clientName: currentUser?.displayName ?? 'Member',
        clientEmail: currentUser?.email ?? '',
        planName: plan.name,
        credits: plan.credits,
        amount: finalAmount,
        currency: 'SGD',
        displayPaymentRef: paymentRef,
        couponCode: coupon?.code,
        originalAmount: coupon != null ? plan.price : null,
        feeAmount: feeAmount,
        validityDays: plan.validityDays,
      );
      if (sheetRecorded && emailSent) {
        // Durably recorded in the Sheet and the customer has their invoice —
        // nothing left for Firestore to hold onto.
        await txDoc.delete();
      } else {
        await txDoc.update({
          'invoiceEmailSent': emailSent,
          'sheetRecorded': sheetRecorded,
          if (invoiceError != null) 'invoiceEmailError': invoiceError,
        });
      }

      if (context.mounted) {
        AppToast.success(
          context,
          emailSent
              ? '${plan.name} activated! +${plan.credits} credits added — invoice emailed to you'
              : '${plan.name} activated! +${plan.credits} credits added — invoice email failed, our team has been notified',
        );
      }
    } on StripeException catch (e, st) {
      if (e.error.code != FailureCode.Canceled && context.mounted) {
        reportError(
          context,
          e,
          st,
          userMessage: 'Payment failed. Please try again or contact support.',
          reason: 'Membership purchase Stripe payment failed',
        );
      }
    } catch (e, st) {
      if (context.mounted) {
        reportError(
          context,
          e,
          st,
          userMessage: friendlyMessage(
              e, 'Payment failed. Please try again or contact support.'),
          reason: 'Membership purchase failed',
        );
      }
    } finally {
      closeLoadingDialog();
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('Membership Plans'),
        actions: [
          IconButton(
            icon: const Icon(Icons.bug_report_outlined),
            tooltip: 'Debug: test Stripe sheet directly',
            onPressed: () => _debugTestStripeDirectly(context),
          ),
        ],
      ),
      body: uid.isEmpty
          ? const SizedBox()
          : Column(
              children: [
                if (_debugStripeStatus != null)
                  Container(
                    width: double.infinity,
                    color: Colors.black87,
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      'Stripe debug: $_debugStripeStatus',
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                    ),
                  ),
                Expanded(child: _buildPlansBody(uid)),
              ],
            ),
    );
  }

  Widget _buildPlansBody(String uid) {
    return StreamBuilder<List<MembershipPlanModel>>(
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

                // Surface the cheapest-per-credit plan as "Best Value" so
                // it's obvious which option to pick without reading every
                // card — only meaningful when there's more than one plan
                // to compare and credits are actually comparable.
                String? bestValuePlanName;
                final withCredits = plans.where((p) => p.credits > 0).toList();
                if (plans.length > 1 && withCredits.length > 1) {
                  withCredits.sort(
                      (a, b) => (a.price / a.credits).compareTo(b.price / b.credits));
                  bestValuePlanName = withCredits.first.name;
                }

                return StreamBuilder<UserModel?>(
                  stream: UserService.currentUserStream(),
                  builder: (ctx, snap) {
                    final user = snap.data;
                    final activePlans =
                        user?.memberships.where((m) => m.isActive).toList() ?? [];
                    final queuedPlans = user?.queuedMemberships ?? [];

                    return Column(
                      children: [
                        if (user != null)
                          _CreditsAndPlansBanner(
                              user: user,
                              activePlans: activePlans,
                              queuedPlans: queuedPlans),
                        const SizedBox(height: 8),
                        _CategoryBar(
                          categories: categories,
                          selected: _selectedCategory!,
                          onSelect: (c) => setState(() => _selectedCategory = c),
                        ),
                        if (PlanCategoryStyle.of(_selectedCategory!)
                            .description
                            .isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                            child: Text(
                              PlanCategoryStyle.of(_selectedCategory!).description,
                              style: const TextStyle(
                                  fontSize: 12, color: AppColors.textSecondary),
                            ),
                          ),
                        Expanded(
                          child: ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                            itemCount: plans.length,
                            itemBuilder: (_, i) {
                              final plan = plans[i];
                              final color = PlanCategoryStyle.of(plan.category).color;
                              final isOwned = activePlans
                                      .any((m) => m.planName == plan.name) ||
                                  queuedPlans.any((m) => m.planName == plan.name);
                              return _PlanCard(
                                plan: plan,
                                color: color,
                                isOwned: isOwned,
                                isBestValue: plan.name == bestValuePlanName,
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
  final List<MembershipEntry> queuedPlans;

  const _CreditsAndPlansBanner({
    required this.user,
    required this.activePlans,
    required this.queuedPlans,
  });

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
                '${user.totalUsableCredits} Credits',
                style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary),
              ),
            ],
          ),
          if (user.activeAdminGrant != null) ...[
            const SizedBox(height: 12),
            _AdminGrantRow(grant: user.activeAdminGrant!),
          ],
          if (activePlans.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text('Active Plans',
                style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            ...activePlans.map((m) => _ActivePlanRow(entry: m)),
          ] else if (user.activeAdminGrant == null) ...[
            const SizedBox(height: 6),
            const Text('No active plans — purchase one below',
                style: TextStyle(
                    fontSize: 12, color: AppColors.textSecondary)),
          ],
          if (queuedPlans.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text('Queued — starts once your current plan ends',
                style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            ...queuedPlans.map((m) => _QueuedPlanRow(entry: m)),
          ],
        ],
      ),
    );
  }
}

class _QueuedPlanRow extends StatelessWidget {
  final MembershipEntry entry;
  const _QueuedPlanRow({required this.entry});

  @override
  Widget build(BuildContext context) {
    final d = entry.startDate;
    final label =
        '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
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
          const Icon(Icons.schedule_rounded,
              color: AppColors.textMuted, size: 14),
          const SizedBox(width: 8),
          Expanded(
            child: Text(entry.planName,
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary)),
          ),
          Text('starts $label',
              style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textMuted,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _AdminGrantRow extends StatelessWidget {
  final AdminCreditGrant grant;
  const _AdminGrantRow({required this.grant});

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFFFFAB40);
    final d = grant.expiryDate;
    final label =
        '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accent.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.stars_rounded, color: accent, size: 14),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              grant.unlocksAnyClass
                  ? 'Admin credits · unlocks any class until $label'
                  : 'Admin credits · until $label',
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600, color: accent),
            ),
          ),
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
  final bool isBestValue;
  final VoidCallback onSelect;

  const _PlanCard({
    required this.plan,
    required this.color,
    required this.isOwned,
    required this.isBestValue,
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
                      if (plan.badge != null || isBestValue)
                        Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: (plan.badge == null
                                    ? const Color(0xFF00D4AA)
                                    : color)
                                .withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(plan.badge ?? 'BEST VALUE',
                              style: TextStyle(
                                  fontSize: 10,
                                  color: plan.badge == null
                                      ? const Color(0xFF00D4AA)
                                      : color,
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
                    // Buying a plan you already hold is a renewal, not a
                    // duplicate — it queues behind your existing chain for
                    // this plan (see UserService.purchaseMembership), so
                    // the button stays enabled instead of blocking it.
                    onPressed: onSelect,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: color.withValues(alpha: 0.15),
                      foregroundColor: color,
                      elevation: 0,
                      side: BorderSide(color: color.withValues(alpha: 0.4)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text(
                      isOwned ? 'Renew Plan' : 'Purchase Plan',
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

  const _CheckoutSheet({required this.plan});

  @override
  State<_CheckoutSheet> createState() => _CheckoutSheetState();
}

class _CheckoutSheetState extends State<_CheckoutSheet> {
  final _couponCtrl = TextEditingController();
  CouponModel? _appliedCoupon;
  String? _error;
  bool _validating = false;
  // Only true for the brief unfocus/dismiss-animation delay below, not for
  // the purchase itself — this sheet no longer runs the purchase; it just
  // collects the choice and pops with it (see _openCheckout in the parent).
  bool _processing = false;
  // Self-declared by the customer — Stripe's PaymentSheet hides the actual
  // card until after the charge amount is already fixed, so there's no way
  // to detect these automatically before creating the PaymentIntent.
  String _cardRegion = 'domestic';
  String _cardBrand = 'visa_mc';

  Future<void> _confirm() async {
    // If the coupon field still has focus, presenting Stripe's native
    // PaymentSheet while the keyboard is up/mid-dismiss can leave iOS's
    // presentPaymentSheet() hanging indefinitely with no error (a known
    // flutter_stripe/iOS quirk) — unfocus and let the dismiss animation
    // finish first. The purchase itself (including Stripe's sheet) only
    // runs after this sheet has fully popped, in the parent — never while
    // this modal is still open/mid-transition.
    FocusScope.of(context).unfocus();
    setState(() => _processing = true);
    await Future.delayed(const Duration(milliseconds: 300));
    if (mounted) {
      Navigator.pop(
          context, (_appliedCoupon, _finalAmount, _cardRegion, _cardBrand));
    }
  }

  Future<void> _payViaQr() async {
    final submitted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.bg,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _QrPaySheet(
        plan: widget.plan,
        amount: _finalAmount,
        coupon: _appliedCoupon?.code,
      ),
    );
    if (submitted == true && mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
    _couponCtrl.dispose();
    super.dispose();
  }

  double get _finalAmount => _appliedCoupon != null
      ? _appliedCoupon!.applyTo(widget.plan.price)
      : widget.plan.price;

  // Preview only — the actual charge is computed and enforced server-side
  // (see PaymentService.processPayment / functions/index.js
  // createPaymentIntent) once the customer confirms.
  ({double feeAmount, double grossAmount}) get _feeEstimate => estimateCardFee(
        netAmount: _finalAmount,
        cardRegion: _cardRegion,
        cardBrand: _cardBrand,
      );

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
    } catch (e, st) {
      setState(() => _appliedCoupon = null);
      if (mounted) {
        reportError(
          context,
          e,
          st,
          userMessage: friendlyMessage(
              e, 'Could not apply this coupon. Please try again.'),
          reason: 'Coupon validation failed',
        );
      }
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
        bottom: MediaQuery.of(context).viewInsets.bottom +
            MediaQuery.of(context).padding.bottom +
            24,
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
          if (_finalAmount > 0) ...[
            const SizedBox(height: 16),
            const Text('Paying by card',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary)),
            const SizedBox(height: 6),
            _CardTierToggle(
              options: const {'domestic': 'Singapore-issued', 'international': 'International'},
              value: _cardRegion,
              onChanged: (v) => setState(() => _cardRegion = v),
            ),
            const SizedBox(height: 6),
            _CardTierToggle(
              options: const {'visa_mc': 'Visa / Mastercard', 'amex': 'Amex'},
              value: _cardBrand,
              onChanged: (v) => setState(() => _cardBrand = v),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Card processing fee',
                    style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                Text('\$${_feeEstimate.feeAmount.toStringAsFixed(2)}',
                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Total charged to card',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary)),
                Text('\$${_feeEstimate.grossAmount.toStringAsFixed(2)}',
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary)),
              ],
            ),
          ],
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
          if (_finalAmount > 0) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _processing ? null : _payViaQr,
                icon: const Icon(Icons.qr_code_2_outlined, size: 18),
                label: const Text('Pay via QR Code'),
              ),
            ),
          ],
        ],
      ),
      ),
    );
  }
}

/// Two/three-way segmented toggle used for the customer's self-declared card
/// region/brand (see _CheckoutSheetState._cardRegion/_cardBrand) — matches
/// the visual language of _CategoryBar's chips.
class _CardTierToggle extends StatelessWidget {
  final Map<String, String> options;
  final String value;
  final ValueChanged<String> onChanged;

  const _CardTierToggle(
      {required this.options, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: options.entries.map((e) {
        final isSelected = e.key == value;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: e.key != options.keys.last ? 8 : 0),
            child: GestureDetector(
              onTap: () => onChanged(e.key),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppColors.primary.withValues(alpha: 0.15)
                      : AppColors.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isSelected
                        ? AppColors.primary.withValues(alpha: 0.5)
                        : AppColors.divider,
                  ),
                ),
                child: Text(e.value,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                        color: isSelected ? AppColors.primary : AppColors.textSecondary)),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ── Pay via QR code ──────────────────────────────────────────────────────────

class _QrPaySheet extends StatefulWidget {
  final MembershipPlanModel plan;
  final double amount;
  final String? coupon;

  const _QrPaySheet({required this.plan, required this.amount, this.coupon});

  @override
  State<_QrPaySheet> createState() => _QrPaySheetState();
}

class _QrPaySheetState extends State<_QrPaySheet> {
  bool _submitting = false;

  Future<void> _submit() async {
    setState(() => _submitting = true);
    try {
      await QrPaymentService.submitRequest(
        planName: widget.plan.name,
        credits: widget.plan.credits,
        amount: widget.amount,
        validityDays: widget.plan.validityDays,
        note: widget.coupon != null ? 'Coupon: ${widget.coupon}' : '',
      );
      if (mounted) {
        AppToast.success(context,
            "Sent — we'll confirm your payment and activate ${widget.plan.name} shortly");
        Navigator.pop(context, true);
      }
    } catch (e, st) {
      if (mounted) {
        reportError(
          context,
          e,
          st,
          userMessage: friendlyMessage(e,
              'Could not submit your payment request. Please try again.'),
          reason: 'QR payment request submission failed',
        );
      }
      setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom +
            MediaQuery.of(context).padding.bottom +
            24,
      ),
      child: StreamBuilder<Map<String, dynamic>?>(
        stream: QrPaymentService.streamConfig(),
        builder: (context, snap) {
          final imageUrl = snap.data?['imageUrl']?.toString() ?? '';
          final caption = snap.data?['caption']?.toString() ?? '';
          if (snap.connectionState == ConnectionState.waiting) {
            return const SizedBox(
                height: 200,
                child: Center(
                    child: CircularProgressIndicator(color: AppColors.primary)));
          }
          if (imageUrl.isEmpty) {
            return const SizedBox(
              height: 120,
              child: Center(
                child: Text('QR payment is not set up yet — ask admin.',
                    style: TextStyle(color: AppColors.textSecondary)),
              ),
            );
          }
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Pay ${widget.plan.name} · \$${widget.amount.toStringAsFixed(2)}',
                  style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary)),
              const SizedBox(height: 4),
              Text(
                  caption.isNotEmpty
                      ? caption
                      : 'Scan with your banking app to pay',
                  style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
              const SizedBox(height: 16),
              Center(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.divider),
                  ),
                  child: Image.network(imageUrl, height: 240),
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFAB40).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                  border:
                      Border.all(color: const Color(0xFFFFAB40).withValues(alpha: 0.3)),
                ),
                child: const Text(
                  "After scanning and paying, tap the button below. An admin "
                  "will manually confirm the payment before your plan "
                  "activates — this usually happens shortly, not instantly.",
                  style: TextStyle(fontSize: 12, color: Color(0xFFFFAB40)),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _submitting ? null : _submit,
                  child: _submitting
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Text("I've Paid"),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

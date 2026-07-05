import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import '../../models/user_model.dart';
import '../../services/invoice_service.dart';
import '../../services/payment_service.dart';
import '../../services/user_service.dart';
import '../../utils/app_colors.dart';
import '../../utils/app_toast.dart';

class MembershipScreen extends StatefulWidget {
  const MembershipScreen({super.key});

  @override
  State<MembershipScreen> createState() => _MembershipScreenState();
}

class _MembershipScreenState extends State<MembershipScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab;

  static const _categories = [
    _Category(
      title: 'Trials',
      icon: Icons.explore_outlined,
      color: Color(0xFF00D4AA),
      plans: [
        _Plan(name: 'All Class Types Trial', subtitle: 'Explore everything for 30 days', price: 99.00, credits: 4, validityDays: 30, badge: 'First Comers', features: ['Fitness, Boxing, Group PT & Yoga', '4 credits included', 'Cannot be paused or extended']),
        _Plan(name: 'Yoga Trial', subtitle: 'Dip into yoga for 14 days', price: 40.00, credits: 1, validityDays: 14, badge: 'First Comers', features: ['Yoga classes only', '1 credit included', 'Cannot be paused or extended']),
      ],
    ),
    _Category(
      title: 'Drop-In',
      icon: Icons.bolt_outlined,
      color: Color(0xFF4FC3F7),
      plans: [
        _Plan(name: 'Drop-In Class', subtitle: 'One session, maximum flexibility', price: 40.00, credits: 1, validityDays: 7, features: ['60-minute session', 'Any class type', 'No commitment needed']),
      ],
    ),
    _Category(
      title: 'Credits',
      icon: Icons.stars_outlined,
      color: Color(0xFFFFAB40),
      plans: [
        _Plan(name: 'Fighter Credit Pack', subtitle: '20 credits · valid 1 month', price: 302.50, credits: 20, validityDays: 30, badge: 'Popular', features: ['Boxing & fitness classes', 'Use credits flexibly']),
        _Plan(name: 'Stress Relief Package', subtitle: '24 credits · valid 4 months', price: 480.00, credits: 24, validityDays: 120, features: ['Longest validity', 'Great value per credit']),
        _Plan(name: 'Starter Package', subtitle: '8 credits · valid 2 months', price: 280.00, credits: 8, validityDays: 60, features: ['Good for casual members']),
        _Plan(name: 'Student Credit Pack', subtitle: '8 credits · valid 2 months', price: 225.00, credits: 8, validityDays: 60, badge: 'Student', features: ['Discounted rate for students']),
      ],
    ),
    _Category(
      title: 'Monthly',
      icon: Icons.autorenew,
      color: Color(0xFFB388FF),
      plans: [
        _Plan(name: 'Adult 3-Month Recurring', subtitle: 'Billed monthly · 3-month commitment', price: 400.00, priceLabel: '/mo', credits: 44, validityDays: 30, badge: 'Best Value', features: ['Unlimited Boxing & Fitness', '4 Yoga sessions/month', '60-min sessions']),
        _Plan(name: 'Adult 6-Month Recurring', subtitle: 'Billed monthly · 6-month commitment', price: 300.00, priceLabel: '/mo', credits: 44, validityDays: 30, features: ['Unlimited Boxing & Fitness', '4 Yoga sessions/month', '60-min sessions']),
        _Plan(name: 'Kids 3-Month Recurring', subtitle: 'Billed monthly · 3-month commitment', price: 180.00, priceLabel: '/mo', credits: 16, validityDays: 30, features: ['Kids Boxing & Fitness 45-60 min', '4 FREE Yoga sessions/month']),
        _Plan(name: 'Kids 6-Month Recurring', subtitle: 'Billed monthly · 6-month commitment', price: 150.00, priceLabel: '/mo', credits: 16, validityDays: 30, features: ['Kids Boxing & Fitness 45-60 min', '4 FREE Yoga sessions/month']),
      ],
    ),
    _Category(
      title: 'Upfront',
      icon: Icons.workspace_premium_outlined,
      color: Color(0xFFFFD54F),
      plans: [
        _Plan(name: 'Adult 6-Month Upfront', subtitle: '240 credits · valid 6 months', price: 1500.00, credits: 240, validityDays: 180, badge: 'Max Savings', features: ['Unlimited Boxing & Fitness', '4 FREE Yoga sessions/month', 'Best price per credit']),
        _Plan(name: 'Adult 3-Month Upfront', subtitle: '120 credits · valid 3 months', price: 960.00, credits: 120, validityDays: 90, features: ['Unlimited Boxing & Fitness', '4 FREE Yoga sessions/month']),
        _Plan(name: 'Kids 6-Month Upfront', subtitle: '100 credits · valid 6 months', price: 780.00, credits: 100, validityDays: 180, features: ['Kids Boxing, Muay Thai & Fitness', '4 FREE Yoga sessions/month']),
        _Plan(name: 'Kids 3-Month Upfront', subtitle: '50 credits · valid 3 months', price: 450.00, credits: 50, validityDays: 90, features: ['Kids Boxing, Muay Thai & Fitness', '4 FREE Yoga sessions/month']),
      ],
    ),
    _Category(
      title: 'Personal Training',
      icon: Icons.person_outline,
      color: Color(0xFFFF7043),
      plans: [
        _Plan(name: 'PT Pack – Senior Coach', subtitle: '10 x 1-on-1 sessions', price: 1650.00, credits: 10, validityDays: 84, badge: 'Includes 4 Yoga', features: ['Senior certified coach', 'Customized training plan', 'Individual or small group']),
        _Plan(name: 'PT Pack – Junior Coach', subtitle: '10 x 1-on-1 sessions', price: 1150.00, credits: 10, validityDays: 84, features: ['Junior coach', 'Customized training plan', 'Individual or small group']),
        _Plan(name: 'PT Group (Max 5 pax)', subtitle: '10 sessions · up to 5 people', price: 650.00, credits: 10, validityDays: 84, features: ['Small group up to 5', 'Per person pricing', 'Shared personalized attention']),
        _Plan(name: 'PT Drop-In', subtitle: 'Single session, no commitment', price: 175.00, credits: 1, validityDays: 0, features: ['60-minute session', 'No package required']),
      ],
    ),
    _Category(
      title: 'Yoga',
      icon: Icons.self_improvement,
      color: Color(0xFF80CBC4),
      plans: [
        _Plan(name: 'Yoga Flow Credit Pack', subtitle: '4 credits for yoga classes', price: 140.00, credits: 4, validityDays: 60, features: ['Yoga classes only', '4 credits included']),
      ],
    ),
  ];

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: _categories.length, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _purchase(BuildContext context, _Plan plan) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final user = await UserService.getCurrentUser();
    if (user != null) {
      final activePlans = user.memberships.where((m) => m.isActive).toList();
      if (activePlans.length >= 2) {
        if (context.mounted) {
          AppToast.error(context,
              'You already have 2 active plans. Cancel one before purchasing.');
        }
        return;
      }
    }

    if (!context.mounted) return;

    try {
      final paymentIntentId = await PaymentService.processPayment(
        planName: plan.name,
        amount: plan.price,
        currency: 'sgd',
      );

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

      // Record transaction in Google Sheet + send invoice email (non-blocking)
      final currentUser = FirebaseAuth.instance.currentUser;
      InvoiceService.process(
        paymentIntentId: paymentIntentId,
        clientName: currentUser?.displayName ?? 'Member',
        clientEmail: currentUser?.email ?? '',
        planName: plan.name,
        credits: plan.credits,
        amount: plan.price,
        currency: 'SGD',
      );

      if (context.mounted) {
        AppToast.success(
            context, '${plan.name} activated! +${plan.credits} credits added');
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
      appBar: AppBar(
        title: const Text('Membership Plans'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(50),
          child: TabBar(
            controller: _tab,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            indicatorColor: AppColors.primary,
            indicatorWeight: 3,
            dividerColor: AppColors.divider,
            labelColor: AppColors.textPrimary,
            unselectedLabelColor: AppColors.textMuted,
            labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            tabs: _categories
                .map((c) => Tab(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(c.icon, size: 15, color: c.color),
                          const SizedBox(width: 6),
                          Text(c.title),
                        ],
                      ),
                    ))
                .toList(),
          ),
        ),
      ),
      body: uid.isEmpty
          ? const SizedBox()
          : StreamBuilder<UserModel?>(
              stream: UserService.currentUserStream(),
              builder: (ctx, snap) {
                final user = snap.data;
                final activePlans =
                    user?.memberships.where((m) => m.isActive).toList() ?? [];

                return Column(
                  children: [
                    // Credits + active plans banner
                    if (user != null)
                      _CreditsAndPlansBanner(user: user, activePlans: activePlans),
                    Expanded(
                      child: TabBarView(
                        controller: _tab,
                        children: _categories.map((cat) {
                          return ListView.builder(
                            padding:
                                const EdgeInsets.fromLTRB(16, 16, 16, 24),
                            itemCount: cat.plans.length,
                            itemBuilder: (_, i) {
                              final plan = cat.plans[i];
                              final isOwned = activePlans
                                  .any((m) => m.planName == plan.name);
                              return _PlanCard(
                                plan: plan,
                                color: cat.color,
                                isOwned: isOwned,
                                canPurchase: activePlans.length < 2,
                                onSelect: () => _purchase(context, plan),
                              );
                            },
                          );
                        }).toList(),
                      ),
                    ),
                  ],
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
              const Spacer(),
              if (activePlans.length >= 2)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text('2/2 Plans Active',
                      style: TextStyle(
                          fontSize: 11,
                          color: AppColors.error,
                          fontWeight: FontWeight.w700)),
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
    final daysLeft = entry.endDate.difference(DateTime.now()).inDays;
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
  final _Plan plan;
  final Color color;
  final bool isOwned;
  final bool canPurchase;
  final VoidCallback onSelect;

  const _PlanCard({
    required this.plan,
    required this.color,
    required this.isOwned,
    required this.canPurchase,
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
                    onPressed: (isOwned || !canPurchase) ? null : onSelect,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isOwned
                          ? AppColors.divider
                          : !canPurchase
                              ? AppColors.divider
                              : color.withValues(alpha: 0.15),
                      foregroundColor: isOwned || !canPurchase
                          ? AppColors.textMuted
                          : color,
                      elevation: 0,
                      side: BorderSide(
                          color: isOwned || !canPurchase
                              ? AppColors.divider
                              : color.withValues(alpha: 0.4)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text(
                      isOwned
                          ? 'Active Plan'
                          : !canPurchase
                              ? '2 Plans Active (Max)'
                              : 'Purchase Plan',
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

class _Plan {
  final String name;
  final String subtitle;
  final double price;
  final String? priceLabel;
  final int credits;
  final int validityDays;
  final String? badge;
  final List<String> features;

  const _Plan({
    required this.name,
    required this.subtitle,
    required this.price,
    this.priceLabel,
    required this.credits,
    required this.validityDays,
    this.badge,
    this.features = const [],
  });
}

class _Category {
  final String title;
  final IconData icon;
  final Color color;
  final List<_Plan> plans;

  const _Category({
    required this.title,
    required this.icon,
    required this.color,
    required this.plans,
  });
}

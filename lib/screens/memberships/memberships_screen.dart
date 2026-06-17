import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
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
        _Plan(
          name: 'All Class Types Trial',
          subtitle: 'Explore everything for 30 days',
          price: 99.00,
          credits: 4,
          validity: '30 days',
          badge: 'First Comers',
          features: [
            'Fitness, Boxing, Group PT & Yoga',
            '4 credits included',
            'Cannot be paused or extended',
          ],
        ),
        _Plan(
          name: 'Yoga Trial',
          subtitle: 'Dip into yoga for 14 days',
          price: 40.00,
          credits: 1,
          validity: '14 days',
          badge: 'First Comers',
          features: [
            'Yoga classes only',
            '1 credit included',
            'Cannot be paused or extended',
          ],
        ),
      ],
    ),
    _Category(
      title: 'Drop-In',
      icon: Icons.bolt_outlined,
      color: Color(0xFF4FC3F7),
      plans: [
        _Plan(
          name: 'Drop-In Class',
          subtitle: 'One session, maximum flexibility',
          price: 40.00,
          credits: 1,
          validity: '1 week',
          features: [
            '60-minute session',
            'Any class type',
            'No commitment needed',
          ],
        ),
      ],
    ),
    _Category(
      title: 'Credits',
      icon: Icons.stars_outlined,
      color: Color(0xFFFFAB40),
      plans: [
        _Plan(
          name: 'Fighter Credit Pack',
          subtitle: '20 credits · valid 1 month',
          price: 302.50,
          credits: 20,
          validity: '1 month',
          badge: 'Popular',
          features: [
            'Boxing & fitness classes',
            'Use credits flexibly',
          ],
        ),
        _Plan(
          name: 'Stress Relief Package',
          subtitle: '24 credits · valid 4 months',
          price: 480.00,
          credits: 24,
          validity: '4 months',
          features: [
            'Longest validity',
            'Great value per credit',
          ],
        ),
        _Plan(
          name: 'Starter Package',
          subtitle: '8 credits · valid 2 months',
          price: 280.00,
          credits: 8,
          validity: '2 months',
          features: ['Good for casual members'],
        ),
        _Plan(
          name: 'Student Credit Pack',
          subtitle: '8 credits · valid 2 months',
          price: 225.00,
          credits: 8,
          validity: '2 months',
          badge: 'Student',
          features: ['Discounted rate for students'],
        ),
      ],
    ),
    _Category(
      title: 'Monthly',
      icon: Icons.autorenew,
      color: Color(0xFFB388FF),
      plans: [
        _Plan(
          name: 'Adult 3-Month Recurring',
          subtitle: 'Billed monthly · 3-month commitment',
          price: 400.00,
          priceLabel: '/mo',
          credits: 44,
          validity: 'per month',
          badge: 'Best Value',
          features: [
            'Unlimited Boxing & Fitness',
            '4 Yoga sessions/month',
            '60-min sessions',
          ],
        ),
        _Plan(
          name: 'Adult 6-Month Recurring',
          subtitle: 'Billed monthly · 6-month commitment',
          price: 300.00,
          priceLabel: '/mo',
          credits: 44,
          validity: 'per month',
          features: [
            'Unlimited Boxing & Fitness',
            '4 Yoga sessions/month',
            '60-min sessions',
          ],
        ),
        _Plan(
          name: 'Kids 3-Month Recurring',
          subtitle: 'Billed monthly · 3-month commitment',
          price: 180.00,
          priceLabel: '/mo',
          credits: 16,
          validity: 'per month',
          features: [
            'Kids Boxing & Fitness 45-60 min',
            '4 FREE Yoga sessions/month',
          ],
        ),
        _Plan(
          name: 'Kids 6-Month Recurring',
          subtitle: 'Billed monthly · 6-month commitment',
          price: 150.00,
          priceLabel: '/mo',
          credits: 16,
          validity: 'per month',
          features: [
            'Kids Boxing & Fitness 45-60 min',
            '4 FREE Yoga sessions/month',
          ],
        ),
      ],
    ),
    _Category(
      title: 'Upfront',
      icon: Icons.workspace_premium_outlined,
      color: Color(0xFFFFD54F),
      plans: [
        _Plan(
          name: 'Adult 6-Month Upfront',
          subtitle: '240 credits · valid 6 months',
          price: 1500.00,
          credits: 240,
          validity: '6 months',
          badge: 'Max Savings',
          features: [
            'Unlimited Boxing & Fitness',
            '4 FREE Yoga sessions/month',
            'Best price per credit',
          ],
        ),
        _Plan(
          name: 'Adult 3-Month Upfront',
          subtitle: '120 credits · valid 3 months',
          price: 960.00,
          credits: 120,
          validity: '3 months',
          features: [
            'Unlimited Boxing & Fitness',
            '4 FREE Yoga sessions/month',
          ],
        ),
        _Plan(
          name: 'Kids 6-Month Upfront',
          subtitle: '100 credits · valid 6 months',
          price: 780.00,
          credits: 100,
          validity: '6 months',
          features: [
            'Kids Boxing, Muay Thai & Fitness',
            '4 FREE Yoga sessions/month',
          ],
        ),
        _Plan(
          name: 'Kids 3-Month Upfront',
          subtitle: '50 credits · valid 3 months',
          price: 450.00,
          credits: 50,
          validity: '3 months',
          features: [
            'Kids Boxing, Muay Thai & Fitness',
            '4 FREE Yoga sessions/month',
          ],
        ),
      ],
    ),
    _Category(
      title: 'Personal Training',
      icon: Icons.person_outline,
      color: Color(0xFFFF7043),
      plans: [
        _Plan(
          name: 'PT Pack – Senior Coach',
          subtitle: '10 x 1-on-1 sessions',
          price: 1650.00,
          credits: 10,
          validity: '12 weeks',
          badge: 'Includes 4 Yoga',
          features: [
            'Senior certified coach',
            'Customized training plan',
            'Individual or small group',
          ],
        ),
        _Plan(
          name: 'PT Pack – Junior Coach',
          subtitle: '10 x 1-on-1 sessions',
          price: 1150.00,
          credits: 10,
          validity: '12 weeks',
          features: [
            'Junior coach',
            'Customized training plan',
            'Individual or small group',
          ],
        ),
        _Plan(
          name: 'PT Group (Max 5 pax)',
          subtitle: '10 sessions · up to 5 people',
          price: 650.00,
          credits: 10,
          validity: '12 weeks',
          features: [
            'Small group up to 5',
            'Per person pricing',
            'Shared personalized attention',
          ],
        ),
        _Plan(
          name: 'PT Drop-In',
          subtitle: 'Single session, no commitment',
          price: 175.00,
          credits: 1,
          validity: '1 session',
          features: ['60-minute session', 'No package required'],
        ),
      ],
    ),
    _Category(
      title: 'Yoga',
      icon: Icons.self_improvement,
      color: Color(0xFF80CBC4),
      plans: [
        _Plan(
          name: 'Yoga Flow Credit Pack',
          subtitle: '4 credits for yoga classes',
          price: 140.00,
          credits: 4,
          validity: 'See T&Cs',
          features: ['Yoga classes only', '4 credits included'],
        ),
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

  Future<void> _select(String planName) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .set({'membership': planName}, SetOptions(merge: true));
    if (mounted) AppToast.success(context, '$planName selected');
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
      body: FutureBuilder<DocumentSnapshot>(
        future: uid.isEmpty
            ? null
            : FirebaseFirestore.instance.collection('users').doc(uid).get(),
        builder: (ctx, snap) {
          final data = snap.data?.data() as Map<String, dynamic>? ?? {};
          final current = data['membership']?.toString() ?? '';

          return Column(
            children: [
              if (current.isNotEmpty) _ActiveBanner(name: current),
              Expanded(
                child: TabBarView(
                  controller: _tab,
                  children: _categories.map((cat) {
                    return ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                      itemCount: cat.plans.length,
                      itemBuilder: (_, i) => _PlanCard(
                        plan: cat.plans[i],
                        color: cat.color,
                        isActive: cat.plans[i].name == current,
                        onSelect: () => _select(cat.plans[i].name),
                      ),
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

class _ActiveBanner extends StatelessWidget {
  final String name;
  const _ActiveBanner({required this.name});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primary.withValues(alpha: 0.2),
            AppColors.primary.withValues(alpha: 0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          const Icon(Icons.verified_rounded, color: AppColors.primary, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Active Plan',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                Text(name,
                    style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w700)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text('Active',
                style: TextStyle(
                    color: AppColors.primary,
                    fontSize: 11,
                    fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  final _Plan plan;
  final Color color;
  final bool isActive;
  final VoidCallback onSelect;

  const _PlanCard({
    required this.plan,
    required this.color,
    required this.isActive,
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
          color: isActive ? color.withValues(alpha: 0.7) : AppColors.divider,
          width: isActive ? 1.5 : 1,
        ),
      ),
      child: Column(
        children: [
          // Header strip with color
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
                              fontSize: 12, color: AppColors.textSecondary)),
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
                              color: color,
                            ),
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

          // Body
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 14),
            child: Column(
              children: [
                // Validity row
                Row(
                  children: [
                    Icon(Icons.schedule_rounded,
                        size: 13, color: AppColors.textMuted),
                    const SizedBox(width: 6),
                    Text('Valid: ${plan.validity}',
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.textMuted)),
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
                    onPressed: isActive ? null : onSelect,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isActive
                          ? AppColors.divider
                          : color.withValues(alpha: 0.15),
                      foregroundColor: isActive ? AppColors.textMuted : color,
                      elevation: 0,
                      side: BorderSide(
                          color: isActive
                              ? AppColors.divider
                              : color.withValues(alpha: 0.4)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text(
                      isActive ? 'Current Plan' : 'Select Plan',
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
  final String validity;
  final String? badge;
  final List<String> features;

  const _Plan({
    required this.name,
    required this.subtitle,
    required this.price,
    this.priceLabel,
    required this.credits,
    required this.validity,
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

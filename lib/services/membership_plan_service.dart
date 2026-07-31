import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/membership_plan_model.dart';

class MembershipPlanService {
  static final _col = FirebaseFirestore.instance.collection('membershipPlans');

  static Stream<List<MembershipPlanModel>> streamPlans() {
    return _col.orderBy('order').snapshots().map((snap) => snap.docs
        .map((d) => MembershipPlanModel.fromFirestore(d.id, d.data()))
        .toList());
  }

  /// Filters isActive in Dart rather than in the query — an equality filter
  /// combined with orderBy on a different field requires a Firestore
  /// composite index, which isn't provisioned here.
  static Future<List<MembershipPlanModel>> getActivePlans() async {
    final snap = await _col.orderBy('order').get();
    return snap.docs
        .map((d) => MembershipPlanModel.fromFirestore(d.id, d.data()))
        .where((p) => p.isActive)
        .toList();
  }

  static Future<String> createPlan(MembershipPlanModel plan) async {
    final ref = await _col.add(plan.toFirestore());
    return ref.id;
  }

  static Future<void> updatePlan(String id, MembershipPlanModel plan) async {
    await _col.doc(id).update(plan.toFirestore());
  }

  static Future<void> deletePlan(String id) async {
    await _col.doc(id).delete();
  }

  /// One-time migration: if no plans exist yet in Firestore, seeds the
  /// collection with the plans that used to be hardcoded in the client so
  /// existing catalog data isn't lost when switching to admin-managed plans.
  static Future<void> ensureSeeded() async {
    final existing = await _col.limit(1).get();
    if (existing.docs.isNotEmpty) return;

    final batch = FirebaseFirestore.instance.batch();
    var order = 0;
    for (final plan in _seedPlans) {
      final ref = _col.doc();
      batch.set(ref, plan.copyWith(order: order).toFirestore());
      order++;
    }
    await batch.commit();
  }

  static final List<MembershipPlanModel> _seedPlans = [
    const MembershipPlanModel(category: 'Trials', name: 'All Class Types Trial', subtitle: 'Explore everything for 30 days', price: 99.00, credits: 4, validityDays: 30, badge: 'First Comers', features: ['Fitness, Boxing, Group PT & Yoga', '4 credits included', 'Cannot be paused or extended']),
    const MembershipPlanModel(category: 'Trials', name: 'Yoga Trial', subtitle: 'Dip into yoga for 14 days', price: 40.00, credits: 1, validityDays: 14, badge: 'First Comers', features: ['Yoga classes only', '1 credit included', 'Cannot be paused or extended']),
    const MembershipPlanModel(category: 'Drop-In', name: 'Drop-In Class', subtitle: 'One session, maximum flexibility', price: 40.00, credits: 1, validityDays: 7, features: ['60-minute session', 'Any class type', 'No commitment needed']),
    const MembershipPlanModel(category: 'Credits', name: 'Fighter Credit Pack', subtitle: '20 credits · valid 1 month', price: 302.50, credits: 20, validityDays: 30, badge: 'Popular', features: ['Boxing & fitness classes', 'Use credits flexibly']),
    const MembershipPlanModel(category: 'Credits', name: 'Stress Relief Package', subtitle: '24 credits · valid 4 months', price: 480.00, credits: 24, validityDays: 120, features: ['Longest validity', 'Great value per credit']),
    const MembershipPlanModel(category: 'Credits', name: 'Starter Package', subtitle: '8 credits · valid 2 months', price: 280.00, credits: 8, validityDays: 60, features: ['Good for casual members']),
    const MembershipPlanModel(category: 'Credits', name: 'Student Credit Pack', subtitle: '8 credits · valid 2 months', price: 225.00, credits: 8, validityDays: 60, badge: 'Student', features: ['Discounted rate for students']),
    const MembershipPlanModel(category: 'Monthly', name: 'Adult 3-Month Recurring', subtitle: 'Billed monthly · 3-month commitment', price: 400.00, priceLabel: '/mo', credits: 44, validityDays: 30, badge: 'Best Value', features: ['Unlimited Boxing & Fitness', '4 Yoga sessions/month', '60-min sessions']),
    const MembershipPlanModel(category: 'Monthly', name: 'Adult 6-Month Recurring', subtitle: 'Billed monthly · 6-month commitment', price: 300.00, priceLabel: '/mo', credits: 44, validityDays: 30, features: ['Unlimited Boxing & Fitness', '4 Yoga sessions/month', '60-min sessions']),
    const MembershipPlanModel(category: 'Monthly', name: 'Kids 3-Month Recurring', subtitle: 'Billed monthly · 3-month commitment', price: 180.00, priceLabel: '/mo', credits: 16, validityDays: 30, features: ['Kids Boxing & Fitness 45-60 min', '4 FREE Yoga sessions/month']),
    const MembershipPlanModel(category: 'Monthly', name: 'Kids 6-Month Recurring', subtitle: 'Billed monthly · 6-month commitment', price: 150.00, priceLabel: '/mo', credits: 16, validityDays: 30, features: ['Kids Boxing & Fitness 45-60 min', '4 FREE Yoga sessions/month']),
    const MembershipPlanModel(category: 'Upfront', name: 'Adult 6-Month Upfront', subtitle: '240 credits · valid 6 months', price: 1500.00, credits: 240, validityDays: 180, badge: 'Max Savings', features: ['Unlimited Boxing & Fitness', '4 FREE Yoga sessions/month', 'Best price per credit']),
    const MembershipPlanModel(category: 'Upfront', name: 'Adult 3-Month Upfront', subtitle: '120 credits · valid 3 months', price: 960.00, credits: 120, validityDays: 90, features: ['Unlimited Boxing & Fitness', '4 FREE Yoga sessions/month']),
    const MembershipPlanModel(category: 'Upfront', name: 'Kids 6-Month Upfront', subtitle: '100 credits · valid 6 months', price: 780.00, credits: 100, validityDays: 180, features: ['Kids Boxing, Muay Thai & Fitness', '4 FREE Yoga sessions/month']),
    const MembershipPlanModel(category: 'Upfront', name: 'Kids 3-Month Upfront', subtitle: '50 credits · valid 3 months', price: 450.00, credits: 50, validityDays: 90, features: ['Kids Boxing, Muay Thai & Fitness', '4 FREE Yoga sessions/month']),
    const MembershipPlanModel(category: 'Personal Training', name: 'PT Pack – Senior Coach', subtitle: '10 x 1-on-1 sessions', price: 1650.00, credits: 10, validityDays: 84, badge: 'Includes 4 Yoga', features: ['Senior certified coach', 'Customized training plan', 'Individual or small group']),
    const MembershipPlanModel(category: 'Personal Training', name: 'PT Pack – Junior Coach', subtitle: '10 x 1-on-1 sessions', price: 1150.00, credits: 10, validityDays: 84, features: ['Junior coach', 'Customized training plan', 'Individual or small group']),
    const MembershipPlanModel(category: 'Personal Training', name: 'PT Group (Max 5 pax)', subtitle: '10 sessions · up to 5 people', price: 650.00, credits: 10, validityDays: 84, features: ['Small group up to 5', 'Per person pricing', 'Shared personalized attention']),
    const MembershipPlanModel(category: 'Personal Training', name: 'PT Drop-In', subtitle: 'Single session, no commitment', price: 175.00, credits: 1, validityDays: 0, features: ['60-minute session', 'No package required']),
    const MembershipPlanModel(category: 'Yoga', name: 'Yoga Flow Credit Pack', subtitle: '4 credits for yoga classes', price: 140.00, credits: 4, validityDays: 60, features: ['Yoga classes only', '4 credits included']),
  ];
}

extension on MembershipPlanModel {
  MembershipPlanModel copyWith({int? order}) => MembershipPlanModel(
        id: id,
        category: category,
        name: name,
        subtitle: subtitle,
        price: price,
        priceLabel: priceLabel,
        credits: credits,
        validityDays: validityDays,
        badge: badge,
        features: features,
        order: order ?? this.order,
        isActive: isActive,
      );
}

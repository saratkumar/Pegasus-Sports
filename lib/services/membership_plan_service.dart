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

  /// Names of every plan flagged [MembershipPlanModel.isJunior] (active or
  /// not — a retired junior plan's already-purchased credits must stay
  /// junior-only). Purchased memberships only record the plan name, so
  /// that's what junior-ness is matched on.
  static Future<Set<String>> getJuniorPlanNames() async {
    final snap = await _col.where('isJunior', isEqualTo: true).get();
    return snap.docs.map((d) => (d.data()['name'] ?? '').toString()).toSet();
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
}

import { collection, getDocs, orderBy, query } from 'firebase/firestore';
import { db } from './firebase.js';

// Mirrors MembershipPlanService.getActivePlans()
// (lib/services/membership_plan_service.dart:16-22): query membershipPlans
// ordered by `order`, filter isActive client-side (a composite index would
// otherwise be required to do both server-side).
export async function getActivePlans() {
  const q = query(collection(db, 'membershipPlans'), orderBy('order'));
  const snap = await getDocs(q);
  return snap.docs
    .map((d) => ({ id: d.id, ...d.data() }))
    .filter((p) => p.isActive !== false);
}

export function groupPlansByCategory(plans) {
  const groups = new Map();
  for (const plan of plans) {
    const key = plan.category || 'Other';
    if (!groups.has(key)) groups.set(key, []);
    groups.get(key).push(plan);
  }
  return groups;
}

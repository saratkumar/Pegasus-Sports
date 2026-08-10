import { loadStripe } from '@stripe/stripe-js';
import { httpsCallable } from 'firebase/functions';
import {
  addDoc,
  collection,
  doc,
  getDoc,
  runTransaction,
  serverTimestamp,
} from 'firebase/firestore';
import { auth, db, functions } from './firebase.js';

// Safe to include in client code (matches lib/services/payment_service.dart:9).
const STRIPE_PUBLISHABLE_KEY =
  'pk_test_51Tps5X5GDQ6NbhM7JIa90Yh2ce52faber57nbE9GJB4kZFS7QpxjF4nWO0RxNmWcs8kPNWAFX4vG2WcGKt5irYzu00nf4mQiQu';

let stripePromise;
function getStripe() {
  if (!stripePromise) stripePromise = loadStripe(STRIPE_PUBLISHABLE_KEY);
  return stripePromise;
}

function normalizeCode(code) {
  return code.trim().toUpperCase();
}

// Mirrors CouponService.validate() (lib/services/coupon_service.dart:37-49).
// UI feedback only — real enforcement happens server-side in the Cloud
// Functions called below.
export async function validateCoupon(code) {
  const ref = doc(db, 'coupons', normalizeCode(code));
  const snap = await getDoc(ref);
  if (!snap.exists()) throw new Error('Coupon code not found');
  const coupon = { id: snap.id, ...snap.data() };
  if (!coupon.isActive) throw new Error('This coupon is no longer active');
  const expiresAt = coupon.expiresAt?.toDate?.();
  if (expiresAt && new Date() > expiresAt) {
    throw new Error('This coupon has expired');
  }
  if (
    coupon.maxRedemptions != null &&
    (coupon.redeemedCount ?? 0) >= coupon.maxRedemptions
  ) {
    throw new Error('This coupon has reached its redemption limit');
  }
  return coupon;
}

export function applyCoupon(coupon, amount) {
  const discounted =
    coupon.discountType === 'percent'
      ? amount * (1 - coupon.value / 100)
      : amount - coupon.value;
  return Math.max(0, discounted);
}

// Mirrors CouponService.redeem() (lib/services/coupon_service.dart:53-64) —
// only used for the partial-discount (still-charged) path. The free-coupon
// path's redemption is handled atomically inside redeemFreeMembership on
// the server, so this must NOT be called for that path.
async function redeemCoupon(couponId) {
  const ref = doc(db, 'coupons', couponId);
  await runTransaction(db, async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists()) return;
    const coupon = snap.data();
    if (
      coupon.maxRedemptions != null &&
      (coupon.redeemedCount ?? 0) >= coupon.maxRedemptions
    ) {
      throw new Error('This coupon has reached its redemption limit');
    }
    tx.update(ref, { redeemedCount: (coupon.redeemedCount ?? 0) + 1 });
  });
}

function generateInvoiceNumber(paymentRef) {
  const now = new Date();
  const ref = paymentRef.replace(/[^A-Za-z0-9]/g, '');
  const suffix = (ref.length >= 8 ? ref.slice(-8) : ref.padStart(8, '0')).toUpperCase();
  const pad = (n) => String(n).padStart(2, '0');
  return `PSAS-${now.getFullYear()}${pad(now.getMonth() + 1)}${pad(now.getDate())}-${suffix}`;
}

async function recordTransaction({ plan, uid, finalAmount, paymentRef, coupon }) {
  const user = auth.currentUser;
  await addDoc(collection(db, 'transactions'), {
    invoiceNumber: generateInvoiceNumber(paymentRef),
    paymentIntentId: paymentRef,
    clientUid: uid,
    clientName: user?.displayName ?? 'Member',
    clientEmail: user?.email ?? '',
    planName: plan.name,
    credits: plan.credits,
    amount: finalAmount,
    currency: 'SGD',
    validityDays: plan.validityDays,
    ...(coupon ? { couponCode: coupon.code, originalAmount: plan.price } : {}),
    createdAt: serverTimestamp(),
  });
}

// Mounts a Stripe Payment Element into `container` and resolves once the
// card details are ready to be confirmed. `onReady` is called with a
// confirm() function the caller invokes when the user submits.
async function mountPaymentElement(container, clientSecret) {
  const stripe = await getStripe();
  const elements = stripe.elements({ clientSecret });
  const paymentElement = elements.create('payment');
  paymentElement.mount(container);
  return { stripe, elements };
}

// Mirrors _purchase() (lib/screens/memberships/memberships_screen.dart:51-176)
// and PaymentService (lib/services/payment_service.dart) — the widget never
// builds membership documents itself, it only calls the same Cloud
// Functions the native app calls and trusts their result.
export async function purchasePlan({ plan, coupon, finalAmount, paymentContainer }) {
  const uid = auth.currentUser?.uid;
  if (!uid) throw new Error('Sign in required');

  let paymentRef;

  if (finalAmount > 0) {
    const createPaymentIntent = httpsCallable(functions, 'createPaymentIntent');
    const { data } = await createPaymentIntent({
      amount: finalAmount,
      currency: 'sgd',
      planName: plan.name,
    });
    const { clientSecret, paymentIntentId } = data;
    paymentRef = paymentIntentId;

    const { stripe, elements } = await mountPaymentElement(paymentContainer, clientSecret);
    const { error } = await stripe.confirmPayment({
      elements,
      confirmParams: { return_url: window.location.href },
      redirect: 'if_required',
    });
    if (error) throw new Error(error.message ?? 'Payment failed');

    const confirmMembershipPayment = httpsCallable(functions, 'confirmMembershipPayment');
    await confirmMembershipPayment({
      paymentIntentId: paymentRef,
      planName: plan.name,
      credits: plan.credits,
      validityDays: plan.validityDays,
    });

    if (coupon?.id) {
      await redeemCoupon(coupon.id);
    }
  } else {
    if (!coupon) throw new Error('A coupon is required for a free membership');
    paymentRef = `coupon_${Date.now()}`;
    const redeemFreeMembership = httpsCallable(functions, 'redeemFreeMembership');
    await redeemFreeMembership({
      planName: plan.name,
      credits: plan.credits,
      validityDays: plan.validityDays,
      couponCode: coupon.code,
    });
  }

  await recordTransaction({ plan, uid, finalAmount, paymentRef, coupon });
}

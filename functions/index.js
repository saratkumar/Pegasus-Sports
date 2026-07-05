const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { setGlobalOptions } = require("firebase-functions/v2");
const admin = require("firebase-admin");

admin.initializeApp();

// Deploy region — change to your nearest region if needed
setGlobalOptions({ region: "asia-southeast1" });

// Lazily initialise Stripe so the secret key is read at call time,
// not at cold-start (allows key rotation without redeployment).
let _stripe;
function getStripe() {
  if (!_stripe) {
    const key = process.env.STRIPE_SECRET_KEY;
    if (!key) {
      throw new HttpsError(
        "failed-precondition",
        "Stripe secret key is not configured. Set STRIPE_SECRET_KEY in Firebase environment."
      );
    }
    _stripe = require("stripe")(key);
  }
  return _stripe;
}

// ── createPaymentIntent ───────────────────────────────────────────────────────
// Called before showing the Stripe payment sheet.
// Returns { clientSecret, paymentIntentId }
exports.createPaymentIntent = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Must be signed in.");
  }

  const { amount, currency = "sgd", planName } = request.data;

  if (!amount || amount <= 0) {
    throw new HttpsError("invalid-argument", "amount must be a positive number.");
  }

  const stripe = getStripe();
  const paymentIntent = await stripe.paymentIntents.create({
    amount: Math.round(amount * 100), // Stripe uses smallest currency unit (cents)
    currency,
    metadata: {
      userId: request.auth.uid,
      planName,
    },
    automatic_payment_methods: { enabled: true },
  });

  return {
    clientSecret: paymentIntent.client_secret,
    paymentIntentId: paymentIntent.id,
  };
});

// ── confirmMembershipPayment ──────────────────────────────────────────────────
// Called after Stripe confirms the payment client-side.
// Verifies the PaymentIntent with Stripe (prevents forged requests),
// then activates the membership in Firestore.
exports.confirmMembershipPayment = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Must be signed in.");
  }

  const { paymentIntentId, planName, credits, validityDays } = request.data;

  if (!paymentIntentId || !planName || credits == null || validityDays == null) {
    throw new HttpsError("invalid-argument", "Missing required fields.");
  }

  const stripe = getStripe();

  // Verify with Stripe — never trust the client alone
  const paymentIntent = await stripe.paymentIntents.retrieve(paymentIntentId);

  if (paymentIntent.status !== "succeeded") {
    throw new HttpsError(
      "failed-precondition",
      `Payment not completed. Status: ${paymentIntent.status}`
    );
  }

  // Guard against replaying the same PaymentIntent
  const paymentsRef = admin.firestore().collection("payments");
  const existing = await paymentsRef
    .where("paymentIntentId", "==", paymentIntentId)
    .limit(1)
    .get();

  if (!existing.empty) {
    throw new HttpsError("already-exists", "This payment has already been processed.");
  }

  const uid = request.auth.uid;
  const now = admin.firestore.Timestamp.now();
  const endDate = new Date();
  endDate.setDate(endDate.getDate() + (validityDays > 0 ? validityDays : 365));

  const membership = {
    planName,
    credits,
    startDate: now,
    endDate: admin.firestore.Timestamp.fromDate(endDate),
    purchasedAt: now,
  };

  const db = admin.firestore();

  // Check 2-plan limit
  const userDoc = await db.collection("users").doc(uid).get();
  const memberships = userDoc.data()?.memberships ?? [];
  const nowMs = Date.now();
  const activePlans = memberships.filter(
    (m) => m.endDate.toMillis() > nowMs
  );

  if (activePlans.length >= 2) {
    throw new HttpsError(
      "failed-precondition",
      "You already have 2 active plans. Cancel one before purchasing another."
    );
  }

  // Activate membership & record payment atomically
  const batch = db.batch();

  batch.update(db.collection("users").doc(uid), {
    memberships: admin.firestore.FieldValue.arrayUnion(membership),
    credits: admin.firestore.FieldValue.increment(credits),
  });

  batch.set(paymentsRef.doc(), {
    userId: uid,
    paymentIntentId,
    planName,
    amount: paymentIntent.amount / 100,
    currency: paymentIntent.currency,
    credits,
    status: "succeeded",
    createdAt: now,
  });

  await batch.commit();

  return { success: true };
});

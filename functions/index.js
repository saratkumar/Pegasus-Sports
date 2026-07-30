const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { setGlobalOptions } = require("firebase-functions/v2");
const admin = require("firebase-admin");

admin.initializeApp();

// Deploy region — change to your nearest region if needed
setGlobalOptions({ region: "asia-southeast1" });

// Scheduled jobs (membership rollover + renewal reminder emails) — split
// into their own module for readability, re-exported here since Firebase
// only discovers exports from the file named in package.json's "main".
const {
  dailyMembershipRollover,
  dailyRenewalReminders,
  sendRenewalReminderNow,
} = require("./scheduled");
exports.dailyMembershipRollover = dailyMembershipRollover;
exports.dailyRenewalReminders = dailyRenewalReminders;
exports.sendRenewalReminderNow = sendRenewalReminderNow;

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
exports.createPaymentIntent = onCall({ secrets: ["STRIPE_SECRET_KEY"] }, async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Must be signed in.");
  }

  const { amount, currency = "sgd", planName } = request.data;

  if (!amount || amount <= 0) {
    throw new HttpsError("invalid-argument", "amount must be a positive number.");
  }
  if (!planName) {
    throw new HttpsError("invalid-argument", "planName is required.");
  }

  const stripe = getStripe();
  const paymentIntent = await stripe.paymentIntents.create({
    amount: Math.round(amount * 100), // Stripe uses smallest currency unit (cents)
    currency,
    description: planName,
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

// ── membership queueing ─────────────────────────────────────────────────────
// Mirrors UserService._resolveQueueTail/purchaseMembership in
// lib/services/user_service.dart — keep the two in sync if this changes.
// Decides whether a newly purchased plan activates immediately or queues
// behind the user's current chain (nothing disturbs an already-active plan;
// a queued plan's startDate is set to its predecessor's endDate, and it
// only becomes usable once that window ends, or is pulled forward early by
// the client's deductCredit if the predecessor runs out of credits first).
function buildQueuedOrActiveMembership(db, existingMemberships, { planName, credits, validityDays }) {
  const now = Date.now();

  const queued = existingMemberships
    .filter((m) => m.status === "queued")
    .sort((a, b) => a.startDate.toMillis() - b.startDate.toMillis());

  const tail =
    queued.length > 0
      ? queued[queued.length - 1]
      : existingMemberships.find((m) => m.status === "active" && m.endDate.toMillis() > now) || null;

  const startDate = tail ? tail.endDate.toDate() : new Date(now);
  const status = tail ? "queued" : "active";
  const endDate = new Date(startDate);
  endDate.setDate(endDate.getDate() + (validityDays > 0 ? validityDays : 365));

  return {
    id: db.collection("users").doc().id,
    planName,
    credits,
    creditsRemaining: credits,
    status,
    startDate: admin.firestore.Timestamp.fromDate(startDate),
    endDate: admin.firestore.Timestamp.fromDate(endDate),
    purchasedAt: admin.firestore.Timestamp.now(),
  };
}

// ── confirmMembershipPayment ──────────────────────────────────────────────────
// Called after Stripe confirms the payment client-side.
// Verifies the PaymentIntent with Stripe (prevents forged requests),
// then activates the membership in Firestore.
exports.confirmMembershipPayment = onCall({ secrets: ["STRIPE_SECRET_KEY"] }, async (request) => {
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
  const db = admin.firestore();
  const userRef = db.collection("users").doc(uid);

  // Transactional (not a bare batch) since queueing vs. immediate
  // activation depends on reading the user's current membership chain.
  await db.runTransaction(async (tx) => {
    const userSnap = await tx.get(userRef);
    const existing = userSnap.data()?.memberships || [];
    const membership = buildQueuedOrActiveMembership(db, existing, { planName, credits, validityDays });

    tx.update(userRef, {
      memberships: admin.firestore.FieldValue.arrayUnion(membership),
    });

    tx.set(paymentsRef.doc(), {
      userId: uid,
      paymentIntentId,
      planName,
      amount: paymentIntent.amount / 100,
      currency: paymentIntent.currency,
      credits,
      status: "succeeded",
      createdAt: admin.firestore.Timestamp.now(),
    });
  });

  return { success: true };
});

// ── updatePaymentDescription ────────────────────────────────────────────────
// Overwrites a PaymentIntent's description (set to the plan name at creation,
// before the invoice number exists) once the invoice number is known.
exports.updatePaymentDescription = onCall({ secrets: ["STRIPE_SECRET_KEY"] }, async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Must be signed in.");
  }

  const { paymentIntentId, description } = request.data;
  if (!paymentIntentId || !description) {
    throw new HttpsError("invalid-argument", "paymentIntentId and description are required.");
  }

  const stripe = getStripe();
  const pi = await stripe.paymentIntents.retrieve(paymentIntentId);

  // Ownership check: only the purchasing user, or an admin, may edit it.
  if (pi.metadata?.userId !== request.auth.uid) {
    const callerDoc = await admin.firestore().collection("users").doc(request.auth.uid).get();
    if (callerDoc.data()?.role !== "admin") {
      throw new HttpsError("permission-denied", "Not authorized to modify this payment.");
    }
  }

  await stripe.paymentIntents.update(paymentIntentId, { description });
  return { success: true };
});

// ── redeemFreeMembership ────────────────────────────────────────────────────
// Handles the 100%-off-coupon purchase path server-side — validates and
// redeems the coupon and activates the membership atomically, instead of
// trusting the client to have already validated the coupon itself.
exports.redeemFreeMembership = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Must be signed in.");
  }

  const { planName, credits, validityDays, couponCode } = request.data;
  if (!planName || credits == null || validityDays == null || !couponCode) {
    throw new HttpsError("invalid-argument", "Missing required fields.");
  }

  const db = admin.firestore();
  const uid = request.auth.uid;
  const couponRef = db.collection("coupons").doc(couponCode.trim().toUpperCase());
  const userRef = db.collection("users").doc(uid);

  await db.runTransaction(async (tx) => {
    const [couponSnap, userSnap] = await Promise.all([tx.get(couponRef), tx.get(userRef)]);

    if (!couponSnap.exists) {
      throw new HttpsError("not-found", "Coupon not found.");
    }
    const coupon = couponSnap.data();
    const now = Date.now();

    if (coupon.isActive === false) {
      throw new HttpsError("failed-precondition", "This coupon is no longer active.");
    }
    if (coupon.expiresAt && coupon.expiresAt.toMillis() < now) {
      throw new HttpsError("failed-precondition", "This coupon has expired.");
    }
    if (coupon.maxRedemptions != null && (coupon.redeemedCount ?? 0) >= coupon.maxRedemptions) {
      throw new HttpsError("failed-precondition", "This coupon has reached its redemption limit.");
    }

    const nowTs = admin.firestore.Timestamp.now();
    const existing = userSnap.data()?.memberships || [];
    const membership = buildQueuedOrActiveMembership(db, existing, { planName, credits, validityDays });

    tx.update(userRef, {
      memberships: admin.firestore.FieldValue.arrayUnion(membership),
    });
    tx.update(couponRef, {
      redeemedCount: admin.firestore.FieldValue.increment(1),
    });
    tx.set(db.collection("payments").doc(), {
      userId: uid,
      paymentIntentId: `coupon_${couponSnap.id}_${Date.now()}`,
      planName,
      amount: 0,
      currency: "sgd",
      credits,
      status: "free_coupon",
      couponCode: couponSnap.id,
      createdAt: nowTs,
    });
  });

  return { success: true };
});

// ── callAppsScript ───────────────────────────────────────────────────────────
// Proxies requests to the Google Apps Script Web App backing the ActivityLog
// and Transactions Sheet mirror, so the script's URL never ships in the
// client and every call is authenticated/authorized server-side.
const APPS_SCRIPT_ALLOWED_ACTIONS = new Set([
  "log_activity",
  "get_activity_log",
  "record_transaction",
  "get_transactions",
]);

async function callerIsAdmin(uid) {
  const doc = await admin.firestore().collection("users").doc(uid).get();
  return doc.data()?.role === "admin";
}

exports.callAppsScript = onCall({ secrets: ["APPS_SCRIPT_URL"] }, async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Must be signed in.");
  }

  const { action, params = {} } = request.data;
  if (!APPS_SCRIPT_ALLOWED_ACTIONS.has(action)) {
    throw new HttpsError("invalid-argument", `Unsupported action: ${action}`);
  }

  if (action === "get_transactions") {
    if (!(await callerIsAdmin(request.auth.uid))) {
      throw new HttpsError("permission-denied", "Admin only.");
    }
  }
  if (action === "get_activity_log") {
    const targetUid = params.userId;
    if (targetUid) {
      if (targetUid !== request.auth.uid && !(await callerIsAdmin(request.auth.uid))) {
        throw new HttpsError("permission-denied", "Cannot view another user's activity log.");
      }
    } else if (!(await callerIsAdmin(request.auth.uid))) {
      // No userId filter = full-roster fetch (Class Roster screen) — admin only.
      throw new HttpsError("permission-denied", "Admin only.");
    }
  }
  // log_activity / record_transaction: any authenticated user may call —
  // matches today's usage (users log their own bookings/transactions).

  const scriptUrl = process.env.APPS_SCRIPT_URL;
  const url = new URL(scriptUrl);
  url.searchParams.set("action", action);
  for (const [key, value] of Object.entries(params)) {
    url.searchParams.set(key, String(value));
  }

  const res = await fetch(url.toString(), { signal: AbortSignal.timeout(15000) });
  if (!res.ok) {
    throw new HttpsError("unavailable", `Apps Script returned ${res.status}`);
  }
  const text = await res.text();
  try {
    return { data: JSON.parse(text) };
  } catch {
    return { data: text };
  }
});

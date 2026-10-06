const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { onDocumentCreated } = require("firebase-functions/v2/firestore");
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

// ── card processing fee ─────────────────────────────────────────────────────
// The business should net the full (post-discount) plan price even when the
// customer pays by card — Stripe deducts its own fee before the money
// arrives, so the charge itself is grossed up to absorb it. Rates are keyed
// by card region/brand (self-declared by the customer at checkout — Stripe's
// PaymentSheet hides the card until after the amount is already fixed, so
// there's no way to detect it automatically here) so different tiers can be
// tuned independently later without a code change.
// MIRRORED in lib/utils/stripe_fee_estimator.dart (client-side preview only —
// keep the rates and formula identical, or the pre-payment estimate shown to
// the customer will drift from what they're actually charged here).
const CARD_FEE_TIERS = {
  domestic: {
    visa_mc: { percent: 0.034, fixed: 0.50 },
    amex: { percent: 0.034, fixed: 0.50 },
  },
  international: {
    visa_mc: { percent: 0.044, fixed: 0.50 },
    amex: { percent: 0.044, fixed: 0.50 },
  },
};

function computeCardFee(netAmount, cardRegion, cardBrand) {
  const tier = CARD_FEE_TIERS[cardRegion]?.[cardBrand];
  if (!tier) {
    throw new HttpsError(
      "invalid-argument",
      `Unknown card tier: ${cardRegion}/${cardBrand}`
    );
  }
  // grossAmount * (1 - percent) - fixed = netAmount, solved for grossAmount,
  // rounded UP to the nearest cent so the net proceeds are never short by a
  // cent after Stripe's own rounding.
  const rawGross = (netAmount + tier.fixed) / (1 - tier.percent);
  const grossAmount = Math.ceil(rawGross * 100) / 100;
  const feeAmount = Math.round((grossAmount - netAmount) * 100) / 100;
  return { feeAmount, grossAmount };
}

// ── createPaymentIntent ───────────────────────────────────────────────────────
// Called before showing the Stripe payment sheet.
// Returns { clientSecret, paymentIntentId, netAmount, feeAmount, grossAmount,
// publishableKey }. The publishable key is served from the
// STRIPE_PUBLISHABLE_KEY secret (not compiled into the app) so it always
// pairs with STRIPE_SECRET_KEY — test/live is switched server-side only.
// ── junior packages ─────────────────────────────────────────────────────────
// Mirrors the app's DependentModel/MembershipPlanModel.isJunior rule: a plan
// flagged isJunior may only be bought by an account holding an active child
// profile aged 6–17. Enforced here, before any charge, so it also covers
// app versions released before the in-app check existed.
const JUNIOR_MIN_AGE = 6;
const JUNIOR_MAX_AGE_EXCLUSIVE = 18;

function ageOn(dob, on) {
  let age = on.getFullYear() - dob.getFullYear();
  if (on.getMonth() < dob.getMonth() ||
      (on.getMonth() === dob.getMonth() && on.getDate() < dob.getDate())) {
    age--;
  }
  return age;
}

async function assertJuniorEligible(uid, planName) {
  const db = admin.firestore();
  const plans = await db.collection("membershipPlans")
    .where("name", "==", planName).limit(1).get();
  if (plans.empty || plans.docs[0].get("isJunior") !== true) return;

  const children = await db.collection("users").doc(uid)
    .collection("dependents").where("isActive", "==", true).get();
  const now = new Date();
  const rightAge = children.docs.filter((d) => {
    const dob = d.get("dateOfBirth");
    if (!dob) return false;
    const age = ageOn(dob.toDate(), now);
    return age >= JUNIOR_MIN_AGE && age < JUNIOR_MAX_AGE_EXCLUSIVE;
  });
  // Staff must have approved the child (see onDependentCreated) — a
  // self-declared profile alone isn't proof a child exists.
  if (rightAge.some((d) => d.get("verificationStatus") === "verified")) return;
  throw new HttpsError(
    "failed-precondition",
    rightAge.some((d) => d.get("verificationStatus") !== "rejected")
      ? "Your child's profile is awaiting approval by our staff. Junior packages unlock once it's approved."
      : "Junior packages are for children aged 6–17. Add your child in My Family first."
  );
}

// ── onDependentCreated ──────────────────────────────────────────────────────
// Every child profile a parent adds needs staff approval before junior
// packages can be bought/used for it. Filing the request server-side (not
// from the app) means it also happens for children added from app builds
// released before verification existed. Children added by an admin arrive
// already verified and are skipped.
exports.onDependentCreated = onDocumentCreated("users/{uid}/dependents/{childId}", async (event) => {
  const child = event.data?.data();
  if (!child || child.verificationStatus === "verified") return;

  const db = admin.firestore();
  const { uid, childId } = event.params;
  const parentSnap = await db.collection("users").doc(uid).get();
  const parent = parentSnap.data() || {};
  const parentName = parent.name || parent.email || "Member";

  const dob = child.dateOfBirth?.toDate();
  const age = dob ? ageOn(dob, new Date()) : null;
  const dobText = dob
    ? `${String(dob.getDate()).padStart(2, "0")}/${String(dob.getMonth() + 1).padStart(2, "0")}/${dob.getFullYear()} (age ${age})`
    : "not given";

  await db.collection("adminRequests").add({
    type: "child_verification",
    requestedBy: uid,
    requestedByName: parentName,
    targetUserId: uid,
    targetUserName: parentName,
    attendeeId: childId,
    attendeeName: child.name || "",
    amount: 0,
    status: "pending",
    note: `Date of birth: ${dobText} · ${child.relationship || "Parent"}`,
    createdAt: admin.firestore.Timestamp.now(),
  });

  // Names are parent-typed text going into an HTML email — escape them.
  const esc = (v) => String(v ?? "").replace(/[&<>"']/g, (c) =>
    ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));

  const admins = await db.collection("users").where("role", "==", "admin").get();
  const emails = admins.docs.map((d) => d.get("email")).filter(Boolean);
  if (emails.length === 0) return;
  await db.collection("mail").add({
    to: emails,
    message: {
      subject: `New Child Verification — ${String(parentName).slice(0, 80)}`,
      html: `
        <div style="font-family: sans-serif; color: #0A0A0A;">
          <h2 style="color: #FF7A00;">New Child Verification</h2>
          <p><strong>${esc(parentName)}</strong> added a child to their account:</p>
          <p><strong>${esc(child.name)}</strong> — date of birth ${dobText}</p>
          <p>Approve or reject it in the admin app under Requests. Junior
          packages can't be bought or used for this child until it's approved.</p>
        </div>`,
    },
  });
});

// Shared by createPaymentIntent (mobile PaymentSheet) and
// createCheckoutSession (web Checkout) so both enforce identical validation
// and server-side fee math. Returns the metadata to stamp on the
// PaymentIntent — confirmMembershipPayment later trusts it, since it was
// written here, not supplied by the client.
function preparePayment(request) {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Must be signed in.");
  }

  const { netAmount, currency = "sgd", planName, cardRegion, cardBrand } = request.data;

  if (!netAmount || netAmount <= 0) {
    throw new HttpsError("invalid-argument", "netAmount must be a positive number.");
  }
  if (!planName) {
    throw new HttpsError("invalid-argument", "planName is required.");
  }
  if (!cardRegion || !cardBrand) {
    throw new HttpsError("invalid-argument", "cardRegion and cardBrand are required.");
  }

  // Fee math happens here, not on the client — the client only declares the
  // card tier, the server is the sole authority on the resulting charge.
  const { feeAmount, grossAmount } = computeCardFee(netAmount, cardRegion, cardBrand);

  return {
    netAmount,
    currency,
    planName,
    feeAmount,
    grossAmount,
    metadata: {
      userId: request.auth.uid,
      planName,
      netAmount: netAmount.toFixed(2),
      feeAmount: feeAmount.toFixed(2),
      cardRegion,
      cardBrand,
    },
  };
}

exports.createPaymentIntent = onCall({ secrets: ["STRIPE_SECRET_KEY", "STRIPE_PUBLISHABLE_KEY"] }, async (request) => {
  const { netAmount, currency, planName, feeAmount, grossAmount, metadata } = preparePayment(request);
  await assertJuniorEligible(request.auth.uid, planName);

  const publishableKey = process.env.STRIPE_PUBLISHABLE_KEY;
  if (!publishableKey) {
    throw new HttpsError("failed-precondition", "Stripe publishable key is not configured.");
  }

  const stripe = getStripe();
  const paymentIntent = await stripe.paymentIntents.create({
    amount: Math.round(grossAmount * 100), // Stripe uses smallest currency unit (cents)
    currency,
    description: planName,
    metadata,
    automatic_payment_methods: { enabled: true },
  });

  return {
    clientSecret: paymentIntent.client_secret,
    paymentIntentId: paymentIntent.id,
    netAmount,
    feeAmount,
    grossAmount,
    publishableKey,
  };
});

// ── createCheckoutSession (web) ─────────────────────────────────────────────
// The mobile PaymentSheet has no Flutter web implementation, so the web shop
// pays through a Stripe-hosted Checkout page instead (opened in a new tab —
// Checkout refuses to render inside the iframe the shop is embedded in).
// Same validation/fee/metadata as createPaymentIntent; the resulting
// PaymentIntent is then confirmed through the same confirmMembershipPayment.
const CHECKOUT_RETURN_PAGE = "https://psas-shop.web.app/checkout-complete.html";

exports.createCheckoutSession = onCall({ secrets: ["STRIPE_SECRET_KEY"] }, async (request) => {
  const { netAmount, currency, planName, feeAmount, grossAmount, metadata } = preparePayment(request);
  await assertJuniorEligible(request.auth.uid, planName);

  const stripe = getStripe();
  const session = await stripe.checkout.sessions.create({
    mode: "payment",
    client_reference_id: request.auth.uid,
    ...(request.auth.token.email && { customer_email: request.auth.token.email }),
    line_items: [{
      quantity: 1,
      price_data: {
        currency,
        unit_amount: Math.round(grossAmount * 100),
        product_data: { name: planName },
      },
    }],
    payment_intent_data: { description: planName, metadata },
    metadata,
    success_url: `${CHECKOUT_RETURN_PAGE}?status=success`,
    cancel_url: `${CHECKOUT_RETURN_PAGE}?status=cancel`,
    // Stripe's minimum; an abandoned page stops accepting payment soon after.
    expires_at: Math.floor(Date.now() / 1000) + 30 * 60,
  });

  return { url: session.url, sessionId: session.id, netAmount, feeAmount, grossAmount };
});

// ── getCheckoutSession (web) ────────────────────────────────────────────────
// Polled by the web shop while the Checkout tab is open. Only the user who
// created the session may read it.
exports.getCheckoutSession = onCall({ secrets: ["STRIPE_SECRET_KEY"] }, async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Must be signed in.");
  }
  const { sessionId } = request.data || {};
  if (!sessionId) {
    throw new HttpsError("invalid-argument", "sessionId is required.");
  }
  const session = await getStripe().checkout.sessions.retrieve(sessionId);
  if (session.client_reference_id !== request.auth.uid) {
    throw new HttpsError("permission-denied", "Not your checkout session.");
  }
  return {
    status: session.status, // open | complete | expired
    paymentStatus: session.payment_status, // paid | unpaid | no_payment_required
    paymentIntentId: session.payment_intent || null,
  };
});

// ── membership queueing ─────────────────────────────────────────────────────
// Mirrors UserService._resolveQueueTail/purchaseMembership in
// lib/services/user_service.dart — keep the two in sync if this changes.
// Decides whether a newly purchased plan activates immediately or queues
// behind the user's current chain FOR THAT SAME PLAN NAME (every plan
// follows its own route; a different plan's active/queued entries never
// affect this one). Nothing disturbs an already-active plan; a queued
// plan's startDate is set to its predecessor's endDate, and it only
// becomes usable once that window ends, or is pulled forward early by the
// client's deductCredit if the predecessor runs out of credits first).
function buildQueuedOrActiveMembership(db, existingMemberships, { planName, credits, validityDays }) {
  const now = Date.now();
  const sameChain = existingMemberships.filter((m) => m.planName === planName);

  const queued = sameChain
    .filter((m) => m.status === "queued")
    .sort((a, b) => a.startDate.toMillis() - b.startDate.toMillis());

  const tail =
    queued.length > 0
      ? queued[queued.length - 1]
      : sameChain.find((m) => m.status === "active" && m.endDate.toMillis() > now) || null;

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

    // netAmount/feeAmount/cardRegion/cardBrand were set server-side in
    // createPaymentIntent, so reading them back off the verified
    // PaymentIntent's metadata is trusted — not client-supplied here.
    const meta = paymentIntent.metadata || {};
    tx.set(paymentsRef.doc(), {
      userId: uid,
      paymentIntentId,
      planName,
      amount: paymentIntent.amount / 100,
      currency: paymentIntent.currency,
      credits,
      status: "succeeded",
      createdAt: admin.firestore.Timestamp.now(),
      ...(meta.netAmount != null && { netAmount: Number(meta.netAmount) }),
      ...(meta.feeAmount != null && { feeAmount: Number(meta.feeAmount) }),
      ...(meta.cardRegion != null && { cardRegion: meta.cardRegion }),
      ...(meta.cardBrand != null && { cardBrand: meta.cardBrand }),
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
  await assertJuniorEligible(request.auth.uid, planName);

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

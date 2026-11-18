const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { onDocumentCreated, onDocumentWritten } = require("firebase-functions/v2/firestore");
const { setGlobalOptions } = require("firebase-functions/v2");
const admin = require("firebase-admin");
const { Timestamp, FieldValue } = require("firebase-admin/firestore");
const { buildInvitationEmail } = require("./emailTemplates");

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

// True when running in the local Firebase emulator (docs/testing-locally.md).
// Anything that would reach live Stripe or the live Google Sheet is switched
// off there; Firestore/Auth are the emulator's own copies.
const IS_EMULATOR = process.env.FUNCTIONS_EMULATOR === "true";

// Lazily initialise Stripe so the secret key is read at call time,
// not at cold-start (allows key rotation without redeployment).
let _stripe;
function getStripe() {
  if (IS_EMULATOR) {
    throw new HttpsError("failed-precondition", "Card payments are off in local test mode.");
  }
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

// Sign-up is invite-only (firestore.rules users/{uid} create): a signed-in
// account without a users/{uid} profile is a stranger or an anonymous web
// shop session, so refuse BEFORE charging — otherwise Stripe takes the money
// and the later membership grant (a tx.update on that missing doc) fails.
async function assertMember(uid) {
  const snap = await admin.firestore().collection("users").doc(uid).get();
  if (!snap.exists) {
    throw new HttpsError("permission-denied",
      "This account isn't registered with PSAS. Please contact the gym to get access.");
  }
  if (snap.get("isActive") === false) {
    throw new HttpsError("permission-denied",
      "This account is inactive. Please contact the gym to reactivate your membership.");
  }
  // Minors can't make payments — the parent buys junior packages for them.
  if (snap.get("role") === "junior") {
    throw new HttpsError("permission-denied",
      "Junior accounts can't make payments. Please ask your parent or guardian to buy a package for you.");
  }
}

// Junior packages are bought by the parent but assigned to ONE child, whose
// profile (users/{uid}/dependents/{dependentId}) then holds the package — so
// only that child's bookings can use it. For a junior plan this requires a
// dependentId naming an active, staff-approved child of THIS parent aged
// 6–17, and returns it; for any other plan it returns null (a stray
// dependentId is ignored, so an adult plan can never land on a child).
async function assertJuniorEligible(uid, planName, dependentId) {
  const db = admin.firestore();
  const plans = await db.collection("membershipPlans")
    .where("name", "==", planName).limit(1).get();
  if (plans.empty || plans.docs[0].get("isJunior") !== true) return null;

  if (!dependentId || typeof dependentId !== "string") {
    // App builds from before packages were per-child don't send one.
    throw new HttpsError("failed-precondition",
      "Please update the app to buy a junior package for your child.");
  }
  const child = await db.collection("users").doc(uid)
    .collection("dependents").doc(dependentId).get();
  if (!child.exists || child.get("isActive") === false) {
    throw new HttpsError("failed-precondition",
      "Junior packages are for children aged 6–17. Add your child in My Family first.");
  }
  // Staff must have approved the child (see onDependentCreated) — a
  // self-declared profile alone isn't proof a child exists.
  if (child.get("verificationStatus") !== "verified") {
    throw new HttpsError("failed-precondition",
      child.get("verificationStatus") === "rejected"
        ? "This child's profile wasn't approved, so junior packages can't be bought for them. Please contact the gym."
        : "Your child's profile is awaiting approval by our staff. Junior packages unlock once it's approved.");
  }
  const dob = child.get("dateOfBirth");
  const age = dob ? ageOn(dob.toDate(), new Date()) : -1;
  if (age < JUNIOR_MIN_AGE || age >= JUNIOR_MAX_AGE_EXCLUSIVE) {
    throw new HttpsError("failed-precondition",
      "Junior packages are for children aged 6–17.");
  }
  return dependentId;
}

// Where a purchased plan is stored: the parent's own doc, or — for a
// junior package — the child it was bought for.
function walletRef(db, uid, dependentId) {
  const userRef = db.collection("users").doc(uid);
  return dependentId ? userRef.collection("dependents").doc(dependentId) : userRef;
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
    createdAt: Timestamp.now(),
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
  await assertMember(request.auth.uid);
  const dependentId = await assertJuniorEligible(request.auth.uid, planName, request.data?.dependentId);
  // Carried on the PaymentIntent so confirmMembershipPayment knows which
  // child the package is for without trusting the client a second time.
  if (dependentId) metadata.dependentId = dependentId;

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
  await assertMember(request.auth.uid);
  const dependentId = await assertJuniorEligible(request.auth.uid, planName, request.data?.dependentId);
  if (dependentId) metadata.dependentId = dependentId;

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
    startDate: Timestamp.fromDate(startDate),
    endDate: Timestamp.fromDate(endDate),
    purchasedAt: Timestamp.now(),
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
  // netAmount/feeAmount/cardRegion/cardBrand/dependentId were set
  // server-side in createPaymentIntent, so reading them back off the
  // verified PaymentIntent's metadata is trusted — not client-supplied here.
  const meta = paymentIntent.metadata || {};
  if (meta.userId && meta.userId !== uid) {
    throw new HttpsError("permission-denied", "This payment belongs to another account.");
  }
  // A junior package goes onto the child it was bought for (validated when
  // the PaymentIntent was created).
  const dependentId = meta.dependentId || null;
  const userRef = walletRef(db, uid, dependentId);

  // Transactional (not a bare batch) since queueing vs. immediate
  // activation depends on reading the current membership chain.
  await db.runTransaction(async (tx) => {
    const userSnap = await tx.get(userRef);
    if (!userSnap.exists) {
      throw new HttpsError("failed-precondition", "Account or child profile not found.");
    }
    const existing = userSnap.data()?.memberships || [];
    const membership = buildQueuedOrActiveMembership(db, existing, { planName, credits, validityDays });

    tx.update(userRef, {
      memberships: FieldValue.arrayUnion(membership),
    });

    tx.set(paymentsRef.doc(), {
      userId: uid,
      ...(dependentId && { dependentId }),
      paymentIntentId,
      planName,
      amount: paymentIntent.amount / 100,
      currency: paymentIntent.currency,
      credits,
      status: "succeeded",
      createdAt: Timestamp.now(),
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
  await assertMember(request.auth.uid);
  const dependentId = await assertJuniorEligible(request.auth.uid, planName, request.data?.dependentId);

  const db = admin.firestore();
  const uid = request.auth.uid;
  const couponRef = db.collection("coupons").doc(couponCode.trim().toUpperCase());
  const userRef = walletRef(db, uid, dependentId);

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

    const nowTs = Timestamp.now();
    const existing = userSnap.data()?.memberships || [];
    const membership = buildQueuedOrActiveMembership(db, existing, { planName, credits, validityDays });

    tx.update(userRef, {
      memberships: FieldValue.arrayUnion(membership),
    });
    tx.update(couponRef, {
      redeemedCount: FieldValue.increment(1),
    });
    tx.set(db.collection("payments").doc(), {
      userId: uid,
      ...(dependentId && { dependentId }),
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

// ── onDependentWritten: a child's own login ────────────────────────────────
// A parent (or staff) can give a child profile a loginEmail. Once the child
// is approved, active and 6–17, an invitation goes to that email (and the
// invitation email via onInvitationCreated); signing in with it creates a
// junior account linked to this profile (see onUserCreated). If the child
// is removed, rejected, ages out, or the email is cleared/changed, the
// pending invitation is withdrawn and an already-linked junior account is
// deactivated — the profile, packages and history stay, and restoring the
// same email reactivates the same account.
exports.onDependentWritten = onDocumentWritten("users/{uid}/dependents/{childId}", async (event) => {
  const before = event.data?.before?.data() || null;
  const after = event.data?.after?.data() || null;
  const { uid, childId } = event.params;
  const db = admin.firestore();
  const norm = (v) => String(v || "").trim().toLowerCase();

  const oldEmail = norm(before?.loginEmail);
  const newEmail = after ? norm(after.loginEmail) : "";
  const dob = after?.dateOfBirth?.toDate?.();
  const age = dob ? ageOn(dob, new Date()) : -1;
  const wantsLogin = !!after && after.isActive !== false &&
    after.verificationStatus === "verified" && newEmail.includes("@") &&
    age >= JUNIOR_MIN_AGE && age < JUNIOR_MAX_AGE_EXCLUSIVE;

  // Withdraw an unused invitation that was issued for THIS child.
  async function withdrawInvite(email) {
    if (!email) return;
    const ref = db.collection("invitations").doc(email);
    const inv = await ref.get();
    if (inv.exists && inv.get("dependentId") === childId && inv.get("parentUid") === uid) {
      await ref.delete();
    }
  }
  async function setJuniorActive(juniorUid, active) {
    const ref = db.collection("users").doc(juniorUid);
    const snap = await ref.get();
    if (snap.exists && snap.get("isActive") !== active) await ref.update({ isActive: active });
  }

  if (oldEmail && oldEmail !== newEmail) await withdrawInvite(oldEmail);

  const linkedUid = after?.linkedUid || null;
  if (linkedUid) {
    const linked = await db.collection("users").doc(linkedUid).get();
    const linkedEmail = norm(linked.get("email"));
    if (!wantsLogin || linkedEmail !== newEmail) {
      await setJuniorActive(linkedUid, false);
      // Email changed to a different address: that is a new login, so the
      // old account stays deactivated and the new email is invited below.
      if (wantsLogin && linkedEmail !== newEmail) {
        await event.data.after.ref.update({ linkedUid: FieldValue.delete() });
      } else {
        return;
      }
    } else {
      await setJuniorActive(linkedUid, true);
      return;
    }
  }

  if (!wantsLogin) {
    await withdrawInvite(newEmail);
    return;
  }

  // Already invited for this child — nothing to do (avoids re-sending).
  const invRef = db.collection("invitations").doc(newEmail);
  const inv = await invRef.get();
  if (inv.exists && inv.get("dependentId") === childId) return;
  if (inv.exists) {
    // Someone else's invitation already uses this email.
    await event.data.after.ref.update({ loginEmailStatus: "email-in-use" });
    return;
  }
  const existing = await db.collection("users").where("email", "==", newEmail).limit(1).get();
  if (!existing.empty) {
    await event.data.after.ref.update({ loginEmailStatus: "email-in-use" });
    return;
  }

  await invRef.set({
    email: newEmail,
    name: after.name || "",
    phone: "",
    role: "junior",
    parentUid: uid,
    dependentId: childId,
    initialCredits: 0,
    createdAt: Timestamp.now(),
  });
  if (after.loginEmailStatus) {
    await event.data.after.ref.update({ loginEmailStatus: FieldValue.delete() });
  }
});

// ── onInvitationCreated: email the invited person ──────────────────────────
// Sign-up is invite-only, so without this an invited person has no way to
// know they can sign in (or which email to use). Queued through the same
// `mail` collection the Trigger Email extension sends from. Runs on
// create only, so editing an invitation doesn't re-send it.
exports.onInvitationCreated = onDocumentCreated("invitations/{email}", async (event) => {
  const inv = event.data?.data();
  const to = String(inv?.email || event.params.email || "").trim().toLowerCase();
  if (!to || !to.includes("@")) return;

  const db = admin.firestore();
  // Already has a working account (not just an imported placeholder) —
  // the invitation won't be used, so don't tell them to "get started".
  const existing = await db.collection("users").where("email", "==", to).get();
  if (existing.docs.some((d) => d.get("importedPending") !== true)) {
    await event.data.ref.update({ emailSkipped: "existing-account" });
    return;
  }

  await db.collection("mail").add(buildInvitationEmail({ to, name: inv.name, role: inv.role }));
  await event.data.ref.update({ emailQueuedAt: Timestamp.now() });
});

// ── onUserCreated: hand imported members their data ────────────────────────
// Members migrated from Glofox were imported as users/{autoId} docs flagged
// importedPending (they had no sign-in account yet), so admins see them in
// User Management with their plans, credits and children. When that person
// first signs in, the app creates users/{authUid} — this moves everything
// from the imported doc onto it (including anything an admin changed or
// booked in the meantime) and deletes the imported doc.
exports.onUserCreated = onDocumentCreated("users/{uid}", async (event) => {
  const created = event.data?.data();
  if (!created || created.importedPending) return;

  // A child's first sign-in: record which account is theirs on the child
  // profile (the junior account can't write the parent's data itself).
  if (created.role === "junior" && created.parentUid && created.dependentId) {
    await admin.firestore().collection("users").doc(created.parentUid)
      .collection("dependents").doc(created.dependentId)
      .update({ linkedUid: event.params.uid, linkedAt: Timestamp.now() })
      .catch((e) => console.error("Could not link junior account", e));
    return;
  }
  const email = String(created.email || "").trim().toLowerCase();
  if (!email) return;

  const db = admin.firestore();
  const uid = event.params.uid;
  const matches = await db.collection("users").where("email", "==", email).get();
  const imported = matches.docs.find((d) => d.id !== uid && d.get("importedPending") === true);
  if (!imported) return;
  const importedRef = imported.ref;
  const userRef = db.collection("users").doc(uid);

  const children = await importedRef.collection("dependents").get();

  await db.runTransaction(async (tx) => {
    const [impSnap, userSnap] = await Promise.all([tx.get(importedRef), tx.get(userRef)]);
    if (!impSnap.exists || !userSnap.exists) return;
    const imp = impSnap.data();
    const user = userSnap.data();

    // One active entry per plan name (app invariant) — top up if the new
    // account somehow already holds the same active plan.
    const memberships = [...(user.memberships || [])];
    for (const m of imp.memberships || []) {
      const same = memberships.findIndex((x) => x.planName === m.planName && x.status === "active");
      if (same !== -1 && m.status === "active") {
        const remaining = (memberships[same].creditsRemaining || 0) + (m.creditsRemaining || 0);
        memberships[same] = { ...memberships[same], creditsRemaining: remaining,
          credits: Math.max(memberships[same].credits || 0, remaining) };
      } else {
        memberships.push(m);
      }
    }

    const update = {
      memberships,
      credits: (user.credits || 0) + (imp.credits || 0),
      importSource: imp.importSource || "import",
    };
    if (imp.adminCreditGrant && !user.adminCreditGrant) update.adminCreditGrant = imp.adminCreditGrant;
    if (!user.phone && imp.phone) update.phone = imp.phone;
    if (!user.name && imp.name) update.name = imp.name;
    tx.update(userRef, update);

    for (const c of children.docs) {
      tx.set(userRef.collection("dependents").doc(c.id), c.data());
      tx.delete(c.ref);
    }
    tx.delete(importedRef);
  });

  // Re-point anything booked against the imported doc in the meantime.
  for (const col of ["bookings", "waitingList", "transactions", "payments"]) {
    const field = col === "transactions" ? "clientUid" : "userId";
    const snap = await db.collection(col).where(field, "==", imported.id).get();
    if (snap.empty) continue;
    const batch = db.batch();
    snap.docs.forEach((d) => batch.update(d.ref, { [field]: uid }));
    await batch.commit();
  }
});

async function callerIsAdmin(uid) {
  const doc = await admin.firestore().collection("users").doc(uid).get();
  return doc.data()?.role === "admin" && doc.data()?.isActive !== false;
}

exports.callAppsScript = onCall({ secrets: ["APPS_SCRIPT_URL"] }, async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Must be signed in.");
  }

  const { action, params = {} } = request.data;
  if (IS_EMULATOR) {
    // Would write test activity into the live Sheet.
    throw new HttpsError("unavailable", "Activity Log is off in local test mode.");
  }
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
  let data;
  try {
    data = JSON.parse(text);
  } catch {
    return { data: text };
  }
  if (action === "get_activity_log") data = fixSheetSessionTimes(data);
  return { data };
});

// Google Sheets turns a logged session time like "7:00 PM" into a time value,
// which the Apps Script returns as a date on Sheets' day zero
// ("1899-12-30T12:04:35.000Z"). App rosters match bookings to classes by that
// text, so every app version — including ones already in the stores — got
// extra "1899" sessions. Convert those back to the "h:mm AM/PM" the app
// writes. Asia/Singapore (the Sheet's zone) includes its 1899 offset, so
// 12:04:35Z comes back as exactly 7:00 PM.
const SHEETS_DAY_ZERO_TIME = /^1899-12-3[01]T\d{2}:\d{2}:\d{2}(\.\d+)?Z$/;
const sessionTimeFormat = new Intl.DateTimeFormat("en-US", {
  timeZone: "Asia/Singapore",
  hour: "numeric",
  minute: "2-digit",
  hour12: true,
});

function fixSheetSessionTimes(data) {
  const fixRow = (row) => {
    if (!row || typeof row !== "object") return row;
    const t = row.sessionTime;
    if (typeof t !== "string" || !SHEETS_DAY_ZERO_TIME.test(t)) return row;
    return { ...row, sessionTime: sessionTimeFormat.format(new Date(t)).replace(/ /g, " ") };
  };
  if (Array.isArray(data)) return data.map(fixRow);
  if (data && Array.isArray(data.data)) return { ...data, data: data.data.map(fixRow) };
  return data;
}

// ── uploadCoachPhoto ─────────────────────────────────────────────────────────
// Admin uploads a trainer/admin profile photo from the app. The image is
// handed to the same Apps Script Web App (doPost, action
// "upload_coach_photo"), which runs as the Drive owner, saves it into the
// "Pegasus Coach Photos" folder shared as "anyone with the link", and
// returns the file id. The app then saves the resulting link plus the
// description on the user's doc when the admin taps Save.
const COACH_PHOTO_MAX_BYTES = 5 * 1024 * 1024;
const COACH_PHOTO_TYPES = new Set(["image/jpeg", "image/png", "image/webp", "image/heic"]);

exports.uploadCoachPhoto = onCall({ secrets: ["APPS_SCRIPT_URL"] }, async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Must be signed in.");
  }
  if (!(await callerIsAdmin(request.auth.uid))) {
    throw new HttpsError("permission-denied", "Admin only.");
  }

  const { uid, mimeType, data } = request.data || {};
  if (typeof uid !== "string" || !uid || typeof data !== "string" || !data) {
    throw new HttpsError("invalid-argument", "uid and data are required.");
  }
  if (!COACH_PHOTO_TYPES.has(mimeType)) {
    throw new HttpsError("invalid-argument", "Please choose a JPG, PNG or WebP image.");
  }
  if (Buffer.byteLength(data, "base64") > COACH_PHOTO_MAX_BYTES) {
    throw new HttpsError("invalid-argument", "Photo is too large (max 5 MB).");
  }

  const coach = await admin.firestore().collection("users").doc(uid).get();
  const role = coach.data()?.role;
  if (role !== "trainer" && role !== "admin") {
    throw new HttpsError("failed-precondition", "That user isn't a trainer or admin.");
  }
  const safeName = (coach.data()?.name || uid).replace(/[^\w .-]/g, "").trim() || uid;
  const ext = mimeType.split("/")[1].replace("jpeg", "jpg");

  // Apps Script answers a POST with a redirect to the result; fetch follows
  // it as a GET, which is what Apps Script expects.
  const res = await fetch(process.env.APPS_SCRIPT_URL, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      action: "upload_coach_photo",
      fileName: `${IS_EMULATOR ? "TEST - " : ""}${safeName} (${uid}).${ext}`,
      mimeType,
      data,
    }),
    signal: AbortSignal.timeout(30000),
  });
  if (!res.ok) {
    throw new HttpsError("unavailable", `Apps Script returned ${res.status}`);
  }
  const text = await res.text();
  let result;
  try {
    result = JSON.parse(text);
  } catch {
    throw new HttpsError("internal",
      "Drive upload isn't set up in the Apps Script yet (got a non-JSON reply).");
  }
  if (!result.fileId) {
    throw new HttpsError("internal", `Drive upload failed: ${result.error || text.slice(0, 200)}`);
  }
  return { fileId: result.fileId, url: `https://lh3.googleusercontent.com/d/${result.fileId}` };
});

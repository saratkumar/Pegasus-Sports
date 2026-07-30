const { onSchedule } = require("firebase-functions/v2/scheduler");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const admin = require("firebase-admin");
const { buildRenewalReminderEmail } = require("./emailTemplates");

const REMINDER_WINDOW_DAYS = 14;
const BATCH_LIMIT = 400; // Firestore batch cap is 500 writes; leave headroom.

function dayDiff(from, to) {
  const msPerDay = 24 * 60 * 60 * 1000;
  return Math.floor((to.getTime() - from.getTime()) / msPerDay);
}

// ── dailyMembershipRollover ─────────────────────────────────────────────────
// Expires any membership entry whose date window has passed and promotes
// the earliest queued entry (if any) to active. This is what makes `status`
// track reality day-to-day for users who never book anything — a booking's
// own deductCredit also does an on-the-fly defensive re-check, but that only
// fires when someone actually tries to book; this keeps the field itself
// honest for display purposes (memberships_screen.dart, admin plan editor)
// even with zero app activity.
exports.dailyMembershipRollover = onSchedule(
  { schedule: "every day 03:00", timeZone: "Asia/Singapore" },
  async () => {
    const db = admin.firestore();
    const now = Date.now();
    const usersSnap = await db.collection("users").get();

    let batch = db.batch();
    let opsInBatch = 0;
    const commits = [];

    for (const doc of usersSnap.docs) {
      const memberships = doc.data().memberships;
      if (!Array.isArray(memberships) || memberships.length === 0) continue;

      let changed = false;
      const updated = memberships.map((m) => ({ ...m }));

      for (let i = 0; i < updated.length; i++) {
        const m = updated[i];
        if (m.status === "active" && m.endDate && m.endDate.toMillis() <= now) {
          updated[i] = { ...m, status: "expired" };
          changed = true;

          // Promote the earliest-starting queued entry, if any — mirrors
          // UserService._resolveQueueTail's ordering.
          const queued = updated
            .map((mm, idx) => ({ mm, idx }))
            .filter(({ mm }) => mm.status === "queued");
          if (queued.length > 0) {
            queued.sort((a, b) => a.mm.startDate.toMillis() - b.mm.startDate.toMillis());
            const nextIdx = queued[0].idx;
            updated[nextIdx] = { ...updated[nextIdx], status: "active" };
          }
        }
      }

      if (changed) {
        batch.update(doc.ref, { memberships: updated });
        opsInBatch++;
        if (opsInBatch >= BATCH_LIMIT) {
          commits.push(batch.commit());
          batch = db.batch();
          opsInBatch = 0;
        }
      }
    }
    if (opsInBatch > 0) commits.push(batch.commit());
    await Promise.all(commits);
  }
);

// ── shared reminder-sending logic ───────────────────────────────────────────
// Used by both the nightly sweep (dailyRenewalReminders, requireWindow: true
// — only within 14 days of expiry, only once) and the admin's on-demand
// "Send Renewal Reminder" button (sendRenewalReminderNow, requireWindow:
// false — admin explicitly asked for it right now, so the day-window and
// already-sent guards don't apply). Both still skip a user who's already
// queued a renewal — nudging someone who's already renewed isn't useful
// regardless of who triggered the check.
//
// Returns { sent: boolean, reason: string|null } — reason explains a no-op
// (used by the admin callable to report back why nothing was sent).
async function sendRenewalReminderForUser(db, userRef, userData, { requireWindow }) {
  const memberships = userData.memberships;
  if (!Array.isArray(memberships)) return { sent: false, reason: "no-memberships" };

  const active = memberships.find((m) => m.status === "active");
  if (!active || !active.endDate) return { sent: false, reason: "no-active-plan" };

  if (memberships.some((m) => m.status === "queued")) {
    return { sent: false, reason: "already-queued" };
  }

  const now = new Date();
  const daysLeft = dayDiff(now, active.endDate.toDate());

  if (requireWindow) {
    if (active.reminderSentAt) return { sent: false, reason: "already-sent" };
    if (daysLeft < 0 || daysLeft > REMINDER_WINDOW_DAYS) return { sent: false, reason: "outside-window" };
  }

  const email = userData.email;
  if (!email) return { sent: false, reason: "no-email" };

  let sent = false;
  await db.runTransaction(async (tx) => {
    const freshSnap = await tx.get(userRef);
    const freshMemberships = freshSnap.data()?.memberships || [];
    const idx = freshMemberships.findIndex((m) => m.id === active.id);
    if (idx === -1) return;
    if (requireWindow && freshMemberships[idx].reminderSentAt) return;

    const updated = [...freshMemberships];
    updated[idx] = { ...updated[idx], reminderSentAt: admin.firestore.Timestamp.now() };
    tx.update(userRef, { memberships: updated });

    tx.set(
      db.collection("mail").doc(),
      buildRenewalReminderEmail({
        to: email,
        name: userData.name || "there",
        planName: active.planName,
        endDate: active.endDate.toDate(),
        creditsRemaining: active.creditsRemaining || 0,
        daysLeft: Math.max(daysLeft, 0),
      })
    );
    sent = true;
  });

  return { sent, reason: sent ? null : "already-sent" };
}

// ── dailyRenewalReminders ───────────────────────────────────────────────────
// Runs after the rollover (15 min later) so it always reads post-rollover
// state — a plan that just expired and promoted its successor shouldn't
// also fire a reminder for the now-expired one. Sends once per membership
// entry and uses a "<= 14 days left" window rather than "exactly 14" so a
// delayed/missed run doesn't permanently skip a user.
exports.dailyRenewalReminders = onSchedule(
  { schedule: "every day 03:15", timeZone: "Asia/Singapore" },
  async () => {
    const db = admin.firestore();
    const usersSnap = await db.collection("users").get();

    for (const doc of usersSnap.docs) {
      await sendRenewalReminderForUser(db, doc.ref, doc.data(), { requireWindow: true });
    }
  }
);

// ── sendRenewalReminderNow ──────────────────────────────────────────────────
// Admin-only: the "Send Renewal Reminder" button in the user management
// screen. Sends immediately for the target user's active plan, bypassing
// the 14-day window and the once-only guard (an explicit manual trigger is
// its own confirmation) — but still skips if they've already queued a
// renewal, same reasoning as the automatic sweep.
exports.sendRenewalReminderNow = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Must be signed in.");
  }
  const db = admin.firestore();
  const callerDoc = await db.collection("users").doc(request.auth.uid).get();
  if (callerDoc.data()?.role !== "admin") {
    throw new HttpsError("permission-denied", "Admin only.");
  }

  const { uid } = request.data;
  if (!uid) throw new HttpsError("invalid-argument", "uid is required.");

  const userRef = db.collection("users").doc(uid);
  const userSnap = await userRef.get();
  if (!userSnap.exists) throw new HttpsError("not-found", "User not found.");

  return sendRenewalReminderForUser(db, userRef, userSnap.data(), { requireWindow: false });
});

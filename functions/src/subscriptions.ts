import { onCall, HttpsError } from "firebase-functions/v2/https";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { z } from "zod";
import { db, FieldValue, requireAuth, audit, notify, alreadyProcessed } from "./shared.js";

const PLANS: Record<string, { name:string; visits:number; validityDays:number; billingMode:string }> = {
  "shine-8": { name:"Shine 8", visits:8, validityDays:30, billingMode:"prepaid" },
  "shine-12": { name:"Shine 12", visits:12, validityDays:30, billingMode:"prepaid" },
  "shine-daily": { name:"Daily Shine", visits:26, validityDays:30, billingMode:"recurring" },
};

/** PRD §12.3/12.4 — prepaid activates after verified payment; recurring needs provider mandate (see docs). */
export const createSubscription = onCall(async (req) => {
  const uid = requireAuth(req);
  const d = z.object({ planId:z.string(), vehicleId:z.string(), addressId:z.string(), timeWindow:z.string(), frequency:z.string().default("alternate_days"), idempotencyKey:z.string().min(8) }).parse(req.data);
  const plan = PLANS[d.planId]; if (!plan) throw new HttpsError("not-found", "Plan not found");
  if (await alreadyProcessed(d.idempotencyKey, "createSubscription")) throw new HttpsError("already-exists", "Duplicate subscription request");
  const ref = db.collection("subscriptions").doc();
  const now = new Date(); const end = new Date(now.getTime() + plan.validityDays * 864e5);
  await ref.set({ id:ref.id, customerUid:uid, vehicleId:d.vehicleId, addressId:d.addressId, planId:d.planId, billingMode:plan.billingMode, status: plan.billingMode==="prepaid" ? "pending_payment" : "pending_payment", schedule:{ frequency:d.frequency, timeWindow:d.timeWindow, timezone:"Asia/Kolkata" }, visitBalance: plan.visits, currentPeriodStart: now, currentPeriodEnd: end, nextRenewalAt: plan.billingMode==="recurring" ? end : null, billingProvider: plan.billingMode==="recurring" ? "razorpay" : null, providerSubscriptionId: null, createdAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp() });
  return { subscriptionId: ref.id, status: "pending_payment", note: plan.billingMode==="recurring" ? "Recurring activates after Razorpay mandate confirmation via webhook" : "Prepaid activates after payment verification" };
});

/** Unique occurrence key prevents duplicates on retry (PRD §8.2). */
export async function generateOccurrencesFor(subId: string) {
  const sSnap = await db.doc(`subscriptions/${subId}`).get(); if (!sSnap.exists) return 0;
  const s = sSnap.data()!; if (s.status !== "active") return 0;
  const dayKey = new Date().toISOString().slice(0,10);
  const occId = `${subId}_${dayKey}`;
  const occRef = db.doc(`subscriptionOccurrences/${occId}`);
  if ((await occRef.get()).exists) return 0;
  await occRef.set({ id: occId, subscriptionId: subId, customerUid: s.customerUid, vehicleId: s.vehicleId, addressId: s.addressId, scheduledAt: new Date(), status: "scheduled", bookingId: null, createdAt: FieldValue.serverTimestamp() });
  await notify(s.customerUid, "subscription_visit", "Wash scheduled today", "Your subscription visit is scheduled", occId);
  return 1;
}
export const generateOccurrences = onSchedule({ schedule: "every day 05:30", timeZone: "Asia/Kolkata" }, async () => {
  const active = await db.collection("subscriptions").where("status","==","active").get();
  for (const d of active.docs) await generateOccurrencesFor(d.id);
});
export const skipOccurrence = onCall(async (req) => {
  const uid = requireAuth(req);
  const { occurrenceId } = z.object({ occurrenceId: z.string() }).parse(req.data);
  const ref = db.doc(`subscriptionOccurrences/${occurrenceId}`); const snap = await ref.get();
  if (!snap.exists || snap.data()!.customerUid !== uid) throw new HttpsError("permission-denied", "Not your visit");
  await ref.update({ status: "skipped" }); // credit NOT consumed on skip (policy)
  return { ok:true };
});
const subAction = (status: string, action: string) => onCall(async (req) => {
  const uid = requireAuth(req);
  const { subscriptionId, reason } = z.object({ subscriptionId: z.string(), reason: z.string().optional() }).parse(req.data);
  const ref = db.doc(`subscriptions/${subscriptionId}`); const snap = await ref.get();
  if (!snap.exists || snap.data()!.customerUid !== uid) throw new HttpsError("permission-denied", "Not your subscription");
  await ref.update({ status, updatedAt: FieldValue.serverTimestamp() });
  await audit(uid, action, subscriptionId, reason);
  return { ok:true };
});
export const pauseSubscription = subAction("paused", "pauseSubscription");
export const resumeSubscription = subAction("active", "resumeSubscription");
export const cancelSubscription = subAction("cancelled", "cancelSubscription");

/** Daily renewal reconciliation — duplicate events never double-credit (idempotency + status check). */
export const processRenewals = onSchedule({ schedule: "every day 06:00", timeZone: "Asia/Kolkata" }, async () => {
  const due = await db.collection("subscriptions").where("billingMode","==","recurring").where("status","==","active").get();
  for (const d of due.docs) {
    const s = d.data();
    if (s.nextRenewalAt && s.nextRenewalAt.toDate() <= new Date()) {
      // Actual charge happens via Razorpay Subscription mandate; webhook confirms → only then extend period + reset credits.
      await notify(s.customerUid, "renewal_due", "Subscription renewal due", "Your Daily Shine plan renews today", d.id);
    }
  }
});
export const reconcileRenewals = processRenewals;

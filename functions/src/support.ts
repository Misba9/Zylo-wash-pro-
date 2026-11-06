import { onCall, HttpsError } from "firebase-functions/v2/https";
import { onDocumentCreated } from "firebase-functions/v2/firestore";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { z } from "zod";
import { db, FieldValue, requireAuth, requireRole, audit, notify } from "./shared.js";

/** Automatic account deletion (Play policy + GDPR-style erasure).
 *  Erases profile, vehicles, addresses, subscriptions, notifications and
 *  support tickets; anonymises bookings/payments (kept for tax law);
 *  finally deletes the Firebase Auth user. Callable only by the owner. */
export const deleteMyAccount = onCall(async (req) => {
  const uid = requireAuth(req);
  const { getAuth } = await import("firebase-admin/auth");
  const batchLimit = 400;
  const deleteQuery = async (coll: string, field: string) => {
    const snap = await db.collection(coll).where(field, "==", uid).get();
    for (let i = 0; i < snap.docs.length; i += batchLimit) {
      const batch = db.batch();
      snap.docs.slice(i, i + batchLimit).forEach((d) => batch.delete(d.ref));
      await batch.commit();
    }
  };
  const anonymiseQuery = async (coll: string) => {
    const snap = await db.collection(coll).where("customerUid", "==", uid).get();
    for (let i = 0; i < snap.docs.length; i += batchLimit) {
      const batch = db.batch();
      snap.docs.slice(i, i + batchLimit).forEach((d) =>
        batch.update(d.ref, { customerName: "Deleted user", customerPhone: "", customerEmail: "" }));
      await batch.commit();
    }
  };
  await deleteQuery("vehicles", "ownerUid");
  await deleteQuery("addresses", "ownerUid");
  await deleteQuery("subscriptions", "customerUid");
  await deleteQuery("notifications", "recipientUid");
  await deleteQuery("supportTickets", "customerUid");
  await anonymiseQuery("bookings");
  await anonymiseQuery("payments");
  await db.doc(`users/${uid}`).delete();
  await db.collection("auditLogs").add({ actor: uid, action: "deleteAccount", target: uid, reason: "self-service in-app deletion", createdAt: FieldValue.serverTimestamp() });
  await getAuth().deleteUser(uid);
  return { ok: true };
});

export const openSupportTicket = onCall(async (req) => {
  const uid = requireAuth(req);
  const d = z.object({ subject: z.string().min(3), bookingId: z.string().optional(), priority: z.enum(["low","medium","high"]).default("medium") }).parse(req.data);
  const ref = db.collection("supportTickets").doc();
  await ref.set({ id: ref.id, customerUid: uid, ...d, status: "open", createdAt: FieldValue.serverTimestamp() });
  return { ticketId: ref.id };
});
export const calculateWorkerEarnings = onCall(async (req) => {
  const { uid, role } = requireRole(req, ["worker","finance","admin","super_admin"]);
  const workerUid = role === "worker" ? uid : z.string().parse(req.data?.workerUid);
  const done = await db.collection("bookings").where("assignedWorkerUid","==",workerUid).where("status","==","completed").get();
  const grossPaise = done.docs.reduce((n,d)=> n + (d.data().priceSnapshot?.totalPaise||0), 0);
  return { workerUid, completedJobs: done.size, grossPaise, payoutPaise: Math.round(grossPaise*0.7), platformPaise: grossPaise - Math.round(grossPaise*0.7) }; // 70% worker share, configure in appConfig
});
export const processWorkerPayout = onCall(async (req) => {
  const { uid } = requireRole(req, ["finance","super_admin"]);
  const d = z.object({ workerUid: z.string(), amountPaise: z.number().int().positive(), period: z.string() }).parse(req.data);
  const ref = db.collection("payouts").doc();
  await ref.set({ id: ref.id, ...d, status: "pending", createdBy: uid, createdAt: FieldValue.serverTimestamp() });
  await audit(uid, "processWorkerPayout", `${d.workerUid} · ${d.amountPaise}`, d.period);
  await notify(d.workerUid, "payout", "Payout initiated", `₹${(d.amountPaise/100).toLocaleString("en-IN")} for ${d.period}`, ref.id);
  return { payoutId: ref.id };
});
export const writeAuditLog = onCall(async (req) => {
  const { uid } = requireRole(req, ["admin","finance","super_admin"]);
  const d = z.object({ action: z.string(), target: z.string(), reason: z.string().optional() }).parse(req.data);
  await audit(uid, d.action, d.target, d.reason);
  return { ok:true };
});
export const expirePendingBooking = onSchedule({ schedule: "every 15 minutes", timeZone: "Asia/Kolkata" }, async () => {
  const cutoff = new Date(Date.now() - 30*60*1000);
  const stale = await db.collection("bookings").where("status","==","awaiting_payment").where("createdAt","<",cutoff).get();
  const batch = db.batch();
  stale.forEach(d => batch.update(d.ref, { status:"cancelled", cancelReason:"Payment not completed in 30 min", updatedAt: FieldValue.serverTimestamp() }));
  if (!stale.empty) await batch.commit();
});
export const sendUpcomingWashReminder = onSchedule({ schedule: "every day 19:00", timeZone: "Asia/Kolkata" }, async () => {
  const upcoming = await db.collection("bookings").where("status","in",["confirmed","assigned"]).limit(200).get();
  for (const d of upcoming.docs) await notify(d.data().customerUid, "reminder", "Wash coming up", `${d.data().serviceId} scheduled`, d.id);
});
export const sendBookingNotification = onCall(async (req) => {
  requireRole(req, ["admin","super_admin"]);
  const d = z.object({ recipientUid: z.string(), title: z.string(), body: z.string(), bookingId: z.string().optional() }).parse(req.data);
  await notify(d.recipientUid, "admin_message", d.title, d.body, d.bookingId ?? null);
  return { ok:true };
});

/** Push delivery for EVERY notifications/{id} doc — including ones written
 *  directly by the Admin dashboard (worker assigned, ticket resolved, …).
 *  The in-app inbox stays the source of truth; FCM is best-effort. */
export const onNotificationCreated = onDocumentCreated("notifications/{id}", async (event) => {
  const d = event.data?.data() as any;
  if (!d?.recipientUid || !d?.title) return;
  try {
    const { getMessaging } = await import("firebase-admin/messaging");
    const user = await db.doc(`users/${d.recipientUid}`).get().catch(() => null);
    const token = (user?.data() as any)?.fcmToken;
    if (!token) return;
    await getMessaging().send({
      token,
      notification: { title: String(d.title), body: String(d.body ?? "") },
      data: { type: String(d.type ?? "update"), bookingId: String(d.bookingId ?? d.refId ?? ""), refId: String(d.refId ?? d.bookingId ?? "") },
      android: { priority: "high" },
    });
  } catch { /* non-fatal: inbox record remains */ }
});

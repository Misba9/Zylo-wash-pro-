import { onCall, onRequest, HttpsError } from "firebase-functions/v2/https";
import { z } from "zod";
import * as crypto from "crypto";
import { db, FieldValue, requireAuth, requireRole, audit, alreadyProcessed, hmacValid } from "./shared.js";

function requireRazorpayKeys() {
  if (!process.env.RAZORPAY_KEY_ID || !process.env.RAZORPAY_KEY_SECRET) {
    throw new HttpsError("failed-precondition", "Razorpay keys are not configured yet. Set RAZORPAY_KEY_ID and RAZORPAY_KEY_SECRET, then redeploy functions.");
  }
}

async function razorpay(path: string, method: string, body?: unknown) {
  requireRazorpayKeys();
  const auth = Buffer.from(`${process.env.RAZORPAY_KEY_ID}:${process.env.RAZORPAY_KEY_SECRET}`).toString("base64");
  const res = await fetch(`https://api.razorpay.com/v1${path}`, { method, headers: { Authorization: `Basic ${auth}`, "Content-Type": "application/json" }, body: body ? JSON.stringify(body) : undefined });
  if (!res.ok) throw new HttpsError("internal", `Razorpay ${res.status}: ${await res.text()}`);
  return res.json() as Promise<any>;
}

/** PRD §12.1 — server creates order; client callback alone never marks paid. */
export const createPaymentOrder = onCall(async (req) => {
  const uid = requireAuth(req);
  const { bookingId } = z.object({ bookingId: z.string() }).parse(req.data);
  const bSnap = await db.doc(`bookings/${bookingId}`).get();
  if (!bSnap.exists || bSnap.data()!.customerUid !== uid) throw new HttpsError("permission-denied", "Not your booking");
  const b = bSnap.data()!;
  if (b.paymentMethod !== "online") throw new HttpsError("failed-precondition", "Not an online booking");
  const order = await razorpay("/orders", "POST", { amount: b.priceSnapshot.totalPaise, currency: "INR", receipt: bookingId, notes: { bookingId } });
  const pRef = db.collection("payments").doc();
  await pRef.set({ id: pRef.id, bookingId, customerUid: uid, amountPaise: b.priceSnapshot.totalPaise, method: "online", status: "pending", providerOrderId: order.id, providerRef: null, createdAt: FieldValue.serverTimestamp() });
  return { orderId: order.id, amountPaise: b.priceSnapshot.totalPaise, currency: "INR", keyId: process.env.RAZORPAY_KEY_ID, paymentId: pRef.id };
});

export const verifyPayment = onCall(async (req) => {
  requireRazorpayKeys();
  const uid = requireAuth(req);
  const d = z.object({ bookingId: z.string(), razorpayOrderId: z.string(), razorpayPaymentId: z.string(), razorpaySignature: z.string() }).parse(req.data);
  const expected = crypto.createHmac("sha256", process.env.RAZORPAY_KEY_SECRET!).update(`${d.razorpayOrderId}|${d.razorpayPaymentId}`).digest("hex");
  if (!crypto.timingSafeEqual(Buffer.from(expected), Buffer.from(d.razorpaySignature))) throw new HttpsError("permission-denied", "Signature mismatch");
  await markPaid(d.bookingId, d.razorpayPaymentId, uid);
  return { ok: true };
});

async function markPaid(bookingId: string, providerRef: string, actor: string) {
  if (await alreadyProcessed(providerRef, "payment")) return;
  await db.runTransaction(async (tx) => {
    const bRef = db.doc(`bookings/${bookingId}`); const b = await tx.get(bRef);
    if (!b.exists) return;
    const payQ = await db.collection("payments").where("bookingId", "==", bookingId).where("status", "==", "pending").limit(1).get();
    payQ.forEach(p => tx.update(p.ref, { status: "paid", providerRef }));
    tx.update(bRef, { paymentStatus: "paid", status: b.data()!.status === "awaiting_payment" ? "confirmed" : b.data()!.status, updatedAt: FieldValue.serverTimestamp() });
  });
  await audit(actor, "paymentPaid", bookingId, providerRef);
}

/** PRD §10.3 — signed webhook, idempotent via webhookEvents. */
export const handlePaymentWebhook = onRequest(async (req, res) => {
  if (!process.env.RAZORPAY_WEBHOOK_SECRET) { res.status(503).send("webhook secret not configured"); return; }
  const signature = req.header("x-razorpay-signature") || "";
  const raw = JSON.stringify(req.body);
  try { if (!hmacValid(raw, signature, process.env.RAZORPAY_WEBHOOK_SECRET!)) { res.status(400).send("bad signature"); return; } } catch { res.status(400).send("bad signature"); return; }
  const event = req.body;
  const eventId = req.header("x-razorpay-event-id") || event?.payload?.payment?.entity?.id || crypto.randomUUID();
  const ref = db.doc(`webhookEvents/${eventId}`);
  if ((await ref.get()).exists) { res.status(200).send("duplicate"); return; }
  await ref.set({ type: event.event, receivedAt: FieldValue.serverTimestamp() });
  if (event.event === "payment.captured") {
    const entity = event.payload.payment.entity;
    const bookingId = entity.notes?.bookingId || entity.description;
    if (bookingId) await markPaid(bookingId, entity.id, "webhook");
  }
  if (event.event === "refund.processed") {
    const refund = event.payload.refund.entity;
    await db.collection("refunds").add({ providerRefundId: refund.id, amountPaise: refund.amount, status: "processed", createdAt: FieldValue.serverTimestamp() });
  }
  res.status(200).send("ok");
});

/** PRD §12.2 — cash, finance-reconcilable, never marked online-paid. */
export const recordCashCollection = onCall(async (req) => {
  const { uid, role } = requireRole(req, ["worker", "admin", "finance", "super_admin"]);
  const d = z.object({ bookingId: z.string(), amountPaise: z.number().int().positive(), reason: z.string().optional() }).parse(req.data);
  const bSnap = await db.doc(`bookings/${d.bookingId}`).get();
  if (!bSnap.exists) throw new HttpsError("not-found", "Booking not found");
  const b = bSnap.data()!;
  if (role === "worker" && b.assignedWorkerUid !== uid) throw new HttpsError("permission-denied", "Not your job");
  if (b.paymentMethod !== "cash") throw new HttpsError("failed-precondition", "Not a cash booking");
  if (d.amountPaise !== b.priceSnapshot.totalPaise && !d.reason) throw new HttpsError("invalid-argument", "Mismatch amount requires a reason");
  await db.collection("payments").add({ bookingId: d.bookingId, customerUid: b.customerUid, amountPaise: d.amountPaise, method: "cash", status: "collected", collectedBy: uid, discrepancyReason: d.reason ?? null, createdAt: FieldValue.serverTimestamp() });
  await bSnap.ref.update({ paymentStatus: "paid", updatedAt: FieldValue.serverTimestamp() });
  await audit(uid, "recordCashCollection", d.bookingId, d.reason);
  return { ok: true };
});

export const requestRefund = onCall(async (req) => {
  const { uid } = requireRole(req, ["finance", "admin", "super_admin"]);
  const d = z.object({ paymentId: z.string(), amountPaise: z.number().int().positive().optional(), reason: z.string().min(3) }).parse(req.data);
  const pSnap = await db.doc(`payments/${d.paymentId}`).get();
  if (!pSnap.exists) throw new HttpsError("not-found", "Payment not found");
  const p = pSnap.data()!;
  const refund = p.providerRef ? await razorpay(`/payments/${p.providerRef}/refund`, "POST", { amount: d.amountPaise ?? p.amountPaise }) : { id: `rfnd_cash_${Date.now()}` };
  const rRef = db.collection("refunds").doc();
  await rRef.set({ id: rRef.id, paymentId: d.paymentId, bookingId: p.bookingId ?? null, amountPaise: d.amountPaise ?? p.amountPaise, providerRefundId: refund.id, status: "pending", reason: d.reason, requestedBy: uid, createdAt: FieldValue.serverTimestamp() });
  await pSnap.ref.update({ status: "refund_pending" });
  await audit(uid, "requestRefund", d.paymentId, d.reason);
  return { refundId: rRef.id };
});

export const reconcilePayments = onCall(async (req) => {
  requireRole(req, ["finance", "super_admin"]);
  const pending = await db.collection("payments").where("status", "in", ["pending", "refund_pending"]).get();
  return { unresolved: pending.docs.map(d => ({ id: d.id, ...d.data(), createdAt: undefined })) };
});

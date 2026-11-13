import { onCall, onRequest, HttpsError } from "firebase-functions/v2/https";
import { defineSecret } from "firebase-functions/params";
import { z } from "zod";
import * as crypto from "crypto";
import type { QueryDocumentSnapshot } from "firebase-admin/firestore";
import { db, FieldValue, requireAuth, requireRole, audit, alreadyProcessed, notify } from "./shared.js";
import { hmacHexEqual, verifyRazorpayCheckoutSignature } from "./payments_crypto.js";
import { resolveTrustedBookingAmount } from "./trusted_amount.js";

const RZP_KEY = defineSecret("RAZORPAY_KEY_ID");
const RZP_SECRET = defineSecret("RAZORPAY_KEY_SECRET");
const RZP_WEBHOOK = defineSecret("RAZORPAY_WEBHOOK_SECRET");

function requireRazorpayKeys() {
  if (!process.env.RAZORPAY_KEY_ID || !process.env.RAZORPAY_KEY_SECRET) {
    throw new HttpsError(
      "failed-precondition",
      "Razorpay keys are not configured yet. Set RAZORPAY_KEY_ID and RAZORPAY_KEY_SECRET, then redeploy functions.",
    );
  }
}

async function razorpay(path: string, method: string, body?: unknown) {
  requireRazorpayKeys();
  const auth = Buffer.from(`${process.env.RAZORPAY_KEY_ID}:${process.env.RAZORPAY_KEY_SECRET}`).toString("base64");
  const res = await fetch(`https://api.razorpay.com/v1${path}`, {
    method,
    headers: { Authorization: `Basic ${auth}`, "Content-Type": "application/json" },
    body: body ? JSON.stringify(body) : undefined,
  });
  if (!res.ok) throw new HttpsError("internal", `Razorpay ${res.status}: ${await res.text()}`);
  return res.json() as Promise<any>;
}

/**
 * Create / reuse a Razorpay order for an awaiting_payment online booking.
 * Amount is recomputed from Firestore catalog (trusted_amount) — never a
 * client-only priceSnapshot underpayment.
 */
export const createPaymentOrder = onCall({ secrets: [RZP_KEY, RZP_SECRET] }, async (req) => {
  const uid = requireAuth(req);
  const { bookingId } = z.object({ bookingId: z.string().min(1) }).parse(req.data);
  const bSnap = await db.doc(`bookings/${bookingId}`).get();
  if (!bSnap.exists || bSnap.data()!.customerUid !== uid) {
    throw new HttpsError("permission-denied", "Not your booking");
  }
  const b = bSnap.data()!;
  if (b.paymentMethod !== "online") {
    throw new HttpsError("failed-precondition", "Not an online booking");
  }
  if (["paid", "authorized", "refunded", "partially_refunded"].includes(b.paymentStatus)) {
    throw new HttpsError("failed-precondition", "Booking is already paid");
  }
  if (["cancelled", "completed"].includes(b.status)) {
    throw new HttpsError("failed-precondition", `Cannot pay booking in status ${b.status}`);
  }

  const trusted = await resolveTrustedBookingAmount(b as Record<string, unknown>);
  const amountPaise = trusted.amountPaise;
  if (!Number.isInteger(amountPaise) || amountPaise < 100) {
    throw new HttpsError("failed-precondition", "Invalid booking amount");
  }
  // Persist server snapshot so review/admin/reports match the Razorpay order.
  const clientTotal = Number(b.priceSnapshot?.totalPaise);
  if (clientTotal !== amountPaise || b.priceSnapshot?.pricingVersion !== trusted.priceSnapshot.pricingVersion) {
    await bSnap.ref.update({
      priceSnapshot: trusted.priceSnapshot,
      updatedAt: FieldValue.serverTimestamp(),
    });
  }

  // Reuse an existing unused pending Razorpay order for this booking when present.
  const existing = await db
    .collection("payments")
    .where("bookingId", "==", bookingId)
    .where("status", "==", "pending")
    .limit(5)
    .get();
  const reusable = existing.docs.find((d) => {
    const m = d.data();
    return (
      m.providerOrderId &&
      m.customerUid === uid &&
      m.amountPaise === amountPaise &&
      (m.paymentGateway === "razorpay" || m.method === "online")
    );
  });
  if (reusable) {
    return {
      orderId: reusable.data().providerOrderId,
      amountPaise,
      currency: "INR",
      keyId: process.env.RAZORPAY_KEY_ID,
      paymentId: reusable.id,
      reused: true,
    };
  }

  const order = await razorpay("/orders", "POST", {
    amount: amountPaise,
    currency: "INR",
    receipt: bookingId.slice(0, 40),
    notes: { bookingId, customerUid: uid },
  });

  const pRef = db.collection("payments").doc();
  await pRef.set({
    id: pRef.id,
    paymentId: pRef.id,
    orderId: order.id,
    bookingId,
    customerId: uid,
    customerUid: uid,
    amountPaise,
    currency: "INR",
    paymentGateway: "razorpay",
    method: "online",
    paymentStatus: "pending",
    status: "pending",
    providerOrderId: order.id,
    razorpayPaymentId: null,
    providerRef: null,
    razorpaySignatureVerified: false,
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
    verifiedAt: null,
  });

  // Keep booking in awaiting_payment for online checkout.
  if (b.status !== "awaiting_payment") {
    await bSnap.ref.update({
      status: "awaiting_payment",
      paymentStatus: "pending",
      updatedAt: FieldValue.serverTimestamp(),
    });
  }

  return {
    orderId: order.id,
    amountPaise,
    currency: "INR",
    keyId: process.env.RAZORPAY_KEY_ID,
    paymentId: pRef.id,
    reused: false,
  };
});

/** Client callback: verify HMAC, ownership, order linkage; never trust Flutter alone. */
export const verifyPayment = onCall({ secrets: [RZP_KEY, RZP_SECRET] }, async (req) => {
  requireRazorpayKeys();
  const uid = requireAuth(req);
  const d = z
    .object({
      bookingId: z.string().min(1),
      razorpayOrderId: z.string().min(1),
      razorpayPaymentId: z.string().min(1),
      razorpaySignature: z.string().min(1),
    })
    .parse(req.data);

  if (
    !verifyRazorpayCheckoutSignature({
      orderId: d.razorpayOrderId,
      paymentId: d.razorpayPaymentId,
      signature: d.razorpaySignature,
      keySecret: process.env.RAZORPAY_KEY_SECRET!,
    })
  ) {
    throw new HttpsError("permission-denied", "Signature mismatch");
  }

  const bSnap = await db.doc(`bookings/${d.bookingId}`).get();
  if (!bSnap.exists || bSnap.data()!.customerUid !== uid) {
    throw new HttpsError("permission-denied", "Not your booking");
  }

  const payQ = await db
    .collection("payments")
    .where("providerOrderId", "==", d.razorpayOrderId)
    .limit(1)
    .get();
  if (payQ.empty) throw new HttpsError("not-found", "Payment order not found");
  const payDoc = payQ.docs[0];
  const pay = payDoc.data();
  if (pay.customerUid !== uid) throw new HttpsError("permission-denied", "Not your payment");
  if (pay.bookingId !== d.bookingId) {
    throw new HttpsError("failed-precondition", "Order does not belong to this booking");
  }

  // Confirm capture status with Razorpay when possible.
  let rzpStatus = "captured";
  try {
    const entity = await razorpay(`/payments/${d.razorpayPaymentId}`, "GET");
    rzpStatus = entity.status;
    if (entity.order_id && entity.order_id !== d.razorpayOrderId) {
      throw new HttpsError("failed-precondition", "Payment/order mismatch");
    }
    if (!["captured", "authorized"].includes(entity.status)) {
      throw new HttpsError("failed-precondition", `Payment not successful (${entity.status})`);
    }
  } catch (e) {
    if (e instanceof HttpsError) throw e;
    // Network blip: signature already valid — still mark via markPaid; webhook will reconcile.
  }

  await markPaid({
    bookingId: d.bookingId,
    providerRef: d.razorpayPaymentId,
    providerOrderId: d.razorpayOrderId,
    actor: uid,
    status: rzpStatus === "authorized" ? "authorized" : "paid",
  });
  return { ok: true, status: rzpStatus === "authorized" ? "authorized" : "paid" };
});

async function markPaid(args: {
  bookingId: string;
  providerRef: string;
  providerOrderId?: string;
  actor: string;
  status?: "authorized" | "paid";
}) {
  const status = args.status ?? "paid";
  if (await alreadyProcessed(args.providerRef, "payment")) return;

  await db.runTransaction(async (tx) => {
    const bRef = db.doc(`bookings/${args.bookingId}`);
    const b = await tx.get(bRef);
    if (!b.exists) return;
    const booking = b.data()!;

    let paySnap;
    if (args.providerOrderId) {
      paySnap = await db
        .collection("payments")
        .where("providerOrderId", "==", args.providerOrderId)
        .limit(1)
        .get();
    } else {
      paySnap = await db
        .collection("payments")
        .where("bookingId", "==", args.bookingId)
        .where("status", "==", "pending")
        .limit(1)
        .get();
    }

    const now = FieldValue.serverTimestamp();
    paySnap.forEach((p) => {
      tx.update(p.ref, {
        status: status === "authorized" ? "authorized" : "paid",
        paymentStatus: status === "authorized" ? "authorized" : "paid",
        providerRef: args.providerRef,
        razorpayPaymentId: args.providerRef,
        razorpaySignatureVerified: true,
        verifiedAt: now,
        updatedAt: now,
      });
    });

    const nextBookingStatus =
      booking.status === "awaiting_payment" ? "confirmed" : booking.status;
    tx.update(bRef, {
      paymentStatus: status === "authorized" ? "authorized" : "paid",
      status: nextBookingStatus,
      updatedAt: now,
    });
  });

  await audit(args.actor, "paymentPaid", args.bookingId, args.providerRef);
  try {
    const b = (await db.doc(`bookings/${args.bookingId}`).get()).data();
    if (b?.customerUid) {
      await notify(
        b.customerUid,
        "payment_confirmed",
        "Payment confirmed",
        "Your booking is confirmed. We'll assign a WashPro expert shortly.",
        args.bookingId,
      );
    }
  } catch {
    /* non-fatal */
  }
}

/** Mark a checkout failure / cancellation without confirming the booking. */
export const handlePaymentFailure = onCall(async (req) => {
  const uid = requireAuth(req);
  const d = z
    .object({
      bookingId: z.string().min(1),
      razorpayOrderId: z.string().optional(),
      reason: z.string().optional(),
      code: z.string().optional(),
    })
    .parse(req.data);

  const bSnap = await db.doc(`bookings/${d.bookingId}`).get();
  if (!bSnap.exists || bSnap.data()!.customerUid !== uid) {
    throw new HttpsError("permission-denied", "Not your booking");
  }

  if (d.razorpayOrderId) {
    const payQ = await db
      .collection("payments")
      .where("providerOrderId", "==", d.razorpayOrderId)
      .where("customerUid", "==", uid)
      .limit(1)
      .get();
    if (!payQ.empty) {
      const p = payQ.docs[0];
      if (p.data().status === "pending") {
        await p.ref.update({
          status: "failed",
          paymentStatus: "failed",
          failureReason: d.reason ?? d.code ?? "checkout_failed",
          updatedAt: FieldValue.serverTimestamp(),
        });
      }
    }
  }

  // Booking stays awaiting_payment so the customer can retry.
  await bSnap.ref.update({
    paymentStatus: "failed",
    updatedAt: FieldValue.serverTimestamp(),
  });
  await audit(uid, "paymentFailed", d.bookingId, d.reason ?? d.code);
  return { ok: true };
});

/** Read payment status for a booking (customer-owned). */
export const getPaymentStatus = onCall(async (req) => {
  const uid = requireAuth(req);
  const { bookingId } = z.object({ bookingId: z.string().min(1) }).parse(req.data);
  const bSnap = await db.doc(`bookings/${bookingId}`).get();
  if (!bSnap.exists || bSnap.data()!.customerUid !== uid) {
    throw new HttpsError("permission-denied", "Not your booking");
  }
  const pays = await db
    .collection("payments")
    .where("bookingId", "==", bookingId)
    .where("customerUid", "==", uid)
    .get();
  const payments = pays.docs.map((d) => {
    const m = d.data();
    return {
      paymentId: d.id,
      orderId: m.providerOrderId ?? m.orderId ?? null,
      paymentStatus: m.paymentStatus ?? m.status,
      amountPaise: m.amountPaise,
      razorpayPaymentId: m.razorpayPaymentId ?? m.providerRef ?? null,
      razorpaySignatureVerified: !!m.razorpaySignatureVerified,
    };
  });
  return {
    bookingId,
    bookingStatus: bSnap.data()!.status,
    paymentStatus: bSnap.data()!.paymentStatus,
    payments,
  };
});

/**
 * Razorpay webhook — verifies signature over the raw body, idempotent via webhookEvents.
 * Supported: payment.authorized, payment.captured, payment.failed, refund.processed
 */
export const handlePaymentWebhook = onRequest(
  { secrets: [RZP_WEBHOOK, RZP_KEY, RZP_SECRET] },
  async (req, res) => {
    if (req.method !== "POST") {
      res.status(405).send("method not allowed");
      return;
    }
    if (!process.env.RAZORPAY_WEBHOOK_SECRET) {
      res.status(503).send("webhook secret not configured");
      return;
    }

    const signature = req.header("x-razorpay-signature") || "";
    const rawBuf = (req as any).rawBody as Buffer | undefined;
    const raw = rawBuf ? rawBuf.toString("utf8") : typeof req.body === "string" ? req.body : JSON.stringify(req.body);
    if (!hmacHexEqual(raw, signature, process.env.RAZORPAY_WEBHOOK_SECRET)) {
      res.status(400).send("bad signature");
      return;
    }

    const event = typeof req.body === "string" ? JSON.parse(req.body) : req.body;
    const eventId =
      req.header("x-razorpay-event-id") ||
      event?.payload?.payment?.entity?.id ||
      event?.payload?.refund?.entity?.id ||
      crypto.randomUUID();

    const ref = db.doc(`webhookEvents/${eventId}`);
    const existing = await ref.get();
    if (existing.exists && existing.data()?.processed === true) {
      res.status(200).send("duplicate");
      return;
    }

    // Record receipt first (not processed) so crashes can be retried.
    if (!existing.exists) {
      await ref.set({
        type: event.event,
        receivedAt: FieldValue.serverTimestamp(),
        processed: false,
      });
    }

    try {
      if (event.event === "payment.authorized" || event.event === "payment.captured") {
        const entity = event.payload?.payment?.entity;
        if (entity) {
          const bookingId =
            entity.notes?.bookingId ||
            (await lookupBookingByOrder(entity.order_id));
          if (bookingId) {
            await markPaid({
              bookingId,
              providerRef: entity.id,
              providerOrderId: entity.order_id,
              actor: "webhook",
              status: event.event === "payment.authorized" ? "authorized" : "paid",
            });
          }
        }
      } else if (event.event === "payment.failed") {
        const entity = event.payload?.payment?.entity;
        if (entity?.order_id) {
          const payQ = await db
            .collection("payments")
            .where("providerOrderId", "==", entity.order_id)
            .limit(1)
            .get();
          if (!payQ.empty && payQ.docs[0].data().status === "pending") {
            await payQ.docs[0].ref.update({
              status: "failed",
              paymentStatus: "failed",
              failureReason: entity.error_description || entity.error_code || "failed",
              updatedAt: FieldValue.serverTimestamp(),
            });
            const bookingId = payQ.docs[0].data().bookingId;
            if (bookingId) {
              await db.doc(`bookings/${bookingId}`).update({
                paymentStatus: "failed",
                updatedAt: FieldValue.serverTimestamp(),
              });
            }
          }
        }
      } else if (event.event === "refund.processed") {
        const refund = event.payload?.refund?.entity;
        if (refund) {
          const paymentId = refund.payment_id;
          let payDoc: QueryDocumentSnapshot | null = null;
          if (paymentId) {
            const byRef = await db.collection("payments").where("providerRef", "==", paymentId).limit(1).get();
            if (!byRef.empty) payDoc = byRef.docs[0];
            if (!payDoc) {
              const alt = await db
                .collection("payments")
                .where("razorpayPaymentId", "==", paymentId)
                .limit(1)
                .get();
              if (!alt.empty) payDoc = alt.docs[0];
            }
          }

          const refundRef = db.collection("refunds").doc();
          await refundRef.set({
            id: refundRef.id,
            paymentId: payDoc?.id ?? null,
            bookingId: payDoc?.data()?.bookingId ?? null,
            providerRefundId: refund.id,
            amountPaise: refund.amount,
            status: "processed",
            createdAt: FieldValue.serverTimestamp(),
          });
          if (payDoc) {
            await payDoc.ref.update({
              status: "refunded",
              paymentStatus: "refunded",
              updatedAt: FieldValue.serverTimestamp(),
            });
            const bookingId = payDoc.data().bookingId;
            if (bookingId) {
              await db.doc(`bookings/${bookingId}`).update({
                paymentStatus: "refunded",
                updatedAt: FieldValue.serverTimestamp(),
              });
            }
          }
        }
      }

      await ref.set(
        { processed: true, processedAt: FieldValue.serverTimestamp(), type: event.event },
        { merge: true },
      );
      res.status(200).send("ok");
    } catch (err) {
      await ref.set(
        {
          processed: false,
          lastError: err instanceof Error ? err.message : String(err),
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
      res.status(500).send("processing error");
    }
  },
);

async function lookupBookingByOrder(orderId: string | undefined): Promise<string | null> {
  if (!orderId) return null;
  const q = await db.collection("payments").where("providerOrderId", "==", orderId).limit(1).get();
  return q.empty ? null : (q.docs[0].data().bookingId as string);
}

/** PRD §12.2 — cash, finance-reconcilable, never marked online-paid. */
export const recordCashCollection = onCall(async (req) => {
  const { uid, role } = requireRole(req, ["worker", "admin", "finance", "super_admin"]);
  const d = z
    .object({ bookingId: z.string(), amountPaise: z.number().int().positive(), reason: z.string().optional() })
    .parse(req.data);
  const bSnap = await db.doc(`bookings/${d.bookingId}`).get();
  if (!bSnap.exists) throw new HttpsError("not-found", "Booking not found");
  const b = bSnap.data()!;
  if (role === "worker" && b.assignedWorkerUid !== uid) throw new HttpsError("permission-denied", "Not your job");
  if (b.paymentMethod !== "cash") throw new HttpsError("failed-precondition", "Not a cash booking");
  if (d.amountPaise !== b.priceSnapshot.totalPaise && !d.reason) {
    throw new HttpsError("invalid-argument", "Mismatch amount requires a reason");
  }
  await db.collection("payments").add({
    bookingId: d.bookingId,
    customerUid: b.customerUid,
    customerId: b.customerUid,
    amountPaise: d.amountPaise,
    currency: "INR",
    paymentGateway: "cash",
    method: "cash",
    status: "collected",
    paymentStatus: "paid",
    collectedBy: uid,
    discrepancyReason: d.reason ?? null,
    razorpaySignatureVerified: false,
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  });
  await bSnap.ref.update({ paymentStatus: "paid", updatedAt: FieldValue.serverTimestamp() });
  await audit(uid, "recordCashCollection", d.bookingId, d.reason);
  return { ok: true };
});

export const requestRefund = onCall({ secrets: [RZP_KEY, RZP_SECRET] }, async (req) => {
  const { uid } = requireRole(req, ["finance", "admin", "super_admin"]);
  const d = z
    .object({
      paymentId: z.string(),
      amountPaise: z.number().int().positive().optional(),
      reason: z.string().min(3),
    })
    .parse(req.data);
  const pSnap = await db.doc(`payments/${d.paymentId}`).get();
  if (!pSnap.exists) throw new HttpsError("not-found", "Payment not found");
  const p = pSnap.data()!;
  const providerPaymentId = p.providerRef || p.razorpayPaymentId;
  const refund = providerPaymentId
    ? await razorpay(`/payments/${providerPaymentId}/refund`, "POST", {
        amount: d.amountPaise ?? p.amountPaise,
      })
    : { id: `rfnd_cash_${Date.now()}` };
  const rRef = db.collection("refunds").doc();
  await rRef.set({
    id: rRef.id,
    paymentId: d.paymentId,
    bookingId: p.bookingId ?? null,
    amountPaise: d.amountPaise ?? p.amountPaise,
    providerRefundId: refund.id,
    status: "pending",
    reason: d.reason,
    requestedBy: uid,
    createdAt: FieldValue.serverTimestamp(),
  });
  await pSnap.ref.update({ status: "refund_pending", paymentStatus: "refund_pending", updatedAt: FieldValue.serverTimestamp() });
  await audit(uid, "requestRefund", d.paymentId, d.reason);
  return { refundId: rRef.id };
});

export const reconcilePayments = onCall(async (req) => {
  requireRole(req, ["finance", "super_admin"]);
  const pending = await db.collection("payments").where("status", "in", ["pending", "refund_pending", "failed"]).get();
  return {
    unresolved: pending.docs.map((d) => ({ id: d.id, ...d.data(), createdAt: undefined })),
  };
});

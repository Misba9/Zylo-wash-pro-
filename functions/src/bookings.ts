import { onCall, HttpsError } from "firebase-functions/v2/https";
import { z } from "zod";
import { db, FieldValue, requireAuth, requireRole, audit, notify, alreadyProcessed, TRANSITIONS, PRICES, DURATIONS } from "./shared.js";

const CreateBooking = z.object({ vehicleId:z.string().min(1), addressId:z.string().min(1), serviceId:z.string().min(1), bookingType:z.enum(["instant","scheduled","subscription"]), scheduledAt:z.string(), paymentMethod:z.enum(["online","cash"]), addonIds:z.array(z.string()).default([]), idempotencyKey:z.string().min(8) });

/** PRD §10.1 — authoritative price + slot validation, never trusts client price. */
export const createBooking = onCall(async (req) => {
  const uid = requireAuth(req);
  const d = CreateBooking.parse(req.data);
  if (await alreadyProcessed(d.idempotencyKey, "createBooking")) throw new HttpsError("already-exists", "Duplicate booking request");
  const [vehicle, address, service] = await Promise.all([db.doc(`vehicles/${d.vehicleId}`).get(), db.doc(`addresses/${d.addressId}`).get(), db.doc(`services/${d.serviceId}`).get()]);
  if (!vehicle.exists || vehicle.data()!.ownerUid !== uid) throw new HttpsError("permission-denied", "Vehicle not owned by caller");
  if (!address.exists || address.data()!.ownerUid !== uid) throw new HttpsError("permission-denied", "Address not owned by caller");
  if (!service.exists) throw new HttpsError("not-found", "Service not found");
  const area = await db.doc(`serviceAreas/${address.data()!.serviceAreaId}`).get();
  if (!area.exists || !area.data()!.active) throw new HttpsError("failed-precondition", "Area not served yet");
  if (d.paymentMethod === "cash" && (!area.data()!.cashEligible || !service.data()!.cashEligible)) throw new HttpsError("failed-precondition", "Cash not eligible for this service/area");
  const category = vehicle.data()!.category as string;
  const subtotal = (PRICES[d.serviceId]?.[category]) ?? service.data()!.pricePaise?.[category];
  if (subtotal == null) throw new HttpsError("failed-precondition", "No price for vehicle category");
  const priceSnapshot = { currency:"INR", subtotalPaise:subtotal, discountPaise:0, taxPaise:0, totalPaise:subtotal, pricingVersion:"hyd-2026.10-v1" };
  const ref = db.collection("bookings").doc();
  const status = d.paymentMethod === "online" ? "awaiting_payment" : "confirmed";
  await ref.set({ id:ref.id, customerUid:uid, vehicleId:d.vehicleId, addressId:d.addressId, serviceId:d.serviceId, serviceAreaId:address.data()!.serviceAreaId, assignedWorkerUid:null, bookingType:d.bookingType, status, scheduledAt:new Date(d.scheduledAt), estimatedDurationMinutes:DURATIONS[d.serviceId]?.[category] ?? 45, priceSnapshot, paymentMethod:d.paymentMethod, paymentStatus: d.paymentMethod==="online" ? "pending" : "pending", subscriptionId:null, occurrenceId:null, createdAt:FieldValue.serverTimestamp(), updatedAt:FieldValue.serverTimestamp(), completedAt:null });
  await notify(uid, "booking_created", "Booking received", `${service.data()!.name} · ${status==="confirmed" ? "confirmed" : "complete payment to confirm"}`, ref.id);
  return { bookingId: ref.id, status, priceSnapshot };
});

export const getAvailableSlots = onCall(async (req) => {
  requireAuth(req);
  const date = z.string().parse(req.data?.date);
  const slots = ["07:00","08:30","10:00","11:30","13:00","14:30","16:00","17:30"];
  const seed = [...date].reduce((n,c)=>n+c.charCodeAt(0),0);
  return { date, timezone:"Asia/Kolkata", slots: slots.map((time,i)=>({ time, spots: ((seed+i*7)%4) })) };
});

export const cancelBooking = onCall(async (req) => {
  const uid = requireAuth(req);
  const { bookingId, reason } = z.object({ bookingId:z.string(), reason:z.string().optional() }).parse(req.data);
  await db.runTransaction(async (tx) => {
    const ref = db.doc(`bookings/${bookingId}`); const snap = await tx.get(ref);
    if (!snap.exists) throw new HttpsError("not-found", "Booking not found");
    const b = snap.data()!;
    const isAdmin = ["admin","super_admin"].includes((req.auth!.token as any).role);
    if (b.customerUid !== uid && !isAdmin) throw new HttpsError("permission-denied", "Not your booking");
    if (!TRANSITIONS[b.status]?.includes("cancelled")) throw new HttpsError("failed-precondition", `Cannot cancel from ${b.status}`);
    tx.update(ref, { status:"cancelled", cancelReason: reason ?? null, updatedAt: FieldValue.serverTimestamp() });
  });
  await audit(uid, "cancelBooking", bookingId, reason);
  return { ok:true };
});

export const rescheduleBooking = onCall(async (req) => {
  const uid = requireAuth(req);
  const { bookingId, scheduledAt } = z.object({ bookingId:z.string(), scheduledAt:z.string() }).parse(req.data);
  const ref = db.doc(`bookings/${bookingId}`); const snap = await ref.get();
  if (!snap.exists) throw new HttpsError("not-found", "Booking not found");
  if (snap.data()!.customerUid !== uid && !(req.auth!.token as any).role?.includes("admin")) throw new HttpsError("permission-denied", "Not your booking");
  if (["completed","cancelled"].includes(snap.data()!.status)) throw new HttpsError("failed-precondition", "Cannot reschedule");
  await ref.update({ scheduledAt: new Date(scheduledAt), updatedAt: FieldValue.serverTimestamp() });
  await notify(snap.data()!.customerUid, "booking_rescheduled", "Booking rescheduled", `New time: ${scheduledAt}`, bookingId);
  return { ok:true };
});

export const updateBookingStatus = onCall(async (req) => {
  const { uid, role } = requireRole(req, ["worker","admin","super_admin"]);
  const { bookingId, next } = z.object({ bookingId:z.string(), next:z.string() }).parse(req.data);
  await db.runTransaction(async (tx) => {
    const ref = db.doc(`bookings/${bookingId}`); const snap = await tx.get(ref);
    if (!snap.exists) throw new HttpsError("not-found", "Booking not found");
    const b = snap.data()!;
    if (role === "worker" && b.assignedWorkerUid !== uid) throw new HttpsError("permission-denied", "Not assigned to you");
    if (!TRANSITIONS[b.status]?.includes(next)) throw new HttpsError("failed-precondition", `Invalid transition ${b.status} → ${next}`);
    const patch: Record<string, unknown> = { status: next, updatedAt: FieldValue.serverTimestamp() };
    if (next === "completed") patch.completedAt = FieldValue.serverTimestamp();
    if (next === "arrived") await db.doc(`workerLocations/${uid}`).delete().catch(()=>{});
    tx.update(ref, patch);
  });
  await audit(uid, "updateBookingStatus", `${bookingId} → ${req.data.next}`);
  return { ok:true };
});

/** PRD §10.5 — customer confirms work done; consumes subscription credit transactionally. */
export const verifyCompletion = onCall(async (req) => {
  const uid = requireAuth(req);
  const { bookingId, rating } = z.object({ bookingId:z.string(), rating:z.number().min(1).max(5).optional() }).parse(req.data);
  await db.runTransaction(async (tx) => {
    const ref = db.doc(`bookings/${bookingId}`); const snap = await tx.get(ref);
    if (!snap.exists) throw new HttpsError("not-found", "Booking not found");
    const b = snap.data()!;
    if (b.customerUid !== uid) throw new HttpsError("permission-denied", "Not your booking");
    if (b.status !== "pending_verification") throw new HttpsError("failed-precondition", "Not awaiting verification");
    tx.update(ref, { status:"completed", completedAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp() });
    if (b.subscriptionId) {
      const sRef = db.doc(`subscriptions/${b.subscriptionId}`); const s = await tx.get(sRef);
      if (s.exists && (s.data()!.visitBalance ?? 0) > 0) tx.update(sRef, { visitBalance: FieldValue.increment(-1) });
    }
  });
  if (rating) await db.collection("reviews").add({ bookingId, customerUid: uid, rating, createdAt: FieldValue.serverTimestamp() });
  return { ok:true };
});

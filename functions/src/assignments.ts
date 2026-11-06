import { onCall, HttpsError } from "firebase-functions/v2/https";
import { z } from "zod";
import { db, FieldValue, requireRole, requireAuth, audit, notify } from "./shared.js";

/** PRD §7.3 / §10.2 — ranked recommendations; admin confirms. */
export const recommendWorkers = onCall(async (req) => {
  requireRole(req, ["admin","super_admin"]);
  const { bookingId } = z.object({ bookingId:z.string() }).parse(req.data);
  const bSnap = await db.doc(`bookings/${bookingId}`).get();
  if (!bSnap.exists) throw new HttpsError("not-found", "Booking not found");
  const b = bSnap.data()!;
  const workers = await db.collection("workers").where("status","==","approved").get();
  const recs = workers.docs.map((d) => {
    const w: any = { uid:d.id, ...d.data() }; let score = 0; const reasons: string[] = [];
    if (!w.isAvailable) return { workerUid:d.id, name:w.name, score:-1, reasons:["Unavailable"] };
    if ((w.serviceAreaIds||[]).includes(b.serviceAreaId)) { score+=30; reasons.push("Serves this area"); }
    if ((w.serviceIds||[]).includes(b.serviceId)) { score+=25; reasons.push("Trained for this service"); }
    score += Math.round((w.rating||4.5)*6); score -= (w.activeJobs||0)*12;
    reasons.push(`★ ${w.rating} · ${w.completedJobs} jobs`);
    return { workerUid:d.id, name:w.name, score, reasons };
  }).sort((a,b)=>b.score-a.score);
  return { recommendations: recs };
});

export const assignWorker = onCall(async (req) => {
  const { uid } = requireRole(req, ["admin","super_admin"]);
  const { bookingId, workerUid, reason } = z.object({ bookingId:z.string(), workerUid:z.string(), reason:z.string().optional() }).parse(req.data);
  await db.runTransaction(async (tx) => {
    const bRef = db.doc(`bookings/${bookingId}`); const wRef = db.doc(`workers/${workerUid}`);
    const [b, w] = await Promise.all([tx.get(bRef), tx.get(wRef)]);
    if (!b.exists || !w.exists) throw new HttpsError("not-found", "Booking/worker not found");
    if (w.data()!.status !== "approved" || !w.data()!.isAvailable) throw new HttpsError("failed-precondition", "Worker not assignable");
    if (!["confirmed","assigned"].includes(b.data()!.status)) throw new HttpsError("failed-precondition", `Cannot assign from ${b.data()!.status}`);
    // conflict check: overlapping active jobs
    const clash = await db.collection("bookings").where("assignedWorkerUid","==",workerUid).where("status","in",["assigned","en_route","arrived","in_progress"]).get();
    if (clash.docs.some(d => d.id !== bookingId && Math.abs(d.data().scheduledAt.toMillis() - b.data()!.scheduledAt.toMillis()) < 60*60*1000)) throw new HttpsError("failed-precondition", "Worker has a conflicting job");
    tx.update(bRef, { assignedWorkerUid: workerUid, status:"assigned", updatedAt: FieldValue.serverTimestamp() });
    const aRef = db.collection("workerAssignments").doc();
    tx.set(aRef, { bookingId, workerUid, assignedBy: uid, reason: reason ?? null, createdAt: FieldValue.serverTimestamp() });
  });
  await audit(uid, "assignWorker", `${bookingId} → ${workerUid}`, reason);
  await notify(workerUid, "worker_assigned", "New job assigned", `Booking ${bookingId}`, bookingId);
  const b = (await db.doc(`bookings/${bookingId}`).get()).data()!;
  await notify(b.customerUid, "worker_assigned", "Worker assigned", "Your wash professional has been assigned", bookingId);
  return { ok:true };
});
export const reassignWorker = assignWorker;

export const acceptAssignment = onCall(async (req) => {
  const uid = requireAuth(req);
  const { bookingId } = z.object({ bookingId:z.string() }).parse(req.data);
  const snap = await db.doc(`bookings/${bookingId}`).get();
  if (!snap.exists || snap.data()!.assignedWorkerUid !== uid) throw new HttpsError("permission-denied", "Not assigned to you");
  await db.collection("workerAssignments").add({ bookingId, workerUid: uid, event:"accepted", createdAt: FieldValue.serverTimestamp() });
  return { ok:true };
});

/** PRD §6.3 / §10.2 — trip + location, active-trip only. */
export const startWorkerTrip = onCall(async (req) => {
  const uid = requireAuth(req);
  const { bookingId } = z.object({ bookingId:z.string() }).parse(req.data);
  const ref = db.doc(`bookings/${bookingId}`); const snap = await ref.get();
  if (!snap.exists || snap.data()!.assignedWorkerUid !== uid) throw new HttpsError("permission-denied", "Not assigned to you");
  if (snap.data()!.status !== "assigned") throw new HttpsError("failed-precondition", "Trip can start only from assigned");
  await ref.update({ status:"en_route", updatedAt: FieldValue.serverTimestamp() });
  await db.doc(`workerLocations/${uid}`).set({ workerUid:uid, bookingId, latitude:null, longitude:null, updatedAt: FieldValue.serverTimestamp() });
  await notify(snap.data()!.customerUid, "worker_en_route", "Worker on the way", "Your wash professional has started the trip", bookingId);
  return { ok:true };
});
export const stopWorkerTrip = onCall(async (req) => {
  const uid = requireAuth(req);
  await db.doc(`workerLocations/${uid}`).delete();
  return { ok:true };
});
export const recordWorkerLocation = onCall(async (req) => {
  const uid = requireAuth(req);
  const d = z.object({ bookingId:z.string(), latitude:z.number().min(-90).max(90), longitude:z.number().min(-180).max(180) }).parse(req.data);
  const loc = await db.doc(`workerLocations/${uid}`).get();
  if (!loc.exists || loc.data()!.bookingId !== d.bookingId) throw new HttpsError("failed-precondition", "No active trip for this booking");
  await db.doc(`workerLocations/${uid}`).set({ workerUid:uid, bookingId:d.bookingId, latitude:d.latitude, longitude:d.longitude, updatedAt: FieldValue.serverTimestamp() }, { merge:true });
  return { ok:true };
});

// Live Firebase layer — active when VITE_FIREBASE_* env vars are set (see .env.local).
// Falls back to demo local store when absent. Mutations prefer Cloud Functions;
// on Spark (functions not deployed) they use constrained Firestore writes allowed by rules.
import { initializeApp, getApps } from "firebase/app";
import { getAuth, onAuthStateChanged, signInWithEmailAndPassword, signOut, type User } from "firebase/auth";
import { getFirestore, collection, doc, onSnapshot, updateDoc, addDoc, setDoc, getDoc, writeBatch, query, orderBy, limit } from "firebase/firestore";
import { seedBookings, SEED_PAYMENTS, SEED_SUBSCRIPTIONS, SEED_TICKETS } from "../../../packages/shared-types/src/seed";
import { WORKERS } from "../../../packages/shared-types/src/index";

const cfg = { apiKey: import.meta.env.VITE_FIREBASE_API_KEY, authDomain: import.meta.env.VITE_FIREBASE_AUTH_DOMAIN, projectId: import.meta.env.VITE_FIREBASE_PROJECT_ID, storageBucket: import.meta.env.VITE_FIREBASE_STORAGE_BUCKET, messagingSenderId: import.meta.env.VITE_FIREBASE_MESSAGING_SENDER_ID, appId: import.meta.env.VITE_FIREBASE_APP_ID };
export type { User };
export const LIVE = Boolean(cfg.projectId && cfg.apiKey);
export const app = LIVE ? (getApps()[0] ?? initializeApp(cfg)) : null;
export const auth = LIVE ? getAuth(app!) : null;
export const db = LIVE ? getFirestore(app!) : null;

export const watchAuth = (cb: (u: User | null) => void) => auth ? onAuthStateChanged(auth, cb) : () => {};
export const login = (email: string, pw: string) => signInWithEmailAndPassword(auth!, email, pw);
export const logout = () => signOut(auth!);

const strip = (d: any) => { const { _live, ...rest } = d ?? {}; return rest; };
// Firestore Timestamps -> ISO strings so fmtTime/sorting work across panels.
const normTimes = (row: any) => { for (const k of Object.keys(row)) { const v = row[k]; if (v && typeof v.toDate === "function") row[k] = v.toDate().toISOString(); } return row; };
export function subscribeAll(apply: (patch: Record<string, unknown>) => void) {
  if (!db) return () => {};
  const subs: (() => void)[] = [];
  const bind = (name: string, key: string, q?: any) => subs.push(onSnapshot(q ?? collection(db!, name), (s: any) => apply({ [key]: s.docs.map((d: any) => { const row: any = normTimes({ ...strip(d.data()), id: d.id }); // doc id always wins; self-registered workers have no uid field in data
      if (name === "workers") { if (!row.uid) row.uid = d.id; row.serviceAreaIds = row.serviceAreaIds ?? []; row.serviceIds = row.serviceIds ?? row.services ?? []; row.rating = row.rating ?? 0; row.completedJobs = row.completedJobs ?? 0; row.activeJobs = row.activeJobs ?? 0; row.earningsTodayPaise = row.earningsTodayPaise ?? 0; row.distanceKm = row.distanceKm ?? 2; row.photoColor = row.photoColor ?? "#64748b"; row.phone = row.phone ?? ""; } return row; }) }), (e: any) => console.warn(name, e.code)));
  bind("bookings", "bookings"); bind("workers", "workers"); bind("payments", "payments"); bind("subscriptions", "subscriptions"); bind("supportTickets", "tickets"); bind("services", "services");
  subs.push(onSnapshot(query(collection(db!, "auditLogs"), orderBy("createdAt", "desc"), limit(50)), (s) => apply({ audit: s.docs.map(d => normTimes({ id: d.id, ...strip(d.data()) })) }), (e) => console.warn("audit", e.code)));
  return () => subs.forEach(u => u());
}
export const liveUpdate = (coll: string, id: string, patch: Record<string, unknown>) => { if (!db) return Promise.resolve(); if (!id) { console.warn("liveUpdate skipped: missing document id for", coll); return Promise.resolve(); } return updateDoc(doc(db, coll, id), patch as any); };
export const liveAudit = (actor: string, action: string, target: string, reason?: string) => db ? addDoc(collection(db, "auditLogs"), { actor, action, target, reason: reason ?? null, createdAt: new Date().toISOString() }) : Promise.resolve();
export const liveNotify = (recipientUid: string, title: string, body: string, refId?: string) => db ? addDoc(collection(db, "notifications"), { recipientUid, type: "admin", title, body, refId: refId ?? null, bookingId: refId ?? null, read: false, createdAt: new Date().toISOString() }) : Promise.resolve();

/** One-time bootstrap: creates admins/{uid} for the signed-in pilot admin. */
export const claimAdmin = (uid: string, email: string) => db ? setDoc(doc(db, "admins", uid), { email, role: "super_admin", createdAt: new Date().toISOString() }) : Promise.resolve();

/** Auto-activate on sign-in: if the bootstrap admin (admin@washproo.in) has no
 *  admins/{uid} doc yet, create it. Returns "created" | "exists" | "skip". */
export async function ensureAdmin(uid: string, email: string): Promise<"created" | "exists" | "skip"> {
  if (!db) return "skip";
  const snap = await getDoc(doc(db, "admins", uid));
  if (snap.exists()) return "exists";
  if ((email || "").toLowerCase() !== "admin@washproo.in") return "skip";
  await claimAdmin(uid, email);
  return "created";
}

/** One-tap pilot seed (admin only, enforced by rules). Writes shared seed shapes to Firestore. */
export async function seedPilot(adminUid: string, adminEmail: string) {
  if (!db) return;
  const batch = writeBatch(db);
  // NOTE: admins/{uid} is written separately by claimAdmin() — re-setting it here
  // would be an "update" (rules: super_admin claim only) and fail the whole batch.
  for (const b of seedBookings()) batch.set(doc(db, "bookings", b.id), { ...b });
  for (const w of WORKERS) batch.set(doc(db, "workers", w.uid), { ...w, phone: `+91985000000${w.uid.slice(1)}`, email: `${w.name.toLowerCase().replace(/[^a-z]+/g, ".").replace(/^\.|\.$/g, "")}@washpro.in` });
  for (const p of SEED_PAYMENTS) batch.set(doc(db, "payments", p.id), { ...p });
  for (const s of SEED_SUBSCRIPTIONS) batch.set(doc(db, "subscriptions", s.id), { ...s });
  for (const t of SEED_TICKETS) batch.set(doc(db, "supportTickets", t.id), { ...t });
  for (const s of [{ id: "body-wash", name: "Body Wash", tagline: "Foam wash, wheels & exterior finish", durationMinutes: 40, hatchback: 499, sedan: 549, suv: 649, luxury: 799, cashEligible: true, popular: false, active: true }, { id: "interior", name: "Interior Refresh", tagline: "Vacuum, dashboard & surface care", durationMinutes: 60, hatchback: 699, sedan: 749, suv: 849, luxury: 999, cashEligible: true, popular: false, active: true }, { id: "deep-clean", name: "Deep Detail", tagline: "Complete interior & exterior restoration", durationMinutes: 150, hatchback: 1499, sedan: 1649, suv: 1899, luxury: 2299, cashEligible: false, popular: true, active: true }]) batch.set(doc(db, "services", s.id), { ...s });
  for (const pl of [{ id: "weekly", name: "Weekly Shine", kicker: "Best for personal cars", visits: 4, perWashPaise: 39900, totalPaise: 159600, savePercent: 20, billingMode: "prepaid", active: true }, { id: "alternate", name: "Alternate Days", kicker: "Most loved by commuters", visits: 15, perWashPaise: 23900, totalPaise: 358500, savePercent: 28, billingMode: "prepaid", active: true }, { id: "daily", name: "Daily Essential", kicker: "Always looking showroom-ready", visits: 26, perWashPaise: 18900, totalPaise: 491400, savePercent: 34, billingMode: "recurring", active: true }]) batch.set(doc(db, "plans", pl.id), { ...pl });
  batch.set(doc(db, "appConfig", "homeBanner"), { pill: "Doorstep Detailing", heading: "Your car deserves a fresh start.", subheading: "Expert care, right where you park.", cta: "Book a wash", imageUrl: "", active: true });
  batch.set(doc(db, "appConfig", "pilot"), { city: "Hyderabad", timezone: "Asia/Kolkata", currency: "INR", pricingVersion: "hyd-2026.10-v1", workerSharePct: 70 });
  await batch.commit();
}

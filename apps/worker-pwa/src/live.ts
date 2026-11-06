// Live Firebase layer for Worker PWA — active when VITE_FIREBASE_* env set.
// Email/Password Auth (login + self-register) → worker profile → live job subscription.
import { initializeApp, getApps } from "firebase/app";
import { getAuth, onAuthStateChanged, signInWithEmailAndPassword, createUserWithEmailAndPassword, updateProfile, signOut, type User } from "firebase/auth";
import { getFirestore, collection, doc, onSnapshot, updateDoc, setDoc, getDoc, query, where, getDocs } from "firebase/firestore";

const cfg = { apiKey: import.meta.env.VITE_FIREBASE_API_KEY, authDomain: import.meta.env.VITE_FIREBASE_AUTH_DOMAIN, projectId: import.meta.env.VITE_FIREBASE_PROJECT_ID, storageBucket: import.meta.env.VITE_FIREBASE_STORAGE_BUCKET, messagingSenderId: import.meta.env.VITE_FIREBASE_MESSAGING_SENDER_ID, appId: import.meta.env.VITE_FIREBASE_APP_ID };
export const LIVE = Boolean(cfg.projectId && cfg.apiKey);
export const app = LIVE ? (getApps()[0] ?? initializeApp(cfg)) : null;
export const auth = LIVE ? getAuth(app!) : null;
export const db = LIVE ? getFirestore(app!) : null;
export type { User };

export const watchAuth = (cb: (u: User | null) => void) => auth ? onAuthStateChanged(auth, cb) : () => {};
export const logout = () => signOut(auth!);
export const loginEmail = (email: string, pw: string) => signInWithEmailAndPassword(auth!, email.trim(), pw);
/** Self-registration: creates the Auth account + an AUTO-APPROVED worker profile.
 *  Workers can sign in and receive jobs immediately (admin can suspend later). */
export async function registerWorker(name: string, email: string, pw: string) {
  const cred = await createUserWithEmailAndPassword(auth!, email.trim(), pw);
  await updateProfile(cred.user, { displayName: name.trim() }).catch(() => {});
  await setDoc(doc(db!, "workers", cred.user.uid), {
    name: name.trim(), email: email.trim().toLowerCase(), phone: "",
    status: "approved", isAvailable: true, rating: 0, completedJobs: 0,
    serviceAreaIds: [], serviceIds: [], services: [], photoColor: "#0E9F6E",
    createdAt: new Date().toISOString(),
  });
  return cred.user;
}
/** Worker profile for a signed-in user: workers/{uid} (self-registered)
 *  or a legacy/admin-created doc matched by email. */
const workerDefaults = (w: any) => ({ serviceAreaIds: [], serviceIds: [], rating: 0, completedJobs: 0, activeJobs: 0, earningsTodayPaise: 0, photoColor: "#64748b", phone: "", isAvailable: false, ...w });
export async function findWorkerForUser(user: User) {
  if (!db) return null;
  // Auto-approve: profiles registered before auto-approve existed may still be
  // "pending" — flip them to approved on sign-in so nobody stays stuck.
  const withAutoApprove = async (docId: string, data: any) => {
    const w = workerDefaults({ docId, ...data });
    if (w.status === "pending") {
      try { await updateDoc(doc(db!, "workers", docId), { status: "approved", isAvailable: true, updatedAt: new Date().toISOString() }); return { ...w, status: "approved", isAvailable: true }; }
      catch { return w; }
    }
    return w;
  };
  const direct = await getDoc(doc(db, "workers", user.uid));
  if (direct.exists()) return withAutoApprove(direct.id, direct.data());
  if (user.email) {
    const s = await getDocs(query(collection(db, "workers"), where("email", "==", user.email.toLowerCase())));
    if (!s.empty) { const d = s.docs[0]; return withAutoApprove(d.id, d.data()); }
  }
  return null;
}
// Firestore Timestamps -> ISO + safe defaults so job screens never crash on partial docs.
const normJob = (d: any) => { const j: any = { id: d.id, ...d.data() }; for (const k of Object.keys(j)) { const v = j[k]; if (v && typeof v.toDate === "function") j[k] = v.toDate().toISOString(); } j.checklistDone = j.checklistDone ?? []; j.priceSnapshot = j.priceSnapshot ?? { currency: "INR", totalPaise: 0, pricingVersion: "" }; j.customerName = j.customerName ?? "Customer"; j.customerPhone = j.customerPhone ?? ""; j.vehicleLabel = j.vehicleLabel ?? ""; j.addressSnapshot = j.addressSnapshot ?? j.addressLabel ?? ""; return j; };
export function subscribeJobs(workerDocId: string, cb: (bookings: any[]) => void) {
  if (!db) return () => {};
  const q = query(collection(db, "bookings"), where("assignedWorkerUid", "==", workerDocId));
  return onSnapshot(q, (s) => cb(s.docs.map(normJob)), (e) => console.warn("jobs", e.code));
}
export const liveBookingUpdate = (id: string, patch: Record<string, unknown>) => db ? updateDoc(doc(db, "bookings", id), patch as any) : Promise.resolve();
export const liveWorkerUpdate = (id: string, patch: Record<string, unknown>) => db ? updateDoc(doc(db, "workers", id), patch as any) : Promise.resolve();
export const liveLocation = (workerDocId: string, bookingId: string, lat: number, lng: number) => db ? setDoc(doc(db, "workerLocations", workerDocId), { workerUid: workerDocId, bookingId, latitude: lat, longitude: lng, updatedAt: new Date().toISOString() }) : Promise.resolve();
export const clearLocation = (workerDocId: string) => db ? setDoc(doc(db, "workerLocations", workerDocId), { latitude: null, longitude: null, updatedAt: new Date().toISOString() }, { merge: true }) : Promise.resolve();

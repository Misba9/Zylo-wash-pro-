import { initializeApp } from "firebase-admin/app";
import { getFirestore, FieldValue } from "firebase-admin/firestore";
import { HttpsError, CallableRequest } from "firebase-functions/v2/https";
import * as crypto from "crypto";
initializeApp();
export const db = getFirestore();
export { FieldValue };
export type Role = "customer"|"worker"|"admin"|"finance"|"super_admin";
export function requireAuth(req: CallableRequest): string {
  if (!req.auth) throw new HttpsError("unauthenticated", "Sign-in required");
  return req.auth.uid;
}
export function requireRole(req: CallableRequest, roles: Role[]) {
  const uid = requireAuth(req);
  const role = (req.auth!.token as any).role as Role | undefined;
  if (!role || !roles.includes(role)) throw new HttpsError("permission-denied", `Requires role: ${roles.join("/")}`);
  return { uid, role };
}
export async function audit(actor: string, action: string, target: string, reason?: string) {
  await db.collection("auditLogs").add({ actor, action, target, reason: reason ?? null, createdAt: FieldValue.serverTimestamp() });
}
export async function notify(recipientUid: string, type: string, title: string, body: string, refId: string | null) {
  await db.collection("notifications").add({ recipientUid, type, title, body, refId, read: false, createdAt: FieldValue.serverTimestamp() });
  // FCM delivery is best-effort; Firestore record above is source of truth (PRD §13)
  try {
    const { getMessaging } = await import("firebase-admin/messaging");
    const user = await db.doc(`users/${recipientUid}`).get().catch(() => null);
    const token = (user?.data() as any)?.fcmToken;
    if (token) await getMessaging().send({ token, notification: { title, body }, data: { type, refId: refId ?? "" } });
  } catch { /* non-fatal */ }
}
/** Idempotency guard (PRD §3.1.5): returns true if this key was already processed. */
export async function alreadyProcessed(key: string, scope: string): Promise<boolean> {
  const ref = db.doc(`idempotencyKeys/${scope}_${key}`);
  const snap = await ref.get();
  if (snap.exists) return true;
  await ref.set({ scope, key, createdAt: FieldValue.serverTimestamp() });
  return false;
}
export const hmacValid = (payload: string, signature: string, secret: string) =>
  crypto.timingSafeEqual(Buffer.from(crypto.createHmac("sha256", secret).update(payload).digest("hex")), Buffer.from(signature));
export const TRANSITIONS: Record<string, string[]> = {
  requested:["awaiting_payment","confirmed","cancelled"], awaiting_payment:["confirmed","cancelled"],
  confirmed:["assigned","cancelled","under_review"], assigned:["en_route","assigned","cancelled","under_review"],
  en_route:["arrived","cancelled"], arrived:["in_progress","under_review"],
  in_progress:["pending_verification","under_review"], pending_verification:["completed","in_progress","under_review"],
  completed:[], cancelled:[], under_review:["confirmed","assigned","cancelled"],
};
export const PRICES: Record<string, Record<string, number>> = {
  "body-wash": { hatchback:29900, sedan:34900, suv:44900, luxury:59900 },
  "interior": { hatchback:49900, sedan:54900, suv:64900, luxury:79900 },
  "deep-clean": { hatchback:99900, sedan:114900, suv:134900, luxury:169900 },
};
export const DURATIONS: Record<string, Record<string, number>> = {
  "body-wash": { hatchback:30, sedan:35, suv:45, luxury:50 },
  "interior": { hatchback:45, sedan:50, suv:60, luxury:70 },
  "deep-clean": { hatchback:90, sedan:105, suv:120, luxury:150 },
};

/**
 * Authoritative booking price quotes (Phase 2).
 * Reads Firestore catalog + appConfig; never trusts client totals.
 */
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { z } from "zod";
import { db, requireAuth, audit } from "./shared.js";
import {
  quoteBookingPrice,
  quoteToPriceSnapshot,
  seatClassForCategory,
  legacyPricesToSeat,
  DEFAULT_APP_FEES,
  type ServiceDoc,
  type CouponDoc,
  type AppFeesConfig,
  type SeatClass,
  type VehicleCategory,
} from "./catalog_quote.js";

const QuoteSchema = z.object({
  serviceId: z.string().min(1),
  vehicleCategory: z.enum(["hatchback", "sedan", "suv", "luxury"]).optional(),
  seatClass: z.enum(["seater5", "seater7"]).optional(),
  addonIds: z.array(z.string()).default([]),
  express: z.boolean().default(false),
  couponCode: z.string().optional(),
  areaId: z.string().optional(),
  auditPreview: z.boolean().optional(),
});

function asPaiseMaybeRupees(n: number): number {
  // Admin seed historically stored rupees (499); catalog uses paise (49900).
  if (!Number.isFinite(n) || n < 0) return 0;
  return n > 0 && n < 10000 ? Math.round(n * 100) : Math.round(n);
}

function normalizeService(id: string, raw: Record<string, unknown>): ServiceDoc {
  const priceObj = raw.pricePaise as Record<string, number> | undefined;
  let pricePaise: ServiceDoc["pricePaise"] | undefined;
  if (priceObj && "seater5" in priceObj) {
    pricePaise = {
      seater5: asPaiseMaybeRupees(Number(priceObj.seater5)),
      seater7: asPaiseMaybeRupees(Number(priceObj.seater7)),
    };
  } else if (priceObj && "hatchback" in priceObj) {
    pricePaise = legacyPricesToSeat({
      hatchback: asPaiseMaybeRupees(Number(priceObj.hatchback)),
      sedan: asPaiseMaybeRupees(Number(priceObj.sedan)),
      suv: asPaiseMaybeRupees(Number(priceObj.suv)),
      luxury: asPaiseMaybeRupees(Number(priceObj.luxury)),
    });
  } else if (raw.hatchback != null) {
    pricePaise = legacyPricesToSeat({
      hatchback: asPaiseMaybeRupees(Number(raw.hatchback)),
      sedan: asPaiseMaybeRupees(Number(raw.sedan)),
      suv: asPaiseMaybeRupees(Number(raw.suv)),
      luxury: asPaiseMaybeRupees(Number(raw.luxury)),
    });
  }
  if (!pricePaise?.seater5) {
    throw new HttpsError("failed-precondition", `Service ${id} has no seat prices`);
  }

  const durationLegacy = raw.durationMinutes as Record<string, number> | number | undefined;
  let durationMinutes: ServiceDoc["durationMinutes"];
  if (durationLegacy && typeof durationLegacy === "object" && "seater5" in durationLegacy) {
    durationMinutes = {
      seater5: Number(durationLegacy.seater5),
      seater7: Number(durationLegacy.seater7),
    };
  } else if (durationLegacy && typeof durationLegacy === "object") {
    durationMinutes = {
      seater5: Number(durationLegacy.sedan ?? durationLegacy.hatchback ?? 45),
      seater7: Number(durationLegacy.suv ?? durationLegacy.luxury ?? 60),
    };
  } else {
    const d = Number(raw.duration ?? durationLegacy ?? 45);
    durationMinutes = { seater5: d, seater7: d };
  }

  return {
    id,
    name: String(raw.name ?? id),
    tagline: String(raw.tagline ?? ""),
    categoryId: String(raw.categoryId ?? "general"),
    pricePaise,
    durationMinutes,
    serviceFeePaise: raw.serviceFeePaise != null ? Number(raw.serviceFeePaise) : undefined,
    taxPct: raw.taxPct != null ? Number(raw.taxPct) : 0,
    cashEligible: raw.cashEligible !== false,
    active: raw.active !== false,
    archived: !!raw.archived,
    sortOrder: Number(raw.sortOrder ?? 0),
  };
}

async function loadFees(): Promise<AppFeesConfig> {
  const snap = await db.doc("appConfig/fees").get();
  if (!snap.exists) return DEFAULT_APP_FEES;
  const d = snap.data()!;
  return {
    serviceFeePaise: Number(d.serviceFeePaise ?? DEFAULT_APP_FEES.serviceFeePaise),
    expressFeePaise: Number(d.expressFeePaise ?? DEFAULT_APP_FEES.expressFeePaise),
    currency: "INR",
    timezone: "Asia/Kolkata",
    pricingVersion: String(d.pricingVersion ?? DEFAULT_APP_FEES.pricingVersion),
  };
}

async function loadCoupon(code?: string): Promise<CouponDoc | null> {
  if (!code?.trim()) return null;
  const normalized = code.trim().toUpperCase();
  const byId = await db.doc(`coupons/${normalized}`).get();
  if (byId.exists) {
    return { id: byId.id, ...(byId.data() as object) } as CouponDoc;
  }
  const q = await db.collection("coupons").where("code", "==", normalized).limit(1).get();
  if (q.empty) {
    if (normalized === "WELCOME75") {
      return {
        id: "WELCOME75",
        code: "WELCOME75",
        discountType: "fixed",
        discountValue: 7500,
        active: true,
      };
    }
    return null;
  }
  const doc = q.docs[0];
  return { id: doc.id, ...(doc.data() as object) } as CouponDoc;
}

async function buildQuote(data: z.infer<typeof QuoteSchema>) {
  const seat: SeatClass =
    data.seatClass ??
    (data.vehicleCategory
      ? seatClassForCategory(data.vehicleCategory as VehicleCategory)
      : "seater5");

  const serviceSnap = await db.doc(`services/${data.serviceId}`).get();
  if (!serviceSnap.exists) throw new HttpsError("not-found", "Service not found");
  const service = normalizeService(serviceSnap.id, serviceSnap.data() as Record<string, unknown>);

  let addonPaise = 0;
  const addonDetails: { id: string; name: string; pricePaise: number }[] = [];
  for (const id of data.addonIds) {
    const s = await db.doc(`addons/${id}`).get();
    if (!s.exists) continue;
    const a = s.data() as Record<string, unknown>;
    if (a.active === false) continue;
    const seatOk = !Array.isArray(a.applicableSeatClasses) ||
      (a.applicableSeatClasses as string[]).includes(seat);
    const svcOk = !Array.isArray(a.applicableServiceIds) ||
      (a.applicableServiceIds as string[]).includes(data.serviceId);
    if (!seatOk || !svcOk) continue;
    const price = Math.round(Number(a.pricePaise) || 0);
    addonPaise += price;
    addonDetails.push({ id: s.id, name: String(a.name ?? s.id), pricePaise: price });
  }

  const coupon = await loadCoupon(data.couponCode);
  if (data.couponCode && !coupon) {
    throw new HttpsError("invalid-argument", "Unknown or inactive coupon");
  }
  if (coupon && coupon.active === false) {
    throw new HttpsError("failed-precondition", "Coupon is inactive");
  }

  let ruleAdjustmentsPaise = 0;
  try {
    const rulesSnap = await db
      .collection("pricingRules")
      .where("active", "==", true)
      .orderBy("priority", "desc")
      .limit(25)
      .get();
    const now = new Date();
    for (const r of rulesSnap.docs) {
      const rule = r.data();
      if (rule.validFrom && new Date(String(rule.validFrom)) > now) continue;
      if (rule.validTo && new Date(String(rule.validTo)) < now) continue;
      if (rule.areaIds?.length && data.areaId && !rule.areaIds.includes(data.areaId)) continue;
      if (rule.serviceIds?.length && !rule.serviceIds.includes(data.serviceId)) continue;
      if (rule.seatClasses?.length && !rule.seatClasses.includes(seat)) continue;
      if (rule.kind === "express" && !data.express) continue;
      const base = service.pricePaise[seat];
      if (rule.adjustmentType === "percent") {
        ruleAdjustmentsPaise += Math.round((base * Number(rule.adjustmentValue)) / 100);
      } else {
        ruleAdjustmentsPaise += Math.round(Number(rule.adjustmentValue) || 0);
      }
    }
  } catch {
    // Index may be missing until deployed; quote still works without rules.
  }

  const fees = await loadFees();
  let quote;
  try {
    quote = quoteBookingPrice({
      service,
      seatClass: seat,
      addonPaise,
      express: data.express,
      coupon,
      fees,
      ruleAdjustmentsPaise,
    });
  } catch (e) {
    throw new HttpsError("failed-precondition", (e as Error).message);
  }

  return {
    quote,
    priceSnapshot: quoteToPriceSnapshot(quote),
    addons: addonDetails,
  };
}

/** Callable: preview or pre-booking quote. Does not mutate bookings. */
export const quoteBookingPriceFn = onCall(async (req) => {
  requireAuth(req);
  const input = QuoteSchema.parse(req.data ?? {});
  return buildQuote(input);
});

/** Admin calculator + optional audit. */
export const adminPreviewPrice = onCall(async (req) => {
  const uid = requireAuth(req);
  const admin = await db.doc(`admins/${uid}`).get();
  const claim = (req.auth!.token as { role?: string }).role;
  if (!admin.exists && !["admin", "super_admin", "finance"].includes(claim || "")) {
    throw new HttpsError("permission-denied", "Admin only");
  }
  const input = QuoteSchema.parse(req.data ?? {});
  const result = await buildQuote(input);
  if (input.auditPreview) {
    await audit(uid, "previewPrice", input.serviceId, "calculator");
  }
  return result;
});

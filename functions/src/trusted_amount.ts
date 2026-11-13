/**
 * Recompute booking totals from Firestore catalog — never trust client snapshot alone.
 */
import { HttpsError } from "firebase-functions/v2/https";
import { db } from "./shared.js";
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

function asPaiseMaybeRupees(n: number): number {
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
    pricePaise,
    durationMinutes,
    serviceFeePaise: raw.serviceFeePaise != null ? Number(raw.serviceFeePaise) : undefined,
    taxPct: raw.taxPct != null ? Number(raw.taxPct) : 0,
    active: raw.active !== false,
    archived: !!raw.archived,
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
  if (byId.exists) return { id: byId.id, ...(byId.data() as object) } as CouponDoc;
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

/** Server-side amount for a booking document. Overwrites client underpayment. */
export async function resolveTrustedBookingAmount(booking: Record<string, unknown>): Promise<{
  amountPaise: number;
  priceSnapshot: ReturnType<typeof quoteToPriceSnapshot>;
}> {
  const serviceId = String(booking.serviceId || "");
  if (!serviceId) {
    throw new HttpsError("failed-precondition", "Booking missing serviceId");
  }
  const serviceSnap = await db.doc(`services/${serviceId}`).get();
  if (!serviceSnap.exists) {
    // Fall back to stored snapshot only if catalog missing (legacy pilot).
    const fallback = Number((booking.priceSnapshot as { totalPaise?: number })?.totalPaise);
    if (!Number.isInteger(fallback) || fallback < 100) {
      throw new HttpsError("failed-precondition", "Service not found and invalid snapshot");
    }
    return {
      amountPaise: fallback,
      priceSnapshot: booking.priceSnapshot as ReturnType<typeof quoteToPriceSnapshot>,
    };
  }

  const category = String(booking.vehicleCategory || "sedan") as VehicleCategory;
  const seat: SeatClass = seatClassForCategory(
    ["hatchback", "sedan", "suv", "luxury"].includes(category) ? category : "sedan",
  );
  const express =
    booking.bookingType === "instant" ||
    Number((booking.priceSnapshot as { expressFeePaise?: number })?.expressFeePaise || 0) > 0;
  const couponCode = (booking.priceSnapshot as { couponCode?: string })?.couponCode;
  const coupon = await loadCoupon(couponCode);
  const fees = await loadFees();
  const service = normalizeService(serviceSnap.id, serviceSnap.data() as Record<string, unknown>);

  let quote;
  try {
    quote = quoteBookingPrice({
      service,
      seatClass: seat,
      express,
      coupon,
      fees,
      addonPaise: 0,
    });
  } catch (e) {
    throw new HttpsError("failed-precondition", (e as Error).message);
  }

  const clientTotal = Number((booking.priceSnapshot as { totalPaise?: number })?.totalPaise);
  // Never charge less than the server quote (blocks underpayment attacks).
  if (Number.isInteger(clientTotal) && clientTotal > quote.totalPaise) {
    // Client asked for more (e.g. extra add-ons not yet in catalog) — keep higher only if within 2x.
    if (clientTotal <= quote.totalPaise * 2) {
      return {
        amountPaise: clientTotal,
        priceSnapshot: booking.priceSnapshot as ReturnType<typeof quoteToPriceSnapshot>,
      };
    }
  }

  return {
    amountPaise: quote.totalPaise,
    priceSnapshot: quoteToPriceSnapshot(quote),
  };
}

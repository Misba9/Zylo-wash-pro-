/** Local copy of shared-types catalog quote (Functions cannot import monorepo packages). */
export type SeatClass = "seater5" | "seater7";
export type VehicleCategory = "hatchback" | "sedan" | "suv" | "luxury";

export interface SeatPriceMap { seater5: number; seater7: number }

export interface ServiceDoc {
  id: string;
  name: string;
  tagline?: string;
  categoryId?: string;
  pricePaise: SeatPriceMap;
  durationMinutes: SeatPriceMap;
  serviceFeePaise?: number;
  taxPct?: number;
  cashEligible?: boolean;
  active: boolean;
  archived?: boolean;
  sortOrder?: number;
}

export interface CouponDoc {
  id: string;
  code: string;
  discountType: "percent" | "fixed";
  discountValue: number;
  minBookingPaise?: number;
  maxDiscountPaise?: number;
  active: boolean;
}

export interface AppFeesConfig {
  serviceFeePaise: number;
  expressFeePaise: number;
  currency: "INR";
  timezone: "Asia/Kolkata";
  pricingVersion: string;
}

export const DEFAULT_APP_FEES: AppFeesConfig = {
  serviceFeePaise: 2900,
  expressFeePaise: 9900,
  currency: "INR",
  timezone: "Asia/Kolkata",
  pricingVersion: "zylo-2026.11-v2",
};

export function seatClassForCategory(category: VehicleCategory): SeatClass {
  return category === "suv" || category === "luxury" ? "seater7" : "seater5";
}

export function legacyPricesToSeat(map: Partial<Record<VehicleCategory, number>>): SeatPriceMap {
  return {
    seater5: map.sedan ?? map.hatchback ?? 0,
    seater7: map.suv ?? map.luxury ?? map.sedan ?? 0,
  };
}

export function applyCouponDiscount(
  eligibleSubtotal: number,
  coupon: CouponDoc,
): number {
  if (!coupon.active) return 0;
  if (coupon.minBookingPaise && eligibleSubtotal < coupon.minBookingPaise) return 0;
  let d =
    coupon.discountType === "percent"
      ? Math.round((eligibleSubtotal * coupon.discountValue) / 100)
      : Math.round(coupon.discountValue);
  if (coupon.maxDiscountPaise != null) d = Math.min(d, coupon.maxDiscountPaise);
  return Math.max(0, Math.min(d, eligibleSubtotal));
}

export interface QuoteBreakdown {
  currency: "INR";
  serviceId: string;
  serviceName: string;
  seatClass: SeatClass;
  basePaise: number;
  addonPaise: number;
  serviceFeePaise: number;
  expressFeePaise: number;
  ruleAdjustmentsPaise: number;
  discountPaise: number;
  taxPaise: number;
  totalPaise: number;
  couponCode?: string;
  pricingVersion: string;
  estimatedDurationMinutes: number;
}

export function quoteBookingPrice(input: {
  service: ServiceDoc;
  seatClass: SeatClass;
  addonPaise?: number;
  express?: boolean;
  coupon?: CouponDoc | null;
  fees?: AppFeesConfig;
  ruleAdjustmentsPaise?: number;
}): QuoteBreakdown {
  const fees = input.fees ?? DEFAULT_APP_FEES;
  if (!input.service.active || input.service.archived) {
    throw new Error("Service is not available");
  }
  const basePaise = input.service.pricePaise[input.seatClass];
  if (!Number.isInteger(basePaise) || basePaise < 0) {
    throw new Error("Invalid service price");
  }
  const addonPaise = Math.max(0, Math.round(input.addonPaise ?? 0));
  const serviceFeePaise = input.service.serviceFeePaise ?? fees.serviceFeePaise;
  const expressFeePaise = input.express ? fees.expressFeePaise : 0;
  const ruleAdjustmentsPaise = Math.round(input.ruleAdjustmentsPaise ?? 0);
  const preDiscount =
    basePaise + addonPaise + serviceFeePaise + expressFeePaise + ruleAdjustmentsPaise;
  const discountPaise = input.coupon
    ? applyCouponDiscount(basePaise + addonPaise, input.coupon)
    : 0;
  const taxBase = Math.max(0, preDiscount - discountPaise);
  const taxPct = input.service.taxPct ?? 0;
  const taxPaise = Math.round((taxBase * taxPct) / 100);
  const totalPaise = Math.max(100, taxBase + taxPaise);
  return {
    currency: "INR",
    serviceId: input.service.id,
    serviceName: input.service.name,
    seatClass: input.seatClass,
    basePaise,
    addonPaise,
    serviceFeePaise,
    expressFeePaise,
    ruleAdjustmentsPaise,
    discountPaise,
    taxPaise,
    totalPaise,
    couponCode: discountPaise > 0 ? input.coupon?.code : undefined,
    pricingVersion: fees.pricingVersion,
    estimatedDurationMinutes: input.service.durationMinutes[input.seatClass] ?? 45,
  };
}

export function quoteToPriceSnapshot(q: QuoteBreakdown) {
  return {
    currency: "INR" as const,
    subtotalPaise: q.basePaise + q.addonPaise,
    serviceFeePaise: q.serviceFeePaise,
    expressFeePaise: q.expressFeePaise,
    discountPaise: q.discountPaise,
    taxPaise: q.taxPaise,
    totalPaise: q.totalPaise,
    pricingVersion: q.pricingVersion,
    seatClass: q.seatClass,
    ruleAdjustmentsPaise: q.ruleAdjustmentsPaise,
    ...(q.couponCode ? { couponCode: q.couponCode } : {}),
  };
}

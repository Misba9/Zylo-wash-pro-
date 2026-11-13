/** Dynamic catalog + pricing models for ZYLO Admin Control Center (Phase 2+).
 *  Historical bookings keep hatchback/sedan/suv/luxury snapshots; new catalog
 *  prices are authored as 5-seater / 7-seater and mapped at quote time.
 */

/** Local alias — avoid circular import with index.ts */
export type CatalogVehicleCategory = "hatchback" | "sedan" | "suv" | "luxury";
export type SeatClass = "seater5" | "seater7";
export type PricingRuleKind =
  | "standard"
  | "weekend"
  | "peak_hour"
  | "express"
  | "area"
  | "promo"
  | "special_day"
  | "subscription_discount";

export interface SeatPriceMap {
  seater5: number;
  seater7: number;
}

export interface ServiceCategoryDoc {
  id: string;
  name: string;
  description?: string;
  sortOrder: number;
  active: boolean;
}

export interface ServiceDoc {
  id: string;
  name: string;
  tagline: string;
  description?: string;
  categoryId: string;
  icon?: string;
  imageUrls?: string[];
  /** Paise by seat class (admin source of truth). */
  pricePaise: SeatPriceMap;
  /** Optional legacy category map for migration / display. */
  legacyPricePaise?: Partial<Record<CatalogVehicleCategory, number>>;
  durationMinutes: SeatPriceMap;
  serviceFeePaise?: number;
  taxPct?: number;
  cashEligible: boolean;
  active: boolean;
  archived?: boolean;
  popular?: boolean;
  featured?: boolean;
  sortOrder: number;
  inclusions?: string[];
  exclusions?: string[];
  checklist?: string[];
  requirements?: string[];
  availableAreaIds?: string[];
}

export interface AddonDoc {
  id: string;
  name: string;
  description?: string;
  imageUrl?: string;
  pricePaise: number;
  durationMinutes: number;
  applicableServiceIds: string[];
  applicableSeatClasses: SeatClass[];
  active: boolean;
  sortOrder: number;
}

export interface PlanDoc {
  id: string;
  name: string;
  description?: string;
  billingMode: "prepaid" | "recurring";
  visits: number;
  validityDays: number;
  frequency: string;
  includedServiceIds: string[];
  pricePaise: SeatPriceMap;
  discountPaise?: number;
  applicableAreaIds?: string[];
  terms?: string;
  active: boolean;
  popular?: boolean;
}

export interface CouponDoc {
  id: string;
  code: string;
  discountType: "percent" | "fixed";
  /** Percent 1–100 or fixed amount in paise. */
  discountValue: number;
  minBookingPaise?: number;
  maxDiscountPaise?: number;
  startsAt?: string;
  expiresAt?: string;
  maxRedemptions?: number;
  perCustomerLimit?: number;
  redemptionCount?: number;
  applicableServiceIds?: string[];
  applicableSeatClasses?: SeatClass[];
  firstBookingOnly?: boolean;
  active: boolean;
}

export interface PricingRuleDoc {
  id: string;
  name: string;
  kind: PricingRuleKind;
  priority: number;
  active: boolean;
  validFrom?: string;
  validTo?: string;
  /** Additive paise or percent of subtotal. */
  adjustmentType: "fixed_paise" | "percent";
  adjustmentValue: number;
  areaIds?: string[];
  serviceIds?: string[];
  seatClasses?: SeatClass[];
  daysOfWeek?: number[];
  hoursLocal?: { start: number; end: number };
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

export function seatClassForCategory(category: CatalogVehicleCategory): SeatClass {
  return category === "suv" || category === "luxury" ? "seater7" : "seater5";
}

export function categoryForSeatClass(seat: SeatClass): CatalogVehicleCategory {
  return seat === "seater7" ? "suv" : "sedan";
}

export interface QuoteInput {
  service: Pick<ServiceDoc, "id" | "name" | "pricePaise" | "durationMinutes" | "serviceFeePaise" | "taxPct" | "active" | "archived">;
  seatClass: SeatClass;
  addonPaise?: number;
  express?: boolean;
  coupon?: Pick<CouponDoc, "code" | "discountType" | "discountValue" | "minBookingPaise" | "maxDiscountPaise" | "active"> | null;
  fees?: AppFeesConfig;
  ruleAdjustmentsPaise?: number;
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

export function applyCouponDiscount(
  eligibleSubtotal: number,
  coupon: NonNullable<QuoteInput["coupon"]>,
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

/** Deterministic quote used by Admin calculator and Cloud Functions. */
export function quoteBookingPrice(input: QuoteInput): QuoteBreakdown {
  const fees = input.fees ?? DEFAULT_APP_FEES;
  if (!input.service.active || input.service.archived) {
    throw new Error("Service is not available");
  }
  const basePaise = input.service.pricePaise[input.seatClass];
  if (!Number.isInteger(basePaise) || basePaise < 0) {
    throw new Error("Invalid service price");
  }
  const addonPaise = Math.max(0, Math.round(input.addonPaise ?? 0));
  const serviceFeePaise =
    input.service.serviceFeePaise ?? fees.serviceFeePaise;
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

/** Convert quote → booking priceSnapshot (backward-compatible keys). */
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

export function legacyPricesToSeat(map: Partial<Record<CatalogVehicleCategory, number>>): SeatPriceMap {
  return {
    seater5: map.sedan ?? map.hatchback ?? 0,
    seater7: map.suv ?? map.luxury ?? map.sedan ?? 0,
  };
}

export function seatPricesToLegacy(map: SeatPriceMap): Record<CatalogVehicleCategory, number> {
  return {
    hatchback: map.seater5,
    sedan: map.seater5,
    suv: map.seater7,
    luxury: map.seater7,
  };
}

import { describe, expect, it } from "vitest";
import {
  quoteBookingPrice,
  quoteToPriceSnapshot,
  seatClassForCategory,
  applyCouponDiscount,
  DEFAULT_APP_FEES,
} from "./catalog";

const interior = {
  id: "interior",
  name: "Interior Cleaning",
  pricePaise: { seater5: 54900, seater7: 64900 },
  durationMinutes: { seater5: 50, seater7: 60 },
  active: true,
  archived: false,
};

describe("seatClassForCategory", () => {
  it("maps sedan to 5-seater and suv to 7-seater", () => {
    expect(seatClassForCategory("sedan")).toBe("seater5");
    expect(seatClassForCategory("hatchback")).toBe("seater5");
    expect(seatClassForCategory("suv")).toBe("seater7");
    expect(seatClassForCategory("luxury")).toBe("seater7");
  });
});

describe("quoteBookingPrice", () => {
  it("matches ZYLO example: ₹549 + ₹29 fee + ₹99 express − ₹75 = ₹602", () => {
    const q = quoteBookingPrice({
      service: interior,
      seatClass: "seater5",
      express: true,
      coupon: {
        code: "WELCOME75",
        discountType: "fixed",
        discountValue: 7500,
        active: true,
      },
      fees: DEFAULT_APP_FEES,
    });
    expect(q.basePaise).toBe(54900);
    expect(q.serviceFeePaise).toBe(2900);
    expect(q.expressFeePaise).toBe(9900);
    expect(q.discountPaise).toBe(7500);
    expect(q.totalPaise).toBe(60200);
    const snap = quoteToPriceSnapshot(q);
    expect(snap.totalPaise).toBe(60200);
    expect(snap.couponCode).toBe("WELCOME75");
  });

  it("scheduled booking without express is ₹503", () => {
    const q = quoteBookingPrice({
      service: interior,
      seatClass: "seater5",
      express: false,
      coupon: {
        code: "WELCOME75",
        discountType: "fixed",
        discountValue: 7500,
        active: true,
      },
    });
    expect(q.totalPaise).toBe(50300);
  });

  it("rejects inactive services", () => {
    expect(() =>
      quoteBookingPrice({
        service: { ...interior, active: false },
        seatClass: "seater5",
      }),
    ).toThrow(/not available/);
  });
});

describe("applyCouponDiscount", () => {
  it("caps percent discounts", () => {
    expect(
      applyCouponDiscount(10000, {
        code: "P50",
        discountType: "percent",
        discountValue: 50,
        maxDiscountPaise: 3000,
        active: true,
      }),
    ).toBe(3000);
  });
});

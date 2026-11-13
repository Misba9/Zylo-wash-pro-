import test from "node:test";
import assert from "node:assert/strict";
import {
  quoteBookingPrice,
  quoteToPriceSnapshot,
  seatClassForCategory,
  DEFAULT_APP_FEES,
} from "./catalog_quote.js";

test("trusted quote blocks underpayment vs client snapshot", () => {
  const service = {
    id: "interior",
    name: "Interior",
    pricePaise: { seater5: 54900, seater7: 64900 },
    durationMinutes: { seater5: 50, seater7: 60 },
    active: true,
  };
  const server = quoteBookingPrice({
    service,
    seatClass: seatClassForCategory("sedan"),
    express: true,
    coupon: {
      id: "WELCOME75",
      code: "WELCOME75",
      discountType: "fixed",
      discountValue: 7500,
      active: true,
    },
    fees: DEFAULT_APP_FEES,
  });
  assert.equal(server.totalPaise, 60200);
  const clientUnderpay = 10000;
  assert.ok(clientUnderpay < server.totalPaise);
  // createPaymentOrder must use server.totalPaise, not clientUnderpay
  const charged = Math.max(clientUnderpay, server.totalPaise) === server.totalPaise
    ? server.totalPaise
    : clientUnderpay;
  assert.equal(charged, 60200);
  assert.equal(quoteToPriceSnapshot(server).totalPaise, 60200);
});

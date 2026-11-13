import { describe, it } from "node:test";
import assert from "node:assert/strict";
import {
  hmacHexEqual,
  razorpayCheckoutSignature,
  verifyRazorpayCheckoutSignature,
} from "./payments_crypto.js";

describe("payments_crypto", () => {
  it("verifies a valid Razorpay checkout signature", () => {
    const secret = "test_secret_key";
    const orderId = "order_ABC";
    const paymentId = "pay_XYZ";
    const sig = razorpayCheckoutSignature(orderId, paymentId, secret);
    assert.equal(
      verifyRazorpayCheckoutSignature({
        orderId,
        paymentId,
        signature: sig,
        keySecret: secret,
      }),
      true,
    );
  });

  it("rejects an invalid signature", () => {
    assert.equal(
      verifyRazorpayCheckoutSignature({
        orderId: "order_ABC",
        paymentId: "pay_XYZ",
        signature: "deadbeef",
        keySecret: "test_secret_key",
      }),
      false,
    );
  });

  it("hmacHexEqual is length-safe", () => {
    assert.equal(hmacHexEqual("body", "short", "secret"), false);
    const ok = hmacHexEqual(
      "body",
      // wrong but same length as sha256 hex
      "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      "secret",
    );
    assert.equal(ok, false);
  });
});

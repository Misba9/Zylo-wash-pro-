import { test, expect } from "@playwright/test";
import { skipReason } from "../../helpers/auth";

/**
 * Payment automation boundaries.
 * Razorpay Checkout is hosted (iframe/SDK). We verify app-side invariants in unit
 * tests (trusted_amount, HMAC). Browser E2E does not drive Live Mode or bank OTP.
 */
test.describe("Razorpay payment boundaries", () => {
  test("documents that hosted checkout is not fully automatable here", async () => {
    test.info().annotations.push({
      type: "note",
      description: skipReason.razorpayHosted,
    });
    expect(skipReason.razorpayHosted.length).toBeGreaterThan(10);
  });

  test("Flutter native payment path is out of Playwright scope", async () => {
    test.skip(true, skipReason.flutterNative);
  });

  test("manual Test Mode checklist is required before Live", async () => {
    test.info().annotations.push({
      type: "manual",
      description:
        "Manual: Cards + UPI Collect success@razorpay; verifyPayment; webhook; no client-only paid.",
    });
    expect(true).toBeTruthy();
  });
});

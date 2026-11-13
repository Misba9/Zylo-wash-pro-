import { test } from "@playwright/test";
import { skipReason } from "../../helpers/auth";

test.describe("Customer booking (Flutter)", () => {
  test("3-step booking + Razorpay is Flutter native — not browser-automated", async () => {
    test.skip(true, skipReason.flutterNative);
  });
});

import { test, expect } from "@playwright/test";
import { urls } from "../../config/urls";

test.describe("Security & isolation (browser)", () => {
  test("customer marketing site does not expose admin sidebar", async ({ page }) => {
    await page.goto(urls.websiteLocal, { waitUntil: "domcontentloaded" });
    await expect(page.getByRole("button", { name: /Audit Logs|Admin Users/i })).toHaveCount(0);
  });

  test("worker hosted app does not embed admin Control chrome", async ({ page }) => {
    await page.goto(urls.workerHosted, { waitUntil: "domcontentloaded" });
    await expect(page.getByText(/ZYLO\s+Control/i)).toHaveCount(0);
    await expect(page.getByText(/ZYLO|Field/i).first()).toBeVisible();
  });

  test("admin hosted login required for protected ops", async ({ page }) => {
    await page.goto(urls.adminHosted, { waitUntil: "domcontentloaded" });
    // Unauthenticated users should see login, not bookings table.
    const login = page.getByRole("button", { name: /Sign in/i });
    const bookings = page.getByRole("heading", { name: /Bookings/i });
    if (await login.isVisible().catch(() => false)) {
      await expect(bookings).toHaveCount(0);
    } else {
      // Already signed-in browser profile — still must not show Firebase secrets.
      const content = await page.content();
      expect(content).not.toMatch(/rzp_live_[A-Za-z0-9]+/);
      expect(content).not.toMatch(/RAZORPAY_KEY_SECRET/);
    }
  });

  test("frontend bundles must not embed Razorpay secret patterns", async ({
    request,
  }) => {
    const res = await request.get(urls.marketing);
    expect(res.ok()).toBeTruthy();
    const html = await res.text();
    expect(html).not.toMatch(/rzp_live_[A-Za-z0-9]{10,}/);
    expect(html).not.toMatch(/sk_live_|RAZORPAY_KEY_SECRET\s*=\s*['\"][^'\"]+/);
  });

  test("XSS probe on marketing contact fields does not execute script", async ({
    page,
  }) => {
    await page.goto(urls.websiteLocal, { waitUntil: "domcontentloaded" });
    let dialog = false;
    page.on("dialog", async (d) => {
      dialog = true;
      await d.dismiss();
    });
    // Marketing site is mostly static anchors — inject via URL hash only.
    await page.goto(`${urls.websiteLocal}/#services"><img src=x onerror=alert(1)>`, {
      waitUntil: "domcontentloaded",
    });
    await page.waitForTimeout(500);
    expect(dialog).toBeFalsy();
  });
});

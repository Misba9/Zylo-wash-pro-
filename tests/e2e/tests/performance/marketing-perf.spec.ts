import { test, expect } from "@playwright/test";
import { urls } from "../../config/urls";

test.describe("Performance (marketing)", () => {
  test("local marketing DOMContentLoaded under documented budget", async ({
    page,
  }) => {
    const start = Date.now();
    await page.goto(urls.websiteLocal, { waitUntil: "domcontentloaded" });
    const dcl = Date.now() - start;
    // Soft budget for local Vite — document condition, not a hard SLA.
    test.info().annotations.push({
      type: "perf",
      description: `DOMContentLoaded ${dcl}ms on local Vite (budget 8000ms)`,
    });
    expect(dcl).toBeLessThan(8_000);
    await expect(page.getByText(/ZYLO/i).first()).toBeVisible();
  });

  test("production host TTFB smoke", async ({ request }) => {
    const start = Date.now();
    const res = await request.get(urls.marketing);
    const ms = Date.now() - start;
    expect(res.ok()).toBeTruthy();
    test.info().annotations.push({
      type: "perf",
      description: `GET ${urls.marketing} ${ms}ms status=${res.status()}`,
    });
    expect(ms).toBeLessThan(15_000);
  });
});

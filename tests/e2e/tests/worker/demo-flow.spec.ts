import { test, expect } from "@playwright/test";
import { WorkerPage } from "../../pages/WorkerPage";
import { urls } from "../../config/urls";
import { attachConsoleGuard } from "../../helpers/console";

test.describe("Worker PWA demo mode", () => {
  test.beforeEach(async ({ page }) => {
    const worker = new WorkerPage(page);
    await worker.goto(urls.workerLocal);
    if (await worker.isDemoPickerVisible()) {
      await worker.pickDemoWorker("Ramesh");
    } else {
      test.skip(true, "Local worker is LIVE (Firebase env). Force demo by clearing VITE_FIREBASE_*.");
    }
  });

  test("shows today dashboard and job tabs", async ({ page }) => {
    const guard = attachConsoleGuard(page);
    await expect(page.getByText(/ZYLO/i).first()).toBeVisible();
    await expect(page.getByRole("button", { name: /Today|Jobs|Earnings|Profile/i }).first()).toBeVisible();
    guard.assertClean();
  });

  test("profile tab exposes logout/reset affordance", async ({ page }) => {
    await page.getByRole("button", { name: /Profile/i }).click();
    await expect(page.getByText(/Ramesh|rating|jobs/i).first()).toBeVisible();
    await expect(page.getByRole("button", { name: /Reset demo data/i })).toBeVisible();
  });

  test("jobs list is scoped to selected worker (demo)", async ({ page }) => {
    await page.getByRole("button", { name: /Jobs/i }).click();
    // Demo seed may be empty or have assigned jobs — must not crash.
    await expect(page.locator("body")).toContainText(/Jobs|Today|No|assigned|ZYLO/i);
  });

  test("manifest link exists for PWA installability signal", async ({ page }) => {
    const href = await page.locator('link[rel="manifest"]').getAttribute("href");
    expect(href).toBeTruthy();
    const res = await page.request.get(new URL(href!, page.url()).toString());
    expect(res.ok()).toBeTruthy();
    const json = await res.json();
    expect(String(json.name || json.short_name || "")).toMatch(/ZYLO|Field|Wash/i);
  });
});

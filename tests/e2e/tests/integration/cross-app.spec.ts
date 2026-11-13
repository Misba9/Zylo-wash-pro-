import { test, expect } from "@playwright/test";
import { urls } from "../../config/urls";
import { AdminPage } from "../../pages/AdminPage";
import { WorkerPage } from "../../pages/WorkerPage";
import { MarketingPage } from "../../pages/MarketingPage";

test.describe("Cross-application smoke (demo + public)", () => {
  test("marketing → app CTA path exists", async ({ page }) => {
    const site = new MarketingPage(page);
    await site.goto(urls.websiteLocal);
    await site.expectLoaded();
    await expect(page.getByRole("link", { name: /Get the app|Book a Wash/i }).first()).toBeVisible();
  });

  test("admin demo can open bookings while worker demo stays separate", async ({
    browser,
  }) => {
    const adminCtx = await browser.newContext();
    const workerCtx = await browser.newContext();
    const adminPage = await adminCtx.newPage();
    const workerPage = await workerCtx.newPage();

    const admin = new AdminPage(adminPage);
    await admin.goto(urls.adminLocal);
    test.skip(!(await admin.isDemoMode()), "Admin demo unavailable");

    const worker = new WorkerPage(workerPage);
    await worker.goto(urls.workerLocal);
    test.skip(!(await worker.isDemoPickerVisible()), "Worker demo unavailable");

    await admin.openNav("bookings");
    await expect(adminPage.getByRole("heading", { name: /Bookings/i })).toBeVisible();

    await worker.pickDemoWorker("Ramesh");
    await expect(workerPage.getByText(/ZYLO/i).first()).toBeVisible();
    // Isolation: worker must not show Admin audit nav.
    await expect(workerPage.getByTestId("nav-audit")).toHaveCount(0);

    await adminCtx.close();
    await workerCtx.close();
  });

  test("Flow A/B/C booking-payment-worker completion is Flutter+CF — marked blocked for browser suite", async () => {
    test.skip(
      true,
      "Full Flow A–C requires Flutter customer + Firebase test accounts. Covered partially by unit/CF tests; device E2E pending.",
    );
  });
});

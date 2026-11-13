import { test, expect } from "@playwright/test";
import { AdminPage } from "../../pages/AdminPage";
import { urls } from "../../config/urls";
import { attachConsoleGuard } from "../../helpers/console";

test.describe("Admin Control demo mode", () => {
  test.beforeEach(async ({ page }) => {
    const admin = new AdminPage(page);
    await admin.goto(urls.adminLocal);
    if (!(await admin.isDemoMode())) {
      test.skip(true, "Local admin is LIVE. Start with VITE_FIREBASE_* cleared for demo.");
    }
  });

  test("dashboard KPIs and sidebar navigate", async ({ page }) => {
    const guard = attachConsoleGuard(page);
    const admin = new AdminPage(page);
    await expect(page.getByText(/Dashboard|Overview|Good morning|Bookings/i).first()).toBeVisible();
    await admin.openNav("bookings");
    await expect(page.getByRole("heading", { name: /Bookings/i })).toBeVisible();
    await admin.openNav("services");
    await expect(page.getByText(/5-seater|Services|Pricing/i).first()).toBeVisible();
    guard.assertClean();
  });

  test("pricing calculator shows ZYLO quote breakdown", async ({ page }) => {
    const admin = new AdminPage(page);
    await admin.openNav("pricing");
    await expect(page.getByText(/Pricing calculator|Final payable|ZYLO quote/i).first()).toBeVisible();
    await expect(page.getByText(/₹|INR|paise|Final payable/i).first()).toBeVisible();
  });

  test("services page can edit seat prices in demo memory", async ({ page }) => {
    const admin = new AdminPage(page);
    await admin.openNav("services");
    const save = page.getByRole("button", { name: /^Save$/i }).first();
    await expect(save).toBeVisible();
    await save.click();
    await expect(page.getByText(/Saved|Pricing updated|new bookings/i).first()).toBeVisible({
      timeout: 10_000,
    });
  });

  test("finance and audit pages open", async ({ page }) => {
    const admin = new AdminPage(page);
    await admin.openNav("finance");
    await expect(page.getByText(/Payments|Collected|Revenue/i).first()).toBeVisible();
    await admin.openNav("audit");
    await expect(page.getByText(/Audit/i).first()).toBeVisible();
  });
});

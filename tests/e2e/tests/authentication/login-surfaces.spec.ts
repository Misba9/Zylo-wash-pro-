import { test, expect } from "@playwright/test";
import { AdminPage } from "../../pages/AdminPage";
import { WorkerPage } from "../../pages/WorkerPage";
import { urls } from "../../config/urls";
import { hasAdminCreds, hasFirebaseTestPhone, skipReason } from "../../helpers/auth";

test.describe("Authentication surfaces", () => {
  test("admin demo mode boots without credentials", async ({ page }) => {
    const admin = new AdminPage(page);
    await admin.goto(urls.adminLocal);
    // Demo: sidebar visible. Live local would show login — either is valid.
    const demo = await admin.isDemoMode();
    const login = await admin.isLoginForm();
    expect(demo || login).toBeTruthy();
    if (demo) {
      // Sidebar labels are hidden <860px; assert main content + nav test id.
      await expect(page.getByTestId("nav-overview")).toBeAttached();
      await expect(page.locator("main").getByRole("heading", { name: /Good morning/i })).toBeVisible();
    }
  });

  test("admin rejects invalid credentials on hosted login", async ({ page }) => {
    await page.goto(urls.adminHosted, { waitUntil: "domcontentloaded" });
    const signIn = page.getByRole("button", { name: /Sign in/i });
    if (!(await signIn.isVisible().catch(() => false))) {
      test.skip(true, "Hosted admin already authenticated or demo — skipping invalid login.");
    }
    await page.locator('input[type="email"]').fill("not-an-admin@example.com");
    await page.locator('input[type="password"]').fill("wrong-password-xyz");
    await signIn.click();
    await expect(page.getByText(/Wrong email or password|Login failed|invalid/i)).toBeVisible({
      timeout: 15_000,
    });
  });

  test("worker field shows login or demo picker", async ({ page }) => {
    const worker = new WorkerPage(page);
    await worker.goto(urls.workerLocal);
    await expect(worker.brand).toBeVisible();
    const demo = await worker.isDemoPickerVisible();
    if (demo) {
      await worker.pickDemoWorker("Ramesh");
      await expect(page.getByText(/Today|Jobs|Earnings/i).first()).toBeVisible();
    } else {
      await expect(worker.email).toBeVisible();
      await expect(worker.signIn).toBeVisible();
    }
  });

  test("worker invalid login shows error on hosted field", async ({ page }) => {
    await page.goto(urls.workerHosted, { waitUntil: "domcontentloaded" });
    const email = page.getByPlaceholder(/Work email/i);
    if (!(await email.isVisible().catch(() => false))) {
      test.skip(true, "Worker already in session or unexpected shell.");
    }
    await email.fill("customer@example.com");
    await page.getByPlaceholder(/Password/i).fill("not-a-worker");
    await page.getByRole("button", { name: /Sign in to ZYLO Field/i }).click();
    await expect(
      page.getByText(/Wrong email or password|No worker profile|Customer accounts cannot/i),
    ).toBeVisible({ timeout: 20_000 });
  });

  test("live admin login (optional creds)", async ({ page }) => {
    test.skip(!hasAdminCreds(), skipReason.noAdmin);
    const admin = new AdminPage(page);
    await admin.goto(urls.adminHosted);
    if (await admin.isLoginForm()) {
      const { email, password } = {
        email: process.env.E2E_ADMIN_EMAIL!,
        password: process.env.E2E_ADMIN_PASSWORD!,
      };
      await admin.login(email, password);
      await expect(page.getByText(/LIVE|Bookings|Dashboard/i).first()).toBeVisible({
        timeout: 30_000,
      });
    }
  });

  test("OTP phone auth not claimed without Firebase test number", async () => {
    test.skip(!hasFirebaseTestPhone(), skipReason.noPhone);
    test.skip(true, skipReason.flutterNative);
  });
});

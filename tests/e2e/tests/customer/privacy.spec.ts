import { test, expect } from "@playwright/test";
import { urls } from "../../config/urls";

test.describe("Privacy & account deletion pages", () => {
  test("privacy policy is publicly reachable", async ({ page }) => {
    const res = await page.goto(urls.privacy, { waitUntil: "domcontentloaded" });
    expect(res?.ok()).toBeTruthy();
    await expect(page.getByRole("heading", { name: /Privacy/i })).toBeVisible();
    await expect(page.getByText(/Delete account|account deletion/i).first()).toBeVisible();
  });

  test("account deletion page is publicly reachable", async ({ page }) => {
    const res = await page.goto(urls.deleteAccount, {
      waitUntil: "domcontentloaded",
    });
    expect(res?.ok()).toBeTruthy();
    await expect(page.getByText(/delete|deletion/i).first()).toBeVisible();
  });
});

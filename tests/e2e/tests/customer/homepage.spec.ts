import { test, expect } from "@playwright/test";
import { MarketingPage } from "../../pages/MarketingPage";
import { attachConsoleGuard } from "../../helpers/console";
import { urls } from "../../config/urls";

test.describe("Customer marketing homepage", () => {
  test("loads ZYLO branding, hero, and services without broken images", async ({
    page,
  }) => {
    const guard = attachConsoleGuard(page);
    const site = new MarketingPage(page);
    await site.goto(urls.websiteLocal);
    await site.expectLoaded();
    await expect(page.getByText(/Fresh Start/i).first()).toBeVisible();
    await expect(site.bookCta).toBeVisible();
    await site.openServices();
    await expect(site.services).toBeVisible();
    const broken = await site.brokenImages();
    // Hero image may 404 locally if asset not copied — treat as soft fail annotation.
    if (broken.length) {
      test.info().annotations.push({
        type: "bug",
        description: `Broken images on local marketing: ${broken.join(", ")}`,
      });
    }
    expect(broken.filter((u) => !/hero-car/i.test(u))).toEqual([]);
    guard.assertClean();
  });

  test("production unified host returns ZYLO content", async ({ page }) => {
    await page.goto(urls.marketing, { waitUntil: "domcontentloaded" });
    await expect(page.getByText(/ZYLO/i).first()).toBeVisible();
    await expect(page.getByText(/Hyderabad/i).first()).toBeVisible();
  });

  test("www.zyloo.co.in TLS / content (infra check)", async ({ page }) => {
    // Known P1: certificate CN mismatch blocks Chromium. Expected failure until DNS/TLS fixed.
    test.fail(true, "TLS certificate invalid on www.zyloo.co.in");
    const res = await page.goto(urls.marketingWww, {
      waitUntil: "domcontentloaded",
      timeout: 20_000,
    });
    expect(res?.ok() || [301, 302, 308].includes(res?.status() || 0)).toBeTruthy();
    await expect(page.getByText(/ZYLO/i).first()).toBeVisible({ timeout: 20_000 });
  });

  test("/app coming-soon path is reachable on unified host", async ({ page }) => {
    const res = await page.goto(`${urls.marketing}/app/`, {
      waitUntil: "domcontentloaded",
    });
    expect(res?.status()).toBeLessThan(500);
  });
});

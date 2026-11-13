import { test, expect } from "@playwright/test";
import { urls } from "../../config/urls";

test.describe("Public HTTP / API smoke", () => {
  test("marketing and privacy endpoints are healthy", async ({ request }) => {
    for (const url of [urls.marketing, urls.privacy, urls.deleteAccount, urls.customerWeb]) {
      const res = await request.get(url);
      expect(res.status(), url).toBeLessThan(500);
      expect([200, 301, 302, 304]).toContain(res.status());
    }
  });

  test("root domain redirects to www", async ({ request }) => {
    const res = await request.get(urls.marketingRoot, { maxRedirects: 0 });
    expect([301, 302, 308]).toContain(res.status());
    const loc = res.headers()["location"] || "";
    expect(loc).toMatch(/www\.zyloo\.co\.in/);
  });

  test("field.zyloo.co.in redirect target is DNS-valid", async ({ request }) => {
    // Known P1: field.zyloo.co.in 301 → www.field.zyloo.co.in (ENOTFOUND). Expected fail until DNS fixed.
    test.fail(true, "field.zyloo.co.in redirects to www.field.zyloo.co.in (DNS ENOTFOUND)");
    const res = await request.get(urls.fieldLegacy, { maxRedirects: 0 });
    expect([200, 301, 302, 308]).toContain(res.status());
    const loc = res.headers()["location"] || "";
    test.info().annotations.push({
      type: "blocker",
      description: `field.zyloo.co.in → ${loc || "(none)"}; workerHosted still used as fallback`,
    });
    const hosted = await request.get(urls.workerHosted);
    expect(hosted.ok()).toBeTruthy();
    expect(loc).not.toMatch(/www\.field\.zyloo\.co\.in/i);
  });

  test("unified /field and /admin return HTML shells", async ({ request }) => {
    for (const url of [urls.unifiedField, urls.unifiedAdmin]) {
      const res = await request.get(url);
      expect(res.ok()).toBeTruthy();
      const ct = res.headers()["content-type"] || "";
      expect(ct).toMatch(/text\/html/);
    }
  });

  test("callable HTTPS without auth is rejected (Functions)", async ({ request }) => {
    // Cloud Functions Gen2 HTTP endpoint pattern — unauthenticated call should fail.
    const project = "wash-pro-7f3b1";
    const region = "us-central1";
    const url = `https://${region}-${project}.cloudfunctions.net/createPaymentOrder`;
    const res = await request.post(url, {
      data: { data: { bookingId: "e2e-fake" } },
      headers: { "Content-Type": "application/json" },
      failOnStatusCode: false,
    });
    // 401/403/404 all acceptable depending on deploy/IAM; never 200 success.
    expect(res.status()).not.toBe(200);
  });
});

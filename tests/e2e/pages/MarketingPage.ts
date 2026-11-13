import type { Page, Locator } from "@playwright/test";

export class MarketingPage {
  readonly page: Page;
  readonly brand: Locator;
  readonly hero: Locator;
  readonly bookCta: Locator;
  readonly services: Locator;

  constructor(page: Page) {
    this.page = page;
    this.brand = page.getByRole("link", { name: /ZYLO/i }).first();
    this.hero = page.getByRole("region", { name: /ZYLO hero/i });
    this.bookCta = page.getByRole("link", { name: /Book a Wash/i }).first();
    this.services = page.locator("#services");
  }

  async goto(url = "/") {
    await this.page.goto(url, { waitUntil: "domcontentloaded" });
  }

  async expectLoaded() {
    await this.brand.waitFor({ state: "visible" });
    await this.hero.waitFor({ state: "visible" });
  }

  async openServices() {
    await this.page.getByRole("link", { name: /Explore Services|Services/i }).first().click();
    await this.services.waitFor({ state: "visible" });
  }

  async brokenImages(): Promise<string[]> {
    return this.page.evaluate(() =>
      Array.from(document.images)
        .filter((img) => !img.complete || img.naturalWidth === 0)
        .map((img) => img.src),
    );
  }
}

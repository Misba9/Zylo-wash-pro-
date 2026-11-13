import type { Page, Locator } from "@playwright/test";

export class WorkerPage {
  readonly page: Page;
  readonly brand: Locator;
  readonly email: Locator;
  readonly password: Locator;
  readonly signIn: Locator;

  constructor(page: Page) {
    this.page = page;
    this.brand = page.getByText(/ZYLO\s+Field/i).first();
    this.email = page.getByPlaceholder(/Work email/i);
    this.password = page.getByPlaceholder(/Password/i);
    this.signIn = page.getByRole("button", { name: /Sign in to ZYLO Field|Create field account/i });
  }

  async goto(base?: string) {
    await this.page.goto(base || "/", { waitUntil: "domcontentloaded" });
  }

  async isDemoPickerVisible() {
    return this.page.getByText(/Demo mode only/i).isVisible().catch(() => false);
  }

  async pickDemoWorker(name = "Ramesh") {
    await this.page.getByText(new RegExp(name, "i")).first().click();
  }

  async login(email: string, password: string) {
    await this.email.fill(email);
    await this.password.fill(password);
    await this.signIn.click();
  }

  async openTab(name: "Today" | "Jobs" | "Earnings" | "Profile") {
    await this.page.getByRole("button", { name: new RegExp(name, "i") }).click();
  }
}

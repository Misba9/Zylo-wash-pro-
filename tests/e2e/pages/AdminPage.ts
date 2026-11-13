import type { Page, Locator } from "@playwright/test";

export class AdminPage {
  readonly page: Page;
  readonly brand: Locator;
  readonly email: Locator;
  readonly password: Locator;
  readonly signIn: Locator;

  constructor(page: Page) {
    this.page = page;
    this.brand = page.getByText(/ZYLO\s+Control|Wash/i).first();
    this.email = page.locator('input[type="email"]');
    this.password = page.locator('input[type="password"]');
    this.signIn = page.getByRole("button", { name: /Sign in/i });
  }

  async goto(base?: string) {
    await this.page.goto(base || "/", { waitUntil: "domcontentloaded" });
  }

  async isDemoMode() {
    // "Demo mode" copy is inside .hideS and hidden under ~860px; use stable signals.
    const byCopy = await this.page.getByText(/Demo mode/i).isVisible().catch(() => false);
    if (byCopy) return true;
    const byReset = await this.page
      .getByRole("button", { name: /Reset demo data/i })
      .isVisible()
      .catch(() => false);
    if (byReset) return true;
    const hasNav = await this.page.getByTestId("nav-overview").isVisible().catch(() => false);
    const hasLogin = await this.isLoginForm();
    return hasNav && !hasLogin;
  }

  async isLoginForm() {
    return this.signIn.isVisible().catch(() => false);
  }

  async login(email: string, password: string) {
    await this.email.fill(email);
    await this.password.fill(password);
    await this.signIn.click();
  }

  /** Sidebar nav uses data-testid=nav-{pageId}; pageId matches App.tsx keys. */
  async openNav(pageId: string) {
    await this.page.getByTestId(`nav-${pageId}`).click();
  }
}

import { defineConfig, devices } from "@playwright/test";
import dotenv from "dotenv";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
dotenv.config({ path: path.join(__dirname, ".env.test") });

const MARKETING =
  process.env.E2E_MARKETING_URL || "https://wash-pro-7f3b1.web.app";
const WORKER =
  process.env.E2E_WORKER_URL || "http://127.0.0.1:5174";
const ADMIN =
  process.env.E2E_ADMIN_URL || "http://127.0.0.1:5173";
const CUSTOMER_WEB =
  process.env.E2E_CUSTOMER_WEB_URL || "https://wash-pro-customer.web.app";
const USE_LOCAL_DEMO = process.env.E2E_LOCAL_DEMO !== "0";

export default defineConfig({
  testDir: "./tests",
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 2 : 1,
  workers: process.env.CI ? 2 : undefined,
  timeout: 60_000,
  expect: { timeout: 12_000 },
  reporter: [
    ["list"],
    ["html", { outputFolder: "reports/html", open: "never" }],
    ["json", { outputFile: "reports/results.json" }],
  ],
  outputDir: "reports/test-output",
  globalSetup: "./global-setup.ts",
  globalTeardown: "./global-teardown.ts",
  use: {
    trace: "on-first-retry",
    screenshot: "only-on-failure",
    video: "retain-on-failure",
    actionTimeout: 15_000,
    navigationTimeout: 45_000,
    ignoreHTTPSErrors: false,
  },
  projects: [
    {
      name: "chromium",
      testIgnore: [/worker\/.*\.spec\.ts/, /admin\/.*\.spec\.ts/, /api\/.*\.spec\.ts/],
      use: { ...devices["Desktop Chrome"], baseURL: MARKETING },
    },
    {
      name: "firefox",
      testIgnore: [/worker\/.*\.spec\.ts/, /admin\/.*\.spec\.ts/, /api\/.*\.spec\.ts/],
      use: { ...devices["Desktop Firefox"], baseURL: MARKETING },
    },
    {
      name: "webkit",
      testIgnore: [/worker\/.*\.spec\.ts/, /admin\/.*\.spec\.ts/, /api\/.*\.spec\.ts/],
      use: { ...devices["Desktop Safari"], baseURL: MARKETING },
    },
    {
      name: "mobile-chrome",
      testIgnore: [/worker\/.*\.spec\.ts/, /admin\/.*\.spec\.ts/, /api\/.*\.spec\.ts/],
      use: { ...devices["Pixel 7"], baseURL: MARKETING },
    },
    {
      name: "mobile-safari",
      testIgnore: [/worker\/.*\.spec\.ts/, /admin\/.*\.spec\.ts/, /api\/.*\.spec\.ts/],
      use: { ...devices["iPhone 14"], baseURL: MARKETING },
    },
    {
      name: "tablet",
      testIgnore: [/worker\/.*\.spec\.ts/, /admin\/.*\.spec\.ts/, /api\/.*\.spec\.ts/],
      use: { ...devices["iPad Pro 11"], baseURL: MARKETING },
    },
    {
      name: "worker-demo",
      testMatch: /worker\/.*\.spec\.ts/,
      use: { ...devices["Desktop Chrome"], baseURL: WORKER },
    },
    {
      name: "admin-demo",
      testMatch: /admin\/.*\.spec\.ts/,
      use: { ...devices["Desktop Chrome"], baseURL: ADMIN },
    },
    {
      name: "api",
      testMatch: /api\/.*\.spec\.ts/,
      use: { baseURL: MARKETING },
    },
  ],
  webServer: USE_LOCAL_DEMO
    ? [
        {
          command:
            "npm run dev -w @zylo/website -- --host 127.0.0.1 --port 5175 --strictPort",
          cwd: path.join(__dirname, "../.."),
          url: "http://127.0.0.1:5175",
          reuseExistingServer: !process.env.CI && process.env.E2E_FORCE_DEMO !== "1",
          timeout: 120_000,
        },
        {
          // Force demo mode: process.env wins over apps/*/.env.local in Vite.
          command:
            "npm run dev -w @zylo/field -- --host 127.0.0.1 --port 5174 --strictPort",
          cwd: path.join(__dirname, "../.."),
          url: "http://127.0.0.1:5174",
          reuseExistingServer: !process.env.CI && process.env.E2E_FORCE_DEMO !== "1",
          timeout: 120_000,
          env: {
            ...process.env,
            VITE_FIREBASE_API_KEY: "",
            VITE_FIREBASE_PROJECT_ID: "",
            VITE_FIREBASE_AUTH_DOMAIN: "",
            VITE_FIREBASE_APP_ID: "",
            VITE_FIREBASE_STORAGE_BUCKET: "",
            VITE_FIREBASE_MESSAGING_SENDER_ID: "",
          },
        },
        {
          command:
            "npm run dev -w @washpro/admin-dashboard -- --host 127.0.0.1 --port 5173 --strictPort",
          cwd: path.join(__dirname, "../.."),
          url: "http://127.0.0.1:5173",
          reuseExistingServer: !process.env.CI && process.env.E2E_FORCE_DEMO !== "1",
          timeout: 120_000,
          env: {
            ...process.env,
            VITE_FIREBASE_API_KEY: "",
            VITE_FIREBASE_PROJECT_ID: "",
            VITE_FIREBASE_AUTH_DOMAIN: "",
            VITE_FIREBASE_APP_ID: "",
            VITE_FIREBASE_STORAGE_BUCKET: "",
            VITE_FIREBASE_MESSAGING_SENDER_ID: "",
          },
        },
      ]
    : undefined,
  metadata: {
    marketing: MARKETING,
    worker: WORKER,
    admin: ADMIN,
    customerWeb: CUSTOMER_WEB,
    note: "Device emulation ≠ real Android/iOS devices. Flutter native app is out of Playwright scope.",
  },
});

export const e2eUrls = { MARKETING, WORKER, ADMIN, CUSTOMER_WEB };

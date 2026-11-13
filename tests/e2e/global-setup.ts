import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

export default async function globalSetup() {
  const root = path.dirname(fileURLToPath(import.meta.url));
  for (const dir of ["reports", "reports/html", "screenshots", "reports/test-output"]) {
    fs.mkdirSync(path.join(root, dir), { recursive: true });
  }
  const stamp = {
    startedAt: new Date().toISOString(),
    marketing: process.env.E2E_MARKETING_URL || "https://wash-pro-7f3b1.web.app",
    worker: process.env.E2E_WORKER_URL || "http://127.0.0.1:5174",
    admin: process.env.E2E_ADMIN_URL || "http://127.0.0.1:5173",
    customerWeb: process.env.E2E_CUSTOMER_WEB_URL || "https://wash-pro-customer.web.app",
    hasAdminCreds: Boolean(process.env.E2E_ADMIN_EMAIL && process.env.E2E_ADMIN_PASSWORD),
    hasWorkerCreds: Boolean(process.env.E2E_WORKER_EMAIL && process.env.E2E_WORKER_PASSWORD),
    hasFirebaseTestPhone: Boolean(process.env.E2E_TEST_PHONE && process.env.E2E_TEST_OTP),
  };
  fs.writeFileSync(path.join(root, "reports/run-meta.json"), JSON.stringify(stamp, null, 2));
}

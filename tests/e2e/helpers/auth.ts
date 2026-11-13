/** Auth helpers — never hardcode production OTPs. */

export function hasAdminCreds() {
  return Boolean(process.env.E2E_ADMIN_EMAIL && process.env.E2E_ADMIN_PASSWORD);
}

export function hasWorkerCreds() {
  return Boolean(process.env.E2E_WORKER_EMAIL && process.env.E2E_WORKER_PASSWORD);
}

export function hasFirebaseTestPhone() {
  return Boolean(process.env.E2E_TEST_PHONE && process.env.E2E_TEST_OTP);
}

export function adminCreds() {
  return {
    email: process.env.E2E_ADMIN_EMAIL!,
    password: process.env.E2E_ADMIN_PASSWORD!,
  };
}

export function workerCreds() {
  return {
    email: process.env.E2E_WORKER_EMAIL!,
    password: process.env.E2E_WORKER_PASSWORD!,
  };
}

export const skipReason = {
  noAdmin:
    "Set E2E_ADMIN_EMAIL / E2E_ADMIN_PASSWORD in tests/e2e/.env.test for live admin login tests.",
  noWorker:
    "Set E2E_WORKER_EMAIL / E2E_WORKER_PASSWORD in tests/e2e/.env.test for live worker login tests.",
  noPhone:
    "Set E2E_TEST_PHONE / E2E_TEST_OTP (Firebase Console test numbers only) for OTP tests.",
  flutterNative:
    "Customer booking/OTP flows live in Flutter native — out of Playwright browser scope.",
  razorpayHosted:
    "Razorpay-hosted checkout / bank OTP cannot be fully automated; use mocked + manual checklist.",
};

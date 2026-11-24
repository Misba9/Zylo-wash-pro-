#!/usr/bin/env node
/**
 * Source of truth: repo-root `.env`
 * Deploy/runtime source: `functions/.env` (loaded by Firebase Functions)
 *
 * Syncs RAZORPAY_* keys so the whole project uses one place to edit credentials.
 */
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const rootEnv = path.join(root, ".env");
const functionsEnv = path.join(root, "functions", ".env");

const KEYS = ["RAZORPAY_KEY_ID", "RAZORPAY_KEY_SECRET", "RAZORPAY_WEBHOOK_SECRET"];

function parseEnv(text) {
  const out = {};
  for (const line of text.split(/\r?\n/)) {
    const t = line.trim();
    if (!t || t.startsWith("#")) continue;
    const i = t.indexOf("=");
    if (i <= 0) continue;
    out[t.slice(0, i).trim()] = t.slice(i + 1).trim();
  }
  return out;
}

if (!fs.existsSync(rootEnv)) {
  console.error(`Missing ${rootEnv}. Copy .env.example → .env and set RAZORPAY_KEY_ID / RAZORPAY_KEY_SECRET.`);
  process.exit(1);
}

const src = parseEnv(fs.readFileSync(rootEnv, "utf8"));
if (!src.RAZORPAY_KEY_ID || !src.RAZORPAY_KEY_SECRET) {
  console.error("Root .env must set RAZORPAY_KEY_ID and RAZORPAY_KEY_SECRET.");
  process.exit(1);
}

const lines = [
  "# Auto-synced from repo-root .env by scripts/sync-razorpay-env.mjs",
  "# Do not edit by hand — change root .env, then re-run sync (or deploy).",
  `RAZORPAY_KEY_ID=${src.RAZORPAY_KEY_ID}`,
  `RAZORPAY_KEY_SECRET=${src.RAZORPAY_KEY_SECRET}`,
];
if (src.RAZORPAY_WEBHOOK_SECRET) {
  lines.push(`RAZORPAY_WEBHOOK_SECRET=${src.RAZORPAY_WEBHOOK_SECRET}`);
} else {
  lines.push("# RAZORPAY_WEBHOOK_SECRET=");
}
lines.push("");

fs.writeFileSync(functionsEnv, lines.join("\n"), "utf8");
console.log(`Synced ${KEYS.filter((k) => src[k]).join(", ")} → functions/.env`);

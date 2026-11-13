#!/usr/bin/env node
/**
 * Assembles hosting/unified for the primary zyloo.co.in Hosting site:
 *   /           → company website
 *   /field/     → ZYLO Field (worker PWA)
 *   /admin/     → ZYLO Control (admin dashboard)
 *   /app/       → coming-soon (no customer web SPA yet)
 */
import { cpSync, existsSync, mkdirSync, rmSync, writeFileSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const out = join(root, "hosting", "unified");

const websiteDist = join(root, "apps", "website", "dist");
const workerDist = join(root, "apps", "worker-pwa", "dist");
const adminDist = join(root, "apps", "admin-dashboard", "dist");
const appSoon = join(root, "hosting", "app-coming-soon");

for (const [label, path] of [
  ["website", websiteDist],
  ["worker", workerDist],
  ["admin", adminDist],
  ["app-coming-soon", appSoon],
]) {
  if (!existsSync(path)) {
    console.error(`Missing ${label} build at ${path}`);
    process.exit(1);
  }
}

rmSync(out, { recursive: true, force: true });
mkdirSync(out, { recursive: true });

cpSync(websiteDist, out, { recursive: true });
cpSync(workerDist, join(out, "field"), { recursive: true });
cpSync(adminDist, join(out, "admin"), { recursive: true });
cpSync(appSoon, join(out, "app"), { recursive: true });

writeFileSync(
  join(out, "404.html"),
  `<!doctype html><html lang="en"><head><meta charset="utf-8"/><meta name="viewport" content="width=device-width,initial-scale=1"/><title>ZYLO — Not found</title><meta http-equiv="refresh" content="0;url=/"/></head><body style="font-family:system-ui;padding:2rem"><p>Page not found. <a href="/">Return home</a>.</p></body></html>\n`,
);

console.log("Assembled unified hosting → hosting/unified");
console.log("  /        company website");
console.log("  /field/  ZYLO Field");
console.log("  /admin/  ZYLO Control");
console.log("  /app/    customer web coming soon");

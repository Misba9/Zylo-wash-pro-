import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

export default async function globalTeardown() {
  const root = path.dirname(fileURLToPath(import.meta.url));
  const metaPath = path.join(root, "reports/run-meta.json");
  if (fs.existsSync(metaPath)) {
    const meta = JSON.parse(fs.readFileSync(metaPath, "utf8"));
    meta.finishedAt = new Date().toISOString();
    fs.writeFileSync(metaPath, JSON.stringify(meta, null, 2));
  }
}

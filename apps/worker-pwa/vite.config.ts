import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import { fileURLToPath, URL } from "node:url";

/** Use ZYLO_BASE=/field/ for unified-domain builds; default `/` keeps legacy Hosting sites working. */
const base = process.env.ZYLO_BASE || "/";

export default defineConfig({
  base,
  plugins: [react()],
  server: { fs: { allow: [fileURLToPath(new URL("../..", import.meta.url))] } },
  resolve: {
    alias: {
      "@shared": fileURLToPath(new URL("../../packages/shared-types/src", import.meta.url)),
    },
  },
});

import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import { fileURLToPath, URL } from "node:url";
export default defineConfig({ plugins:[react()], server:{ fs:{ allow:[fileURLToPath(new URL("../..", import.meta.url))] } }, resolve:{ alias:{ "@shared": fileURLToPath(new URL("../../packages/shared-types/src", import.meta.url)) } } });

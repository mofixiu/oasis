import { defineConfig, loadEnv } from "vite";
import react from "@vitejs/plugin-react";
import { resolveOrigin } from "./site.config.mjs";
export default defineConfig(({ mode }) => {
  const env = loadEnv(mode, process.cwd(), "");
  const origin = resolveOrigin(env.SITE_URL || "https://landaos.vercel.app");
  return {
    plugins: [
      react(),
      {
        name: "landa-metadata",
        transformIndexHtml: (html: string) =>
          html.replaceAll("__SITE_URL__", origin),
      },
    ],
  };
});

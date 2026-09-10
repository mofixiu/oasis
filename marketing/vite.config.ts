import { defineConfig, loadEnv } from "vite";
import react from "@vitejs/plugin-react";
import { siteOrigin } from "./site.config.mjs";
export default defineConfig(({ command, mode }) => {
  const env = loadEnv(mode, process.cwd(), "");
  // The dev server never publishes its metadata, so it may run without a domain.
  const origin =
    command === "serve" && !env.SITE_URL && !env.VERCEL_PROJECT_PRODUCTION_URL
      ? "http://127.0.0.1:5173"
      : siteOrigin(env);
  return {
    plugins: [
      react(),
      {
        name: "oasis-metadata",
        transformIndexHtml: (html: string) =>
          html.replaceAll("__SITE_URL__", origin),
      },
    ],
  };
});

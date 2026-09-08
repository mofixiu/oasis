import { readFile, writeFile, rm } from "node:fs/promises";
import { loadEnv } from "vite";
import { render } from "../.prerender/entry-server.js";
import { resolveOrigin } from "../site.config.mjs";
const origin = resolveOrigin(
  loadEnv("production", process.cwd(), "").SITE_URL || "https://landaos.com",
);
const template = await readFile("dist/index.html", "utf8");
if (!template.includes('<div id="root"></div>'))
  throw new Error("Prerender root was not found.");
const markup = render();
if (!markup.includes("<h1>"))
  throw new Error("Prerender did not produce the marketing page.");
await writeFile(
  "dist/index.html",
  template.replace('<div id="root"></div>', `<div id="root">${markup}</div>`),
);
await writeFile(
  "dist/robots.txt",
  `User-agent: *\nAllow: /\nSitemap: ${origin}/sitemap.xml\n`,
);
await writeFile(
  "dist/sitemap.xml",
  `<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9"><url><loc>${origin}/</loc></url></urlset>\n`,
);
await rm(".prerender", { recursive: true, force: true });
console.log(`Prerendered complete HTML for ${origin}/`);

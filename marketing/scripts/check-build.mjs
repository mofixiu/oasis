import assert from "node:assert/strict";
import { readFile, readdir, stat } from "node:fs/promises";
const html = await readFile("dist/index.html", "utf8");
assert.match(
  html,
  /<div id="root">[\s\S]*<h1>/,
  "Page content must be present without JavaScript.",
);
for (const id of [
  "landlords",
  "product",
  "money-and-stays",
  "how-we-build",
  "trust",
  "faq",
  "waitlist",
])
  assert.ok(html.includes(`id="${id}"`), `Missing section ${id}`);
for (const tag of ["og:image", "og:url", "twitter:card", "twitter:image"])
  assert.ok(html.includes(`"${tag}"`), `Missing sharing metadata ${tag}`);
assert.match(html, /rel="canonical" href="https:\/\//);
assert.ok(!html.includes("__SITE_URL__"));
const phone = html.match(/<figure class="app-figure"[^>]*>([\s\S]*?)<\/figure>/)?.[1];
assert.ok(
  phone && !/<h[1-6]\b/.test(phone),
  "Product preview must not pollute heading navigation.",
);
const imgs = [...html.matchAll(/<img\b[^>]*>/g)].map((x) => x[0]);
for (const img of imgs) {
  assert.match(img, /\bwidth="\d+"/);
  assert.match(img, /\bheight="\d+"/);
  const src = img.match(/src="([^"]+)"/)?.[1];
  assert.ok(src?.endsWith(".webp"), "Content images must use WebP.");
  assert.ok((await stat(`dist${src}`)).size > 0);
}
assert.match(html, /fetchPriority="high"|fetchpriority="high"/);
const ids = new Set([...html.matchAll(/\bid="([^"]+)"/g)].map((x) => x[1]));
for (const match of html.matchAll(/href="#([^"]+)"/g))
  assert.ok(ids.has(match[1]), `Broken anchor ${match[1]}`);
const assets = await readdir("dist/assets");
const fonts = assets.filter((x) => /\.woff2?$/.test(x));
assert.equal(
  fonts.length,
  4,
  "Only four Latin WOFF2 font weights should ship.",
);
assert.ok(fonts.every((x) => x.includes("-latin-") && x.endsWith(".woff2")));
let imageBytes = 0;
for (const name of [
  "room-interior.webp",
  "short-stay.webp",
  "interior-thumb.webp",
])
  imageBytes += (await stat(`dist/images/${name}`)).size;
assert.ok(imageBytes < 150000, `Content image budget exceeded: ${imageBytes}`);
assert.ok((await stat("dist/og.jpg")).size > 0);
for (const name of ["robots.txt", "sitemap.xml"])
  assert.ok((await readFile(`dist/${name}`, "utf8")).includes("https://"));
assert.ok(
  !html.includes("/images/room_interior.png") &&
    !html.includes("/images/quality_hero.png"),
);
console.log(
  `Build checks passed: static content, metadata, anchors, image dimensions, ${fonts.length} Latin WOFF2 files, ${(imageBytes / 1024).toFixed(1)} KiB of content images.`,
);

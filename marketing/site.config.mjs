// The site's real public origin, and the fallback when SITE_URL is unset.
//
// This default is not cosmetic: it is baked into the canonical link, the OG
// and Twitter URLs, robots.txt and the sitemap at build time. It shipped once
// as "https://landaos.com" — a domain Landa does not own, belonging to an
// unrelated musician — which meant the live site was telling search engines
// that the authoritative copy of every page lived on a stranger's website,
// and every share card resolved there too.
//
// Change it only alongside an actual domain move, and check the built
// dist/index.html, robots.txt and sitemap.xml afterwards.
export function resolveOrigin(value = "https://landaos.vercel.app") {
  const url = new URL(value);
  if (
    url.protocol !== "https:" ||
    url.username ||
    url.password ||
    url.pathname !== "/" ||
    url.search ||
    url.hash
  ) {
    throw new Error(
      "SITE_URL must be an HTTPS origin without a path, credentials, query or fragment.",
    );
  }
  return url.origin;
}

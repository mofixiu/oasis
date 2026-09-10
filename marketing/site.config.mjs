// The site's public origin, baked into the canonical link, the OG and Twitter
// URLs, robots.txt and the sitemap at build time.
//
// There is deliberately no hardcoded fallback domain. One shipped once
// pointing at a domain the project did not own — belonging to an unrelated
// musician — which meant the live site was telling search engines that the
// authoritative copy of every page lived on a stranger's website, and every
// share card resolved there too.
//
// So the origin is SITE_URL when set, and otherwise the production domain
// Vercel assigns the project, which follows it through renames and custom
// domains. A build with neither fails rather than guess. After a domain move,
// check the built dist/index.html, robots.txt and sitemap.xml.
export function siteOrigin(env) {
  const value =
    env.SITE_URL ||
    (env.VERCEL_PROJECT_PRODUCTION_URL &&
      `https://${env.VERCEL_PROJECT_PRODUCTION_URL}`);
  if (!value) {
    throw new Error(
      "Set SITE_URL (for example in .env.local) to the site's public HTTPS origin.",
    );
  }
  return resolveOrigin(value);
}

export function resolveOrigin(value) {
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

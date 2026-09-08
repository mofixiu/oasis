export function resolveOrigin(value = "https://landaos.com") {
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

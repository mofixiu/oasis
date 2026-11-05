# Oasis Backend Change Specification — v19: Host Brand Name and Listing Photos

> **Audience:** Backend and Flutter developers working on the short-stay app.
>
> **Date:** 2026-11-05
>
> **Status:** Proposed. The Flutter app already sends `brand_name` and already falls back to unit photos. Nothing breaks before the backend changes; the brand name is just not saved.

## 1. Optional host brand name

Host sign-up now has an optional **Brand name** field (for example "Lekki Luxe Stays"). Hosts can leave it empty.

### 1.1 Register

`POST /api/users/register/` may include:

```json
{
  "email": "host@example.com",
  "password": "…",
  "phone": "+2348012345678",
  "role": "OWNER",
  "brand_name": "Lekki Luxe Stays"
}
```

- Only sent for `role: "OWNER"`, and only when the host typed something. A missing key means no brand.
- Must stay optional. Do not reject a host sign-up without it.
- Suggested limits: trimmed, up to 80 characters. Return `400` with a field error if longer.

### 1.2 Profile

Return `brand_name` on `GET /api/users/profile/` (empty string or `null` when unset). Accept it on `PATCH /api/users/profile/` so a host can add or change it later.

### 1.3 Later: show it to guests

When the backend stores it, include the host's `brand_name` on short-let listing payloads (for example `host_brand_name`). The app can then show "Hosted by Lekki Luxe Stays" on the listing page.

## 2. Listing photos on guest payloads

A host reported that photos uploaded from the host side do not appear for guests.

The app reads guest photos from the listing payload in this order: listing `photo_urls`, then `unit.photo_urls`, then property `photo_urls`. Before this change, a listing-level `"photo_urls": []` stopped the app from looking further. The app now skips empty lists, so unit photos show even if the listing-level field is empty.

Please also check the server side:

- `GET /api/users/tenant/short-lets/` should return the unit's photos in `photo_urls` (and `cover_photo_url`) for every listing, the same as `GET /api/users/landlord/short-lets/` does.
- The list must reflect uploads to `POST /api/users/units/{unit_id}/photos/` straight away, with no caching that keeps the old empty list.

If the tenant list already returns the photos, the app change above is enough.

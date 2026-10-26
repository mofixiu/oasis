# Oasis Backend Change Specification — v18: Richer Shortlet Listings

> **Audience:** Backend and Flutter developers working on the short-stay app.
>
> **Date:** 2026-10-26
>
> **Status:** Proposed. The Flutter app already collects and sends every field below on listing create and edit. Until the backend stores them, they are ignored and lost on save; nothing else breaks.

## Summary

The host's list-a-place flow is now a full-screen, step-by-step flow that asks more about each place. The new answers need to be stored on the short-let listing, returned to hosts and guests, and filterable in guest search.

| Field | Type | Required on create | Notes |
| --- | --- | --- | --- |
| `property_type` | enum string | Yes (app-enforced) | See §1.1 |
| `amenities` | array of enum strings | At least one (app-enforced) | See §1.2 |
| `best_for` | array of enum strings | At least one (app-enforced) | See §1.3 |
| `check_in_time` | `"HH:MM"` | No, default `"14:00"` | Local time at the listing |
| `check_out_time` | `"HH:MM"` | No, default `"12:00"` | Local time at the listing |
| `smoking_allowed` | boolean | No, default `false` | |
| `pets_allowed` | boolean | No, default `false` | |
| `parties_allowed` | boolean | No, default `false` | The app sets this whenever `best_for` includes `PARTY` |

The app also now requires at least 3 unit photos and a unit tour video before a new listing is published. Both use the existing unit-media routes (`/units/{unit_id}/photos/`, `/units/{unit_id}/video/`) and are uploaded right after the listing is created.

## 1. Accept and store the new fields

Accept the fields on all three write paths, as top-level keys alongside the existing listing fields:

- `POST /api/users/host/listings/` (new place, property, unit and listing in one request)
- `POST /api/users/landlord/short-lets/` (list an existing unit)
- `PATCH /api/users/landlord/short-lets/{listing_id}/` (edit)

On `PATCH`, an omitted key leaves the stored value unchanged; a key sent as `[]` clears the list.

Reject unknown enum values with `400` and a field error, for example:

```json
{ "amenities": ["\"JACUZZI\" is not a valid choice."] }
```

### 1.1 `property_type`

`APARTMENT`, `STUDIO`, `SERVICED_APARTMENT`, `PENTHOUSE`, `DUPLEX`, `TERRACE`, `HOUSE`, `ROOM`

### 1.2 `amenities`

`WIFI`, `POWER_24H`, `AIR_CONDITIONING`, `KITCHEN`, `PARKING`, `SECURITY`, `HOT_WATER`, `SMART_TV`, `WORKSPACE`, `WASHING_MACHINE`, `POOL`, `GYM`, `BALCONY`, `GAMING`, `SOUND_SYSTEM`

### 1.3 `best_for`

`STAYCATION`, `BIRTHDAY`, `BAECATION`, `PARTY`, `WEEKEND_GETAWAY`, `WORK_TRIP`, `FAMILY`, `FRIENDS_TRIP`, `PHOTOSHOOT`, `WEDDING`, `HOLIDAY`, `LONG_STAY`, `STOPOVER`

Example create body (existing-unit path):

```json
{
  "unit": "UNIT_UUID",
  "nightly_price": "65000.00",
  "minimum_nights": 1,
  "maximum_guests": 4,
  "description": "Two-bedroom flat with a rooftop view…",
  "property_type": "APARTMENT",
  "amenities": ["WIFI", "POWER_24H", "AIR_CONDITIONING", "PARKING"],
  "best_for": ["STAYCATION", "BIRTHDAY", "BAECATION"],
  "check_in_time": "14:00",
  "check_out_time": "12:00",
  "smoking_allowed": false,
  "pets_allowed": false,
  "parties_allowed": false
}
```

## 2. Return the fields

Include all eight fields on every short-let listing payload: host listing list and detail, guest browse/search results, guest listing detail, and the listing embedded in a booking. Send defaults rather than omitting keys for listings created before this change (`property_type: null`, empty arrays, `"14:00"` / `"12:00"`, `false`).

Times may be returned as `"HH:MM"` or `"HH:MM:SS"`; the app reads both.

## 3. Guest search filters

Add to `GET /api/users/tenant/short-lets/`:

| Query param | Example | Behaviour |
| --- | --- | --- |
| `best_for` | `best_for=BIRTHDAY` | Listings whose `best_for` contains the value. Comma-separated values match any. |
| `property_type` | `property_type=STUDIO,APARTMENT` | Listings of any of the given types |
| `amenities` | `amenities=WIFI,POOL` | Listings that have **all** the given amenities |
| `parties_allowed` | `parties_allowed=true` | Exact match |
| `pets_allowed` | `pets_allowed=true` | Exact match |

The guest home screen now shows all 13 occasions as tiles. Today they open the general search; once `best_for` filtering exists, each tile will open search pre-filtered to its occasion.

## 4. Media requirements (optional server check)

The app blocks publishing a new listing without at least 3 unit photos and a tour video, but the uploads happen after the listing is created. If the backend wants to enforce this too, prefer a read-only flag over refusing the create, for example `media_complete: true|false` on the host listing payload. Hosts with incomplete media then see a reminder rather than a failed listing.

## 5. Acceptance

- Each of the three write paths stores the new fields, and `PATCH` with a subset changes only those keys.
- All listing payloads return the eight fields with the defaults above for older listings.
- The search filters in §3 work alone and combined with the existing filters.
- Invalid enum values return `400` with a field-level error.

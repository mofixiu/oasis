# Landa OS Backend Change Specification — v12

> **Audience:** Backend developer implementing on the Django API (`landa_os`, `users` app).
>
> **Companion documents:** `flutter_api_guide (17).md` (received 2026-09-03) is the current source of truth. `backend_change_spec_v11.md` (realtime socket, stay descriptions, bedrooms filter) is still open and nothing here supersedes it.
>
> **Date:** 2026-09-05
>
> **Status:** One blocking item. The app now lets a landlord change what a unit costs, and the endpoint it needs — `PATCH /units/{unit_id}/` — does not exist. Until it does, the feature is on screen and refuses to save. Everything else in this document is either already working or a correctness note.

---

## Priority

| §   | Change                                                        | Blocking?                              |
| --- | ------------------------------------------------------------- | -------------------------------------- |
| 1   | `PATCH /units/{unit_id}/` to change a unit's rent              | **Yes** — feature cannot save at all   |
| 2   | Re-pricing a short let must not disturb its bookings           | No — confirm the existing behaviour    |
| 3   | Rent changes must not reach a signed tenancy                   | No — confirm; it is a correctness risk |
| 4   | Tell the marketplace a price moved                             | No — quality of life                   |
| 5   | A price history worth keeping                                  | No — read it and decide                |

---

## Why this exists at all

A price is the only thing on a listing a landlord changes because the *world* changed rather than because they got it wrong. Everything else on a unit — the number, the room count, the photos — is right or wrong from the day it is typed. The rent is a position in a market.

Until now the app had no answer to that. A rent was set once, in the units sheet, during the add-property flow, and was then fixed for ever. A landlord who mispriced a flat, or who wanted to drop it ₦200,000 to fill a two-month vacancy, had exactly one option inside Landa: delete the unit and add it again — which throws away its photos, its walkthrough, its artisan recommendations and any applications against it.

The observable consequence is a listing that sits at a stale price until the landlord gives up on the app and lets the flat through an agent instead. That is the growth argument for this change, and it is the reason §1 is worth doing before the rest of v11.

Short lets were already better off: `POST /landlord/short-lets/` keys on the unit and treats a second post as an edit, so a nightly price has always been changeable. §2 only asks you to confirm what that does to bookings that already exist.

---

## 1. `PATCH /units/{unit_id}/` — change a unit's rent

### What the app now sends

```text
PATCH /api/users/units/{unit_id}/
Content-Type: application/json
Authorization: Bearer <access token>

{ "rent_amount": "3000000.00" }
```

That is the whole body. **Rent and nothing else** — deliberately, and please enforce it rather than accepting a general-purpose unit update. A unit's number and room count are what a tenant matched against when they applied; a PATCH that can quietly rewrite them is a category of bug worth making impossible rather than careful.

`rent_amount` is a **year's** rent as a decimal string, exactly as `POST /properties/{id}/units/` takes it. The app converts a monthly quote before it gets here (₦250,000/month → `"3000000.00"`) and shows the landlord the multiplication before they save, because Landa stores one number per unit.

### Expected response

`200 OK` with the updated unit, serialized exactly as `GET /properties/{id}/units/` serializes it:

```json
{
  "id": "UNIT_UUID",
  "unit_number": "A1",
  "bedrooms": 2,
  "bathrooms": 1,
  "rent_amount": "3000000.00",
  "is_occupied": false,
  "photo_urls": ["…"],
  "cover_photo_url": "…",
  "video_url": "…",
  "created_at": "2026-01-04T10:00:00Z"
}
```

The app writes the returned unit straight into the row it patched, so a response that omits `photo_urls` or `video_url` blanks a unit's media on screen until the next full refresh. If returning the full unit is awkward, returning `{"detail": "ok"}` is safer than returning a partial unit — the app ignores a response with no `id` and falls back to refetching the property.

### Permissions

* `OWNER` only, and only the owner of the property the unit belongs to.
* Verified only, like every other product endpoint.
* A landlord patching somebody else's unit is `403`, not `404`. Enumeration is not a concern here — the id is a UUID and they had to have it already.

### Validation worth having

* `rent_amount` must parse as a positive decimal. A blank or zero rent should be `400`, not a free flat.
* If there is a platform floor or ceiling on rent, enforce it and say so in `errors.rent_amount` — the app surfaces the field-level message verbatim, so `{"errors": {"rent_amount": ["Rent cannot be lower than ₦50,000."]}}` reaches the landlord as written.

### Until it ships

The app calls this today. A deployment without the route answers `404 {"detail": "Not found."}`, and one that has the route but refuses the verb answers `405 {"detail": "Method \"PATCH\" not allowed."}`.

Shown as written, both of those read to a landlord as *their flat has vanished*. So the app catches exactly those two status codes on this call and replaces the message with:

> This server cannot change a rent yet. Your unit is unchanged — nothing was lost. Try again once the update has shipped.

Every other rejection is passed through as the backend sent it. That translation is narrow and self-deleting: the day this endpoint answers `200`, the branch stops running.

---

## 2. Re-pricing a short let: confirm what happens to existing bookings

No change requested. This is a confirmation, because the app now makes it easy enough to do that it will start happening several times a week per host.

The short-let listing screen has a price-only editor alongside the full one. It posts to the existing endpoint with the price changed and **every other field carried through unchanged**:

```text
POST /api/users/landlord/short-lets/

{
  "unit": "UNIT_UUID",
  "nightly_price": "42000.00",
  "caution_fee": "25000.00",
  "minimum_nights": 2,
  "maximum_guests": 4,
  "description": "…",
  "cancellation_policy": "MODERATE",
  "available_from": "2026-09-01",
  "available_to": "2026-12-31",
  "blocked_dates": ["2026-10-10"],
  "house_rules": "…",
  "check_in_notes": "…",
  "is_active": true
}
```

The full body is sent because the endpoint replaces the listing — an omitted key is a house rule deleted and a calendar wiped, which is not an acceptable side effect of changing one number.

**Please confirm all three of these hold:**

1. A booking that is **already paid** keeps the price it was paid at. The money has moved and is in escrow; the amount is a fact about a transaction, not a lookup against the listing.
2. A booking that is **approved and awaiting payment** keeps the price it was approved at. The guest has a 24-hour window and was quoted a number; re-pricing under them inside that window would be a bait-and-switch, and it is the case most likely to be got wrong because the payment has not happened yet.
3. A booking still **pending a decision** — where nothing has been agreed — may be re-priced or may keep its quote, but whichever it is, say which. If it re-prices, the guest must be told; a request that comes back approved at a different number than it was made at needs a notification, not silence.

If any of the three currently reads the live listing at payment time, that is a bug, and it is a bigger one than anything else in this document.

---

## 3. A rent change must not reach a signed tenancy

Same shape of question for the yearly side, and the stakes are higher because a tenancy is a year long and a contract.

A `TenancyAgreement` carries its own `rent_amount`, agreed and signed by both parties. `PATCH /units/{id}/` changes what the **unit** is advertised at. Those two must not be the same number:

* an executed agreement keeps the rent on the agreement, for its whole term;
* the rent schedule and every payment derived from it keep using the agreement's figure;
* an agreement that has been sent but not yet signed keeps the figure it was sent with — the tenant is looking at a document, and a document that changes while they read it is not one anybody should sign.

The app states this to the landlord on the editing sheet, in both directions:

> **Occupied** — *"Someone is living here. Their signed agreement keeps the rent they agreed to — this only changes what the unit is advertised at once it is free again."*
>
> **Vacant** — *"This takes effect on the listing straight away. Applications already sent keep the rent they were made at."*

Two things follow from that second sentence. Please confirm a **pending application** keeps the rent it was made at, and that approving it produces an agreement at that figure rather than at the unit's current one. An applicant who applied at ₦1.2M and is approved at ₦1.5M has been quoted a price that was never offered to them.

If the backend currently reads the unit's live `rent_amount` when it drafts an agreement, that is the change to make here: snapshot the rent onto the application when it is created.

---

## 4. Tell the marketplace a price moved

Quality of life, and it composes with v11 §1.

When a unit's rent changes, or a short-let listing's nightly price does, the tenants with a live interest in it have a reason to hear about it — most obviously a **price drop** on a unit somebody has applied for or has saved. Two candidate notification types:

* `UNIT_PRICE_CHANGED` — payload `{"unit_id": …, "property_id": …, "old_rent": "…", "new_rent": "…"}`
* `SHORT_LET_PRICE_CHANGED` — payload `{"listing_id": …, "unit_id": …, "old_price": "…", "new_price": "…"}`

The app renders unknown notification types with sensible defaults already, so these can ship server-first without an app release; it will show them in the list and raise an in-app popup for them the moment they exist.

Worth being conservative about who receives one: a price *rise* is not news anybody wants pushed at them, and a listing nobody has engaged with has no audience. Applicants and prior enquirers on a price drop is the whole useful set.

---

## 5. A price history worth keeping

Read this and decide; the app asks for nothing.

Landa's proposition is that a rental is auditable — that is what the escrow, the agreements and the verification are all for. A rent that can be silently rewritten is a small hole in that. If a landlord raises a unit's rent between an application being made and it being approved, and §3 is implemented correctly, nothing bad happens to the tenant — but there is also no record that it happened.

A small append-only row on each change (`unit`, `changed_by`, `old_rent`, `new_rent`, `changed_at`) costs almost nothing and answers a dispute in one query. The same applies to short-let nightly prices, which will change far more often.

Not required, and the app will not read it. It is the kind of thing that is cheap now and impossible to reconstruct later.

---

## Summary of what the app sends today

| Call | Change |
| --- | --- |
| `PATCH /units/{unit_id}/` | **New, and the blocking item.** Body is exactly `{"rent_amount": "<annual decimal>"}`. `OWNER`, verified, owner of the property. Returns the full unit, or `{"detail": "ok"}`. |
| `POST /landlord/short-lets/` | Unchanged shape. Now called from a price-only editor as well as the full one, so it will be hit more often and always with the complete body. |

## Still open from earlier specs

Nothing here closes anything. `backend_change_spec_v11.md` is untouched and its §1 (the realtime WebSocket) is still the largest outstanding item; §1 of this document is smaller and unblocks a feature that is already on screen, so it is the one to take first if both cannot be done at once.

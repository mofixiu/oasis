# Landa OS Backend Change Specification — v14

> **Audience:** Backend developer implementing on the Django API (`landa_os`, `users` app).
>
> **Companion document:** `flutter_api_guide (18).md`. This document is written against it.
>
> **Date:** 2026-09-07
>
> **Origin:** A round of Android testing on the build shared with external testers, plus one item from the product team. This is not a wishlist — every item below is something somebody actually hit. Most of the report was fixed in the app and needs nothing from the backend; those are listed first so nobody implements them twice. What is left is six things the app cannot fix on its own.

---

## Fixed in the app — no backend change needed

Recorded so this document is read as six asks rather than thirteen.

| Tester report | Cause | Fixed by |
| --- | --- | --- |
| "Auto comma on the numbers" | Every amount was an ungrouped digit field | `LandaThousandsFormatter` on all thirteen money inputs. Display only; the wire still gets `"450000.00"` |
| "The map pin should fill in the state and address" | The reverse geocode produced a label and nothing else | `GeocodeAddress` — the pin now fills street, city and state, and never overwrites something typed |
| "Remove Lagos as placeholder text" | The state box was prefilled `Lagos` | Both location boxes start empty and are filled from the pin |
| "A dropdown / bottom sheet for cities and states" | Both were free text | `NigeriaLocations` (37 states, ~200 towns) behind a searchable sheet, on the add-property form and the marketplace filter. **See §4 — the backend half of this is not optional** |
| "Error when listing the unit (it showed an error but it still listed)" | The save and the list refresh after it shared one `try`; a failed `GET` turned a successful `POST` into "could not save" | The refresh is outside the save. `POST /landlord/short-lets/` behaved correctly throughout |
| "I have to refresh everything to see" | The bottom bar is an `IndexedStack`, so switching tabs mounts nothing, pops no route, and re-read nothing | `LandaTabVisibility`: becoming the visible tab now refreshes, and a tab nobody has opened defers its first fetch |
| "Remove this tour videos come next" | An explainer panel about the video moving onto units, sitting above a footer that already said what came next | Deleted |
| "They can't see any picture in it" — *partly* | A refresh through `GET /properties/` was overwriting a freshly created property's photos with a payload that does not carry them | `PropertyModel.withMediaFrom` / `UnitModel.withMediaFrom`: a refresh may **add** media and may never remove it. **See §5 — the rest of this one is backend** |
| "Forgot password is a waste of space" | Two full pushed screens, each a centred card with its own app bar and Back button | One staged bottom sheet over sign-in (`password_reset_sheet.dart`); both screens deleted |

The last one is worth a line for the backend too: request volume at cold start **drops**. Four tabs used to fire their opening fetches on the first frame; now one does, and the other three fetch when they are opened.

---

## 1. Nothing stops a tenant moving into a yearly property without paying

> *"I was able to enter the yearly property without paying the first rent."*

This is the serious one. Escrowed rent is the product's whole premise, and the tenancy lifecycle currently never asks about money.

### What happens today

Per guide 18:

1. `POST /landlord/applications/{id}/approve/` — "the application becomes `APPROVED`, the agreement becomes `PENDING`, **the unit becomes occupied**, other pending applications for that unit are rejected" (§Tenant Marketplace And Applications).
2. `POST /agreements/{id}/sign/` (tenant), then the same again (landlord) — "Agreement status becomes `EXECUTED`. `pay_rent_unlocked` becomes `true`" (§5.21).

Neither step checks whether a naira has moved. So the sequence a tester ran is:

```text
apply → approved  → unit.is_occupied = true      (no payment)
      → sign ×2   → agreement.status = EXECUTED  (no payment)
      → done. The flat is theirs on every screen, and the rent is "due".
```

`pay_rent_unlocked` is the *permission to pay*, not evidence of payment. There is no field anywhere on the agreement that means "this tenancy has actually started".

### Why the app cannot fix this

The app can stop *claiming* the tenancy is live, and now does: an executed agreement whose `rent_payment.status` is `DUE` or `FAILED` with no instalments paid renders as **"Your tenancy has not started yet"**, the unit chip goes from sage to sand, and the landlord's unit sheet reads `Reserved · first rent not paid` instead of `Occupied`.

But that is presentation. The backend is the only place that can stop the state from existing, and everything downstream of occupancy — marketplace availability, other applicants' rejections, the landlord's payout expectations — is computed server-side from `is_occupied` and `status`.

### What is needed

**A. An agreement is not `EXECUTED` until the first rent is in escrow.**

Add a state between the second signature and a running tenancy. Suggested:

| Status | Meaning |
| --- | --- |
| `PENDING` | awaiting one or both signatures (unchanged) |
| `AWAITING_FIRST_RENT` | both signatures in, first payment not yet in escrow |
| `EXECUTED` | first payment reached `ESCROW`; the tenancy is running |

`pay_rent_unlocked` becomes `true` on entering `AWAITING_FIRST_RENT` — the tenant must be able to pay, that is the point of the state.

If a new status value is too disruptive, the minimum viable alternative is a boolean on the agreement:

```json
{ "status": "EXECUTED", "is_active": false, "first_rent_settled": false }
```

Either shape works for the app. A new status is cleaner; a flag is faster. **Do not** leave it derivable only from `rent_payment` — that block is documented as optional, and a rule this important should not depend on an optional field.

**B. Occupancy follows the money, not the approval.**

`unit.is_occupied` should become `true` when the first rent reaches escrow, not when the application is approved. Between approval and payment the unit is *reserved*: not bookable, not in the marketplace, and not yet occupied. Suggested:

```json
{ "id": "...", "unit_number": "A1", "is_occupied": false, "availability": "RESERVED" }
```

with `availability` in `AVAILABLE | RESERVED | OCCUPIED`. The marketplace's existing exclusion rule (§Tenant Marketplace And Applications) already keeps a unit with a `PENDING` agreement out of the listings, so `RESERVED` does not need new filtering — it needs to be *sayable*, so both parties can see which of the two states a flat is in.

**C. A reservation has to expire.**

Approval currently rejects every other applicant for the unit. If the winner then never pays, the flat is dead: the other applicants are gone and the unit is out of the marketplace indefinitely. Please add a window — 48 or 72 hours from execution is the obvious span, and it mirrors the 24-hour short-let payment window that already exists — after which the agreement is `VOIDED`, the unit returns to `AVAILABLE`, and both parties are notified.

Two new notification types for it:

| Type | Sent to | When |
| --- | --- | --- |
| `FIRST_RENT_REMINDER` | tenant | the window is half gone |
| `TENANCY_LAPSED` | both | the window closed unpaid |

**D. Say so in the agreement payload.**

Whichever shape A takes, the app needs the deadline to show a countdown:

```json
{
  "status": "AWAITING_FIRST_RENT",
  "first_rent_due_by": "2026-09-09T09:40:00Z",
  "first_rent_settled": false,
  "pay_rent_unlocked": true
}
```

### Migration

Existing `EXECUTED` agreements with no payment against them are the awkward case, and there are two kinds. A tenancy the landlord *imported* (rent collected off-platform, `rent_payment.status = NOT_DUE`) is genuinely running and must stay `EXECUTED` — the app already treats `NOT_DUE` as settled for exactly this reason. A tenancy created through apply-approve-sign with rent `DUE` and nothing paid is the bug, and moving it to the new state is correct. Please do not migrate on "has no payment rows" alone.

---

## 2. There are no push notifications

> *"no notifications"*

Testers meant device notifications. There are none, and there is no backend surface for them: `flutter_api_guide (18).md` contains no mention of FCM, APNs, a device token, or a push payload, and the app registers no messaging plugin.

### What exists today

In-app only, and all three of these work:

* `GET /notifications/` — the bell, and the list behind it.
* `/ws/realtime/` — `notification.created` raises an in-app banner while the app is **open and foregrounded**.
* A 45-second REST fallback poll for when the socket is down, also only while foregrounded.

The socket is closed the moment the app is backgrounded — deliberately; the OS freezes it anyway and one held across a suspension wakes up believing it is connected while delivering nothing. So today: **close the app and nothing reaches you.** For a product whose whole job is telling a landlord that somebody applied and a tenant that rent is due, that is the gap testers named.

### What is needed

**A. Device registration.**

```text
POST /api/users/devices/
{
  "token": "FCM_REGISTRATION_TOKEN",
  "platform": "ANDROID",          // ANDROID | IOS
  "app_version": "1.0.0+1"
}
→ 201 { "id": "...", "token": "...", "platform": "ANDROID", "created_at": "..." }
```

* Idempotent on `token`: re-posting the same token returns `200` with the existing row. Tokens are re-issued by FCM on reinstall, app data clear and roughly every few months, so the app will post on every launch.
* Bound to the authenticated user. One user may hold several (phone + tablet); one token must only ever belong to one user, so a token arriving for a different user **moves** to that user rather than duplicating — this is what stops the previous signed-in account's notifications reaching whoever signs in next on a shared phone.

```text
DELETE /api/users/devices/{id}/     — or —
DELETE /api/users/devices/?token=…
```

Called on sign-out. **This one matters for privacy**: without it, "rent is due for Unit A1" keeps arriving on a phone whose owner signed out weeks ago.

**B. Send a push alongside every notification that is already created.**

No new taxonomy: the `notification_type` values in guide 18 are already the right list. When a `Notification` row is written, fan out to that user's device tokens with the same content.

```json
{
  "notification": {
    "title": "Rent is due",
    "body": "₦472,500 is due on Sunset House · A1."
  },
  "data": {
    "notification_id": "d4067ff3-…",
    "notification_type": "RENT_DUE",
    "deep_link": "landa://agreements/69be1df4-…"
  }
}
```

The `data` block is what makes a tap useful — the app routes on `notification_type` today and would route on `deep_link`. Please send both: `data` alone (a silent push) is unreliable on Android once the app is force-stopped, and `notification` alone gives the app nothing to route with.

**C. Honour the preferences that already exist.**

`GET/PATCH /notification-preferences/` currently governs the optional early rent reminder **emails**. Push needs the same switch, and the natural shape is one more field:

```json
{
  "early_rent_reminder_emails_enabled": true,
  "push_enabled": true
}
```

**D. Do not push what the user is already looking at.**

If a push and an open WebSocket both deliver, the user gets a banner from the app and a notification from the OS for one event. The app can suppress its own banner, but only if the two are distinguishable. Either skip the push when the user has a live socket, or include `"suppress_if_foreground": true` in `data` — either is fine, but pick one and document it.

### App-side work this unblocks

`firebase_messaging` + `flutter_local_notifications`, a `google-services.json`, the `POST /devices/` call on sign-in and the `DELETE` on sign-out, and routing a tap through the existing `landaNavigatorKey`. It is a day's work and none of it can start before the endpoint exists.

---

## 3. A landlord cannot message the tenant of a unit

> *"i also cant message individual units (landlord)"*

### Why

Guide 18, §Messaging: *"Landlord should send `application` or `agreement`, because a unit can have multiple applicants."* That is right, and the app now complies — the unit sheet's **Message tenant** button hangs off the tenancy's agreement id.

The cost is that the property screen has to hold **every one of the landlord's agreements** in memory and scan them for one whose `unit` matches, just to decide whether to draw a button. A landlord with forty units pays for forty agreements on a screen showing one flat.

### What is needed — either one, not both

**A (preferred).** Put the live tenancy on the unit payload. `GET /properties/{id}/units/` and `GET /units/{id}/` gain:

```json
{
  "id": "c82c03a7-…",
  "unit_number": "A1",
  "is_occupied": true,
  "tenant": { "id": "…", "full_name": "Ada Okafor" },
  "active_agreement": {
    "id": "69be1df4-…",
    "status": "EXECUTED",
    "conversation_id": "…"      // null when no thread has been opened
  }
}
```

This is a small addition and it removes a whole cross-feature dependency from the client. `conversation_id` is a bonus, not a requirement.

**B.** Accept `unit` from a landlord when it is unambiguous — the unit has exactly one live tenancy or exactly one approved application. Resolve to that; return the existing `TENANT_NOT_IDENTIFIED` when there is genuinely more than one candidate. The error already exists in the guide, which suggests this was the intent.

A is better. B is smaller.

---

## 4. `city` and `state` are matched as raw strings

The tenant marketplace filters on `?city=` and `?state=` (guide 18, §`GET /tenant/marketplace/`), matched against whatever the landlord typed into the property form. Both were free-text boxes, so the corpus contains `Lagos`, `lagos`, `Lagos State`, `LAGOS`, `Ikeja`, `FCT`, `Abuja`, `Federal Capital Territory` — and a tenant filtering for one of those finds none of the others. It fails silently: an empty result reads as "nothing available", not as "your spelling missed".

### What the app has done

Both fields are now pickers over one canonical list (`NigeriaLocations`): 37 states in one spelling each, with the FCT normalised to `Abuja (FCT)` however the geocoder or the user spells it, and towns scoped to their state. **New** properties and **new** searches will agree with each other from this build on.

### What is still needed

**A. Match case-insensitively.** `?state=lagos` and `?state=Lagos` are the same query. `icontains` or a normalised column — either.

**B. Normalise on write.** `POST /properties/` and `PATCH /properties/{id}/` should canonicalise `state` server-side against the same 37, so a property created by any other client (or by an admin, or by the existing corpus) lands in the same vocabulary. `Lagos State` → `Lagos`; `FCT` / `Federal Capital Territory` / `Abuja` → one value, and please tell us which one you pick so the app's list matches it exactly.

**C. Backfill.** Existing property rows carry the old spellings and will stay invisible to filtered searches until they are normalised. A one-off migration over `city` and `state` is the whole job.

**D. Consider exposing the list.** `GET /locations/states/` returning the canonical names, and their towns, would let the app stop shipping the list at all — and would mean a state added or renamed server-side does not need an app release. Nice to have, not a blocker; the client list works today.

---

## 5. A tenant cannot see photos of the flat they are applying for

> *"they can see the property but they cant see any picture in it, just seeing that its live too"*

Two separate gaps produce this, and only the first is fixed.

### A. `GET /properties/` describes a property more thinly than `POST /properties/` does — *fixed in the app, but please close it anyway*

Guide 18 §5.12, the create response:

```json
{ "photo_urls": ["…front.jpg", "…living-room.jpg"],
  "cover_photo_url": "…front.jpg",
  "photo_count": 2, "needs_photos": false, "video_url": "…tour.mp4" }
```

Guide 18 §5.11, the list the landlord's portfolio is rebuilt from on **every**
refresh:

```json
{ "photo_urls": [], "verification_status": "PENDING_REVIEW", "unit_count": 2 }
```

No `cover_photo_url`, no `photo_count`, no `needs_photos`, no `video_url`.

So a landlord added a property with four photos, saw them on the card that the
create response built, and then watched it go blank the next time the list was
re-read — with the property still showing as live, which is the second half of
what the tester described. This got **more** visible in this build, because
tabs now refresh when you switch to them; before, the list was often never
re-read at all.

The app now merges rather than replaces: a refresh may add media and may never
remove it. That is a workaround for a payload inconsistency, and it should not
have to exist. **Please make `GET /properties/` return the same media fields as
`POST /properties/`.** The same goes for `GET /properties/{id}/`, which the
property detail screen re-reads.

### B. The marketplace does not expose unit media to tenants — *not fixable in the app*

This is the real one. Guide 18, §`GET /tenant/marketplace/`, `available_units`:

```json
{ "id": "UNIT_UUID", "unit_number": "A1", "bedrooms": 2, "bathrooms": 2,
  "rent_amount": "300000.00", "photo_count": 0, "needs_photos": true }
```

`photo_count` and `needs_photos` — a count of pictures, and no pictures. There
is no `photo_urls`, no `cover_photo_url` and no `video_url` on a marketplace
unit, and the only place they exist is:

```text
GET /api/users/units/{unit_id}/photos/
```

which guide 18 states plainly: *"All unit media endpoints require an
authenticated verified `OWNER`. The unit must belong to a property owned by
that user."* A tenant asking for them gets a 403.

So a tenant browsing yearly rentals sees the building's photos and **nothing of
the flat**, on a screen that exists to decide whether to apply for that flat.
The app is already built for the data — `UnitModel` parses `photo_urls`,
`cover_photo_url` and `video_url`, and the unit card renders a photo strip and
a walkthrough player the moment they arrive — so this is a serializer change
and nothing else.

It is also inconsistent with Stays, which already does the right thing. Guide
18, §"2026-09-03 Stays v7 Update":

> *"Units now return `photo_urls`, `cover_photo_url`, and `video_url`. Short-let
> media should be read from the nested `unit`, not the parent `property`."*

A guest booking three nights can see inside the flat. A tenant signing for a
year cannot. That is backwards, and it is the single change on this list with
the biggest effect on whether the marketplace works at all.

**What is needed:** add `photo_urls`, `cover_photo_url` and `video_url` to
every unit in `GET /tenant/marketplace/`, exactly as the short-let listing
serializer already does. Keep `photo_count`/`needs_photos`. Nothing needs to
change on the app side.

**Related:** since the whole point of unit photos is that a tenant sees them,
consider making `GET /units/{unit_id}/photos/` readable by any verified user
for a unit that is currently listed. Not required if the serializer change
above lands — it is the fallback the app would otherwise want.

---

## 6. Removing a property: no endpoint, and it needs more than one

Flagged by the product team rather than by a tester: *"we want to add that, but
it would need several verifications."* Agreed on both halves — and there is
currently no endpoint at all. `flutter_api_guide (18).md` has
`DELETE /properties/{id}/photos/{photo_id}/` and
`DELETE /properties/{id}/video/`; there is nothing for the property itself, and
`POST /deletion-requests/` is account deletion, not this.

**No app work has been done on this**, deliberately: there is nothing to point
a button at, and a delete flow designed before the rule that governs it is the
wrong order.

### Why it cannot be a plain `DELETE`

A property is not a leaf. Hanging off it are units, tenancy agreements, escrow
payments, short-let bookings, conversations, reviews and artisan
recommendations. A landlord who deletes a building with a signed tenancy in it
has deleted somebody's home, their agreement and the record of the rent they
paid into escrow — which is evidence in any dispute that follows.

### Proposed rule

**Removal is refused outright while any of these is true:**

| Condition | Why |
| --- | --- |
| Any unit has a live tenancy (`PENDING`, `AWAITING_FIRST_RENT`, `EXECUTED`) | Somebody lives there |
| Any payment on the property is in `ESCROW` or `DISPUTED` | Money is held |
| Any short-let booking is approved, paid or in progress | A guest has plans |
| Any application on a unit is `PENDING` | Somebody is waiting on an answer |

The response should name which of these blocked it, per unit, so the landlord
is told *"Unit A1 has a running tenancy"* rather than *"cannot delete"*.

**Otherwise it is a soft delete, gated and reversible:**

1. `POST /properties/{id}/removal-request/` with a `reason`. Returns the
   blocking conditions if there are any, otherwise creates the request and
   returns a `confirmation_required` challenge.
2. The landlord confirms out of band — a code to the account email, or a
   password re-entry. This is the "several verifications" part, and it is the
   same shape as the payout-account resolve-then-confirm flow that already
   exists, so it is a pattern the app already implements.
3. `POST /properties/{id}/removal-request/{request_id}/confirm/` with the code.
   The property moves to `status: "REMOVAL_PENDING"`: hidden from the
   marketplace and from Stays immediately, still visible to its owner, and
   still fully readable for any historic agreement or payment that references
   it.
4. A cooling-off window — 7 days is the usual span — after which it is archived
   for good. `DELETE /properties/{id}/removal-request/{request_id}/` cancels it
   at any point before that.
5. Records are **never** hard-deleted. Expired agreements and released payments
   keep pointing at the property; it simply stops being listable.

### What the app will add once this exists

A destructive action on the property detail screen, in brick red, behind the
confirmation challenge, showing the blocking reasons per unit when there are
any and a countdown while a removal is pending. Roughly a day, and none of it
can start first.

---

## Summary

| § | Ask | Size | Why it matters |
| --- | --- | --- | --- |
| 1 | First rent in escrow gates occupancy and execution; reservations expire | Large | A tenant can move into a yearly flat having paid nothing. This is the product's core promise |
| 2 | Device registration + push fan-out | Medium | Close the app and nothing reaches you. Every time-sensitive thing Landa does is invisible |
| 3 | `active_agreement` on the unit payload | Small | A landlord can talk to an applicant and then loses the thread once they become a tenant |
| 4 | Case-insensitive location matching, normalise on write, backfill | Small | Filtered searches silently miss listings, and neither side is told why |
| 5B | Unit `photo_urls` / `cover_photo_url` / `video_url` in `GET /tenant/marketplace/` | **Small** | A tenant cannot see inside the flat they are applying for. The app already renders them; Stays already sends them |
| 5A | The same media fields on `GET /properties/` as on `POST /properties/` | Small | A refresh blanked a landlord's own photos. Worked around client-side |
| 6 | Property removal: request, confirm, soft-delete, cool off | Medium | No endpoint exists. Nothing is built app-side pending the rule |

**§5B is the cheapest large win on this list** — one serializer, copying what
the short-let serializer already does — and it is the one a tenant hits on the
screen where they decide whether to apply.

§1 and §2 are the serious ones. §3, §4 and §5A are already worked around in the
app and can follow. §6 is not started.

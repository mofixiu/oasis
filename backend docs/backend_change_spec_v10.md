# Oasis Backend Change Specification — v10

> **Audience:** Backend developer implementing on the Django API (`landa_os`, `users` app).
>
> **Companion documents:** `flutter_api_guide (17).md` (received 2026-09-03) is the current source of truth. `property_verification_and_batch_units_api.md` is the authority on property creation and is contradicted in §1 below. `backend_change_spec_v9.md` is still open on its own points; nothing here supersedes it.
>
> **Date:** 2026-09-04
>
> **Status:** The app has shipped a set of changes to how a landlord lists a property and how the two sides of a tenancy talk to each other. Two of them (§1, §2) are **blocked** on the backend: the app sends the new request, the server refuses it, and the user sees an error. The rest are correctness and quality-of-life items the app currently works around client-side.

---

## Priority

| §   | Change                                                        | Blocking?                        |
| --- | ------------------------------------------------------------- | -------------------------------- |
| 1   | `deed` optional for a short-let property                      | **Yes** — flow cannot complete   |
| 2   | Messaging opens on a pending application                      | **Yes** — feature is dead        |
| 3   | Refuse a duplicate short-let listing                          | No — app guards, imperfectly     |
| 4   | Machine-readable code for a booking date clash                | No — app matches on wording      |
| 5   | Keep short-let units out of the yearly marketplace            | No — but it misleads both sides  |
| 6   | Unit photo count on unit payloads                             | No — app cannot chase a gap      |
| 7   | Store the interval a rent was quoted in                       | No — nice to have, read on       |
| 8   | A poster frame URL for every video                            | No — app opens a stream instead  |

---

## 1. `deed` must be optional when a property is for short lets

**This blocks the whole short-let listing flow. It is the one to do first.**

The add-property flow now opens with a question: is this property for **yearly rent** or for **short lets**? The two collect different things, and a deed is one of the differences.

A deed underwrites a *tenancy* — a document that binds somebody to a home for a year, where a forged ownership claim costs a family their savings. A guest booking three nights signs nothing, pays into escrow, and leaves. The live walkthrough already ties the host to the building, and it is still required. Asking a short-let host for a land title is asking for paperwork most of them do not have, to cover a risk their booking does not carry — and in practice it is what stops a host with a spare flat from listing it at all.

### What the app now sends

For a **yearly rent** property — unchanged from today:

```text
POST /api/users/properties/
Content-Type: multipart/form-data

name, address, city, state, latitude, longitude
verification_method = LIVE_VIDEO_AND_DEED
photos[]            (2+ files)
verification_video  (file)
deed                (file)
```

For a **short let** property — the `deed` part is **absent entirely**, and the method names what is actually attached:

```text
POST /api/users/properties/
Content-Type: multipart/form-data

name, address, city, state, latitude, longitude
verification_method = LIVE_VIDEO
photos[]            (2+ files)
verification_video  (file)
```

### What is needed

`property_verification_and_batch_units_api.md` §2 currently says `deed` is **required** and that a missing one is a field-level `422`. Please relax that to:

- `deed` is required when `verification_method` is `LIVE_VIDEO_AND_DEED` (or is absent, for older clients).
- `deed` is optional — and its absence is not an error — when `verification_method` is `LIVE_VIDEO`.
- `verification_video` stays required in both cases. Nothing about the live walkthrough changes.
- `LIVE_VIDEO` is a new value for `verification_method`; please accept it.

Everything else about verification is untouched: files stay private, malware-scanned, and exposed only as signed URLs to staff and the owning landlord. A `LIVE_VIDEO` property is simply a property whose review has one piece of evidence rather than two, and it is worth deciding on your side whether that changes the manual review bar for those properties — the app does not assume either way.

### Until it ships

The short-let path fails at the last step: the host fills in the whole form, records a walkthrough, and the submission is rejected on a field the app deliberately did not ask them for. There is no client-side workaround that is not a lie (the app is not going to invent a document), so this one genuinely waits on the backend.

---

## 2. Messaging must open on a **pending** application, in both directions

The v17 guide, §"Messaging", is explicit: *"Messaging is available only after the landlord has approved the tenant's application or when an active agreement exists. Pending applications cannot start chat."* — with the refusal:

```json
{
  "code": "NO_RELATIONSHIP",
  "detail": "Messaging opens only after the landlord approves the application."
}
```

**Please change this so that an application in `PENDING` also opens a thread, for either party.**

### Why

The questions a tenant has are the ones they need answered *before* they commit, not after: can I come and inspect on Saturday, what does the service charge cover, will you take the rent monthly. Under the current rule, the channel opens at the exact moment those questions stop being useful. In practice the conversation still happens — it happens on WhatsApp, off-platform, which is precisely the thing Oasis exists to replace, and it takes the payment with it.

It matters in the other direction too. A landlord deciding on an applicant usually wants to ask them something first — when they want to move in, whether they have actually seen the flat. Today they have to *approve* someone to ask them a question, which is the wrong way round: approval creates a tenancy agreement, and it should not be the price of a sentence.

Nothing here is about money. A tenant owes nothing until an agreement is signed, and messaging should not be gated on payment at any point in the apartment flow.

### The rule the app now implements

Client-side, the Message button appears when the application is **`PENDING` or `APPROVED`**, for both roles, on the same `POST /conversations/ {"application": "..."}` body already documented.

Settled applications stay closed, and this half matters as much as the other: **`REJECTED` and `WITHDRAWN` must not open or re-open a thread.** A declined applicant keeping a live channel to a landlord is not messaging, it is contact the landlord did not agree to. If a thread already exists on an application that is later rejected, closing it (`status: CLOSED`) is the right behaviour.

So the eligible set becomes:

| Relationship                         | May open a thread |
| ------------------------------------ | ----------------- |
| Application `PENDING`                | **Yes** (new)     |
| Application `APPROVED`               | Yes               |
| Application `REJECTED` / `WITHDRAWN` | No                |
| Active agreement                     | Yes               |
| Short-let booking, paid              | Yes (unchanged)   |
| Short-let booking, unpaid            | No (unchanged)    |

Short lets are deliberately **not** part of this change. A guest and a host who have only exchanged a booking request are strangers, the stay is not paid for, and there is no unit anybody has committed to — the existing paid-only rule there is correct and the app still gates on it.

Please also update the `NO_RELATIONSHIP` `detail` string, which currently states the old rule in a sentence the app shows verbatim.

### Until it ships

The button is visible and the thread fails to open. The app surfaces the backend's own sentence rather than a generic error, so a tenant tapping Message today reads "Messaging opens only after the landlord approves the application" — accurate, but it is describing a rule we have decided to drop.

---

## 3. `POST /landlord/short-lets/` should refuse a duplicate rather than silently editing

A listing is keyed to its unit, so posting a unit that already has one **edits the existing listing**. That is the documented behaviour and it is right for an edit. It is wrong for a host who believes they are adding a place: their live nightly price, house rules, caution fee, availability window and blocked dates are all replaced by whatever is in the new form, and nothing tells them it happened. The listing they thought they created never appears, and a booking calendar they had built up is gone.

### What the app now does

Before saving, the app looks the unit up in `GET /landlord/short-lets/` and, if it finds a listing there, refuses locally: the unit is disabled in the picker and marked `already listed`, and the save button is off with a line pointing at the edit path.

This is a client-side guard over a cached list, and it is only as good as that cache. It does not cover a listing created on another device, in another session, or since the sheet was opened — which is exactly when the silent overwrite is most likely and least expected.

### What is needed

Make the create path refuse a unit that already has a listing:

```json
{
  "code": "LISTING_EXISTS",
  "detail": "This unit is already listed for short stays.",
  "listing_id": "LISTING_UUID"
}
```

`409 Conflict` or `400` are both fine — the app branches on `code`, not the status. `listing_id` is the useful part: with it, the app can offer "Open that listing" instead of a dead end.

An explicit edit (`PATCH /landlord/short-lets/{listing_id}/`, or a `POST` carrying the listing id) should keep working exactly as it does now. The intent is to separate *create* from *update*, not to make editing harder.

### Smaller ask, same problem

If unit payloads carried a `has_short_let_listing` boolean (and ideally `short_let_listing_id`), the app could grey out already-listed units everywhere they appear without fetching the whole listings collection first. Cheap on your side, and it removes an entire request from a sheet that is already slow to open on a Nigerian connection.

---

## 4. Give the date clash a code the app can branch on

`POST /tenant/short-let-bookings/` checks "already-approved booking conflicts" (v17 guide, §"Tenant Browsing And Booking"), but the refusal is a DRF field error:

```json
{ "check_in": ["These dates are already booked."] }
```

Flattened for display, that reached the guest as **`check_in: These dates are already booked.`** — a field name they have never seen, a full stop in the middle of the sentence, and no indication that the fix is simply to pick other dates. This was reported as unfriendly, and it is.

### What the app now does

It rewrites that one refusal into: *"Someone has already booked those nights. Pick different dates — the calendar shows what is still free."*

The detection is a **string match** on the message (`already booked`, `already reserved`, `not available`, `unavailable`). It is deliberately narrow — a `check_in` error can just as easily be "cannot be in the past", which has a completely different fix, and rewriting that one would send a guest round in circles — but a string match on backend copy is a fragile thing to build on. Rewording the message on your side silently breaks it.

### What is needed

A stable code on the clash, alongside whatever field errors you already send:

```json
{
  "code": "DATES_UNAVAILABLE",
  "detail": "Those nights are already booked.",
  "check_in": ["These dates are already booked."]
}
```

The app will branch on `code` and drop the string matching. If you can also return which nights conflicted — `"conflicting_dates": ["2026-10-02", "2026-10-03"]` — the sheet can grey them out in the picker rather than asking the guest to guess, which is the actual fix for the complaint.

The same applies to the other pre-flight refusals on that endpoint (minimum nights, maximum guests, outside the availability window, blocked dates). The app checks all of them client-side before sending and shows its own wording, so these are lower priority — but a code on each would let the app stop duplicating your rules.

---

## 5. A unit listed for short stays should not appear in the yearly rental marketplace

Per the v17 guide: *"A unit is available when `is_occupied=false` and no active agreement has started for that unit."* A short-let unit satisfies both — it has no yearly tenant and never will — so it shows up in `GET /tenant/marketplace/` as a flat to apply for by the year.

This predates the changes in this document; the new flow just makes it far more likely, because listing a property for short stays is now a first-class path with its own three-step flow, and every unit created through it lands in the yearly marketplace by default.

Both sides lose. A tenant applies for a home that was never available and waits for a decision that will never come. A landlord gets applications they have to decline one by one for a flat they are letting by the night. And because `rent_amount` on a short-let unit is the annual figure derived from a nightly rate (see §7), the price the tenant sees is a number no one would ever be charged.

**Please exclude units that have an active short-let listing from `GET /tenant/marketplace/`.** If there is a real case for a unit being available both ways — some hosts genuinely would take either — then it should be the landlord's explicit choice on the listing (`also_available_yearly: false` by default) rather than the current accident.

---

## 6. Unit photos: the app now requires them, and cannot tell when they are missing

Photos of the **unit** are now compulsory in the app: a minimum of two per unit before a batch can be saved, matching the rule already enforced on property photos. Pictures of the gate tell somebody deciding where to live nothing about the rooms, and units that went up without them were the ones nobody applied for.

Two things about this sit awkwardly with the current API.

### 6.1 Photos are uploaded after the unit exists, so the rule can be defeated by a failure

`POST /properties/{id}/units/batch/` creates the units; `POST /units/{unit_id}/photos/` uploads their photos afterwards, because there is no unit id before the batch lands. The app enforces its rule on the *drafts*, then uploads. If an upload fails — and on a Nigerian connection some will — the units are saved and real, and one of them has no photos. The app reports it ("Open the unit to add them again — the units themselves are saved") rather than deleting units the landlord successfully created, which is the right trade, but the end state is a unit that violates a rule the app claims to enforce.

If the batch endpoint could accept photos per unit as multipart, this whole class of failure goes away. That is a real change and may not be worth it — but it is the clean fix.

### 6.2 There is no way to find the units that are short

Properties carry `photo_count` and `needs_photos`, and the app uses them to prompt a landlord whose listing is hidden. **Units carry neither.** The app currently infers `needs_photos` from the length of `photo_urls`, which is only correct when the payload is complete — list endpoints that trim media would read as "no photos" on a unit that has plenty.

Please add to unit payloads, mirroring the property fields exactly:

```json
{
  "photo_count": 4,
  "needs_photos": false
}
```

With those, a landlord can be shown which of their flats are invisible to tenants and why — which is the only way the units created before this rule existed ever get fixed.

The guide also notes: *"Unit tour video is optional on the backend, even if Flutter requires it before saving the current unit flow."* The same is now true of unit photos. That mismatch is fine and intentional — the app is stricter than the API on purpose, because the API has to keep accepting units created years ago — but it is worth recording that neither rule is enforced server-side, so anything that creates units outside this app can still create ones with no media.

---

## 7. Rent interval — no change required, one thing worth considering

Landlords do not all think in years. A serviced flat is quoted per month, a family house per year, a short let per night. The add-units sheet now asks for the price **and the period it is quoted for**, which is what stops a ₦250,000-per-month flat being listed at ₦250,000 a year.

**No API change is needed for this.** The app converts before sending: `rent_amount` is still always the annual figure, exactly as `backend_change_spec_v6.md` §"rent_amount" specifies (*"The annual figure, whatever `rent_plan` says"*), computed in whole kobo so nothing rounds. A monthly quote is multiplied by 12, a nightly quote by 365, and the sheet shows the landlord the annual result before they save so the multiplication is never done behind their back.

The thing that is lost is the *question*. Once converted, nothing anywhere knows the landlord thinks of that flat as ₦250,000 a month, so every screen — the marketplace card, the application, the agreement — says ₦3,000,000/yr to a tenant who will be quoted ₦250,000 a month by the same landlord on the phone.

If you want to close that gap later, a single nullable field on the unit would do it:

```json
{
  "rent_amount": "3000000.00",
  "rent_interval": "MONTHLY"
}
```

`rent_amount` stays the annual source of truth and nothing computed from it changes; `rent_interval` (`YEARLY` / `MONTHLY` / `NIGHTLY`, nullable, purely descriptive) would let the app display the figure the way it was quoted. **Explicitly not a request** — it is a display improvement, and the app is correct without it. Recording it here so the decision is a decision rather than something noticed in six months.

---

## 8. A poster frame for every video, so the app stops opening a stream to get one

A listing's walkthrough now shows its own first frame as the poster. It used
to show the listing's cover photo, which meant tapping play cut from a
photograph of the gate to a completely different scene — the video visibly
*replacing* the picture rather than starting. A still of the building is a
fine picture of the building and a lie about the video.

### What the app does now

With no `video_thumbnail_url` to fetch, the client obtains that frame by
opening the video itself: `VideoPlayerController.initialize()`, decode frame
zero, render it, and wait for a tap before building a player. It works and it
looks right — but it is the wrong way to get a still image:

- **A range request and a decode per visible video.** For an MP4 that is the
  `moov` atom plus enough samples to decode one frame — small next to the
  clip, large next to a JPEG, and paid on a connection where the JPEG would
  already be cached.
- **It does not scale down a list.** The client had to add a flag
  (`preparePoster: false`) for the units on a property screen, because every
  unit card builds in one pass and a ten-flat building would open ten streams
  the moment it loaded. Those units now show a plain block until tapped —
  correct, but poorer than the rest of the app, and only because there is no
  cheap still to show instead.
- **It cannot be cached like an image.** Every other picture in the app is on
  disk after the first view; a decoded video frame is not, so it is fetched
  again on every visit to the screen.

### What is needed

A poster URL alongside the video, wherever a video is returned:

```json
{
  "video_url": "https://…/tour.mp4",
  "video_thumbnail_url": "https://…/tour-poster.jpg"
}
```

On the unit, the property and the short-let listing payloads — the three
places `video_url` already appears. Generated once on upload (ffmpeg at ~1s
in, so the frame is not a black lead-in), stored beside the video and served
through the same signed-URL mechanism as the photos.

Null is fine and expected for anything uploaded before this ships: the app
keeps its current behaviour wherever the field is absent, so it can land
without a backfill and improve as videos are re-uploaded. A backfill is what
would turn the units list back on — the one place the client workaround is
visibly worse than the rest of the app.

### Related, while the media pipeline is open

Photos are served at full upload resolution. A marketplace card renders one
into a 150pt box and a hero into 340pt, so a 4MB photo is downloaded and
decoded to fill a space needing a fraction of it — on the same connection as
everything else in this document. Size variants (`thumb`, `detail`, `full`),
or an on-the-fly resize parameter, would cut the marketplace's data cost by
roughly an order of magnitude. Not a request yet; flagged so it is a decision
rather than something noticed later.

---

## Summary of what the app sends today

Nothing in this document is speculative — all of it is already in the shipped client, either working or waiting on a server that refuses it.

- `POST /properties/` with **no `deed` part** and `verification_method: LIVE_VIDEO`, for short-let properties. **Currently rejected (§1).**
- `POST /conversations/ {"application": "..."}` for a **`PENDING`** application, from either role. **Currently rejected (§2).**
- `POST /landlord/short-lets/` guarded client-side against duplicates; a stale cache still lets one through. **Silently overwrites (§3).**
- `POST /tenant/short-let-bookings/` failures matched on message wording to rewrite the clash message. **Fragile (§4).**
- `POST /properties/{id}/units/batch/` with `rent_amount` always annual, converted from whatever period the landlord quoted (§7), followed by per-unit photo and video uploads that the app now requires and cannot verify afterwards (§6).
- `GET` on anything carrying a `video_url`: the app opens the video stream
  itself to decode a poster frame, because there is no `video_thumbnail_url`
  to fetch (§8).

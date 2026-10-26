# Oasis Backend Change Specification — v16

> **Audience:** Backend developer implementing on the Django API (`landa_os`, `users` app).
>
> **Date:** 2026-10-17 (§7 added 2026-10-21, status updated 2026-10-23)
>
> **Status:** The app now ships **only v2**, the short-stay app. v1 (long-term rentals) is switched off in the client. This spec lists what changed in the app, what the shipped app still calls, and **seven new pieces of API** the v2 screens are already built against. Every new call degrades gracefully on a `404` until it ships, so these can land in any order.

---

> **Update, 2026-10-23 (API guide 20):** §1–§6 are live on staging, along with `POST /host/listings/` (answering §8 Q1) and the new payout timing, 24 hours after checkout (§8 Q2). The app is now wired to all of them; see **§9**. **§7 (caution fee inspection) is not in guide 20 and is still outstanding.**

## Summary of what you need to build

| § | What | Endpoint(s) | Until it ships, the app… |
| --- | --- | --- | --- |
| 1 | Saved shortlets | `GET/POST /tenant/saved-short-lets/`, `DELETE /tenant/saved-short-lets/{listing_id}/` | keeps hearts on the phone only, per account |
| 2 | Profile details and photo | `PATCH /profile/` (new fields), `POST /profile/avatar/`, new fields on `GET /profile/` | shows "Profile editing is not available yet." |
| 3 | App config (support contacts, legal links) | `GET /app-config/` | uses build-time values; hides anything unset |
| 4 | Support messages | `POST /support/tickets/` | opens the mail app if a support email is configured |
| 5 | Host phone in shortlet conversations | `counterparty.phone` on conversation payloads | shows "Call host" disabled |
| 6 | Blocking in conversations | `POST /conversations/{id}/block/` | shows "Blocking is not available yet." |
| 7 | Caution fee checkout inspection **(still open)** | `caution_claim` on bookings, `POST …/caution-fee/release/`, a checkout notification, an evidence upload, an hourly release job | inspection card works from existing fields; "All good, refund" explains that the refund happens automatically |

All paths are under the existing base (`/api/users`) and use the existing JWT auth unless marked public.

---

## What changed in the app (no backend work needed)

| Change | Detail |
| --- | --- |
| **v1 switched off** | Marketplace, applications, tenancy agreements, rent and escrow, the landlord dashboard and Fix are no longer reachable. Nothing was deleted; see `docs/v1_disabled.md`. **Do not remove any endpoints.** |
| **Wording** | The app says **guest** and **host** where it said tenant and landlord, and **shortlets** where it said stays. The API roles stay `TENANT` and `OWNER`; nothing changes on the wire. |
| **Sign-up** | Opens on Guest (`TENANT`) and no longer offers the artisan route. `ARTISAN` registration is unchanged server-side; it just is not offered. |
| **Payments tab** | Now the guest's **vault** first (balance, add money, withdraw, PIN, history), then shortlet payments. It uses the existing endpoints unchanged: `/vault/`, `/vault/transactions/`, `/vault/pin/`, `/vault/topups/`, `/vault/withdrawals/`, `/payout-account/`, `/tenant/short-let-bookings/`. |
| **"Save for this trip" card** | When a booking is `APPROVED` and unpaid, the Payments tab compares `vault.available_balance` with `booking.total_amount` and offers to top up the shortfall (`POST /vault/topups/` with that amount). No API change. |
| **Discover and Search** | Discover is a photo grid; Search is its own screen. Dates, price and bedrooms moved into a filter sheet. Same `GET /tenant/short-lets/` and the same query parameters as before. |

---

## 1. Saved shortlets

A guest can heart any shortlet and see them later on a Saved screen (2-column grid, filterable by area).

### `GET /tenant/saved-short-lets/`

Returns the user's saved listings, **newest saved first**, in exactly the shape of the items in `GET /tenant/short-lets/` (the app parses them with the same `ShortLetListing.fromJson`). A bare list or a paginated `{ "results": [...] }` envelope are both fine.

```json
[
  {
    "id": "6c1f…",
    "property_name": "The Lumière",
    "city": "Lekki",
    "state": "Lagos",
    "nightly_price": "280000.00",
    "cover_photo_url": "https://…",
    "photo_urls": ["https://…"],
    "average_rating": 4.8,
    "review_count": 32,
    "minimum_nights": 1,
    "maximum_guests": 6,
    "bedrooms": 3,
    "bathrooms": 3,
    "saved_at": "2026-10-17T09:12:00Z"
  }
]
```

* Include listings that have since gone **inactive**, with `is_active: false`, rather than silently dropping them. (The app shows what it is given; a future version can mark them.)
* **TENANT only.** `403` for other roles.

### `POST /tenant/saved-short-lets/`

```json
{ "listing_id": "6c1f…" }
```

* `201` (or `200`) with the listing object. **Idempotent:** saving something already saved returns success, not an error.
* `404` if the listing does not exist.

### `DELETE /tenant/saved-short-lets/{listing_id}/`

* `204`. Unsaving something not saved: please return `204` as well, or `404`. The app treats a `404` on delete as already removed.

### Nice to have

An `is_saved` boolean on each item of `GET /tenant/short-lets/` would let the hearts render correctly before the Saved list has loaded. Not required: the app already fetches the saved list on Home.

### Client behaviour (for reference)

The app calls `GET` on Home. A `404` there means the feature is not deployed, and from then on hearts are stored on the phone (SharedPreferences, keyed by user id), with "Saved on this phone for now." under the grid. Once the endpoint answers, the server list replaces the local one.

---

## 2. Profile details and photo

The v2 **Edit profile** screen edits: photo, full name, phone, date of birth (optional) and bio (optional, 150 characters max). Email and account type are shown read-only.

### New fields on `GET /profile/` (and on the login and register responses, which share the user shape)

```json
{
  "id": "…",
  "email": "jemima@example.com",
  "phone": "+2348123456789",
  "role": "TENANT",
  "verification_status": "VERIFIED",
  "full_name": "Jemima Danjuma",
  "avatar_url": "https://…/avatars/abc.jpg",
  "date_of_birth": "2005-03-12",
  "bio": "Weekend traveller. Quiet guest."
}
```

All four are optional and may be empty strings or `null`. The app shows `full_name` everywhere a name is needed, falling back to the email handle.

### `PATCH /profile/`

The app sends **only the fields that changed**:

```json
{
  "full_name": "Jemima Danjuma",
  "phone": "+2348123456789",
  "date_of_birth": "2005-03-12",
  "bio": "Weekend traveller."
}
```

| Field | Suggested validation |
| --- | --- |
| `full_name` | required when sent; 2–100 characters, trimmed |
| `phone` | E.164 or a Nigerian local format. If changing it needs re-verification, return a clear `400` message: the app shows your `message` verbatim |
| `date_of_birth` | `YYYY-MM-DD`; the app's picker only offers dates 16+ years ago, so validate to whatever minimum age the business wants. Empty string clears it |
| `bio` | 0–150 characters. Empty string clears it |

Return the updated user (same shape as `GET /profile/`). After a successful `PATCH`, the app re-reads `GET /profile/`.

Should a verified user be allowed to change `full_name` once identity verification has matched it to an ID? That is a product decision for you; if not, reject with a `400` and a message such as "Your name is locked after verification. Contact support to change it."

### `POST /profile/avatar/` (multipart)

* Field name: **`avatar`**. JPEG or PNG; the app resizes to at most 1200px and about 85% quality before sending, so files are typically under 500 KB. A 5 MB cap is safe.
* Response: `200`/`201` with `{ "avatar_url": "https://…" }`. The app then re-reads the profile.

### Optional

`avatar_url` on `counterparty` in conversation payloads, so the inbox can show the person rather than the property photo. Not needed now.

---

## 3. App config: support contacts and legal links

The **Help & support** and **Terms & policies** screens need contact details and links that should change without an app release.

### `GET /app-config/` (**public**, no auth)

```json
{
  "support_email": "help@…",
  "support_phone": "+234…",
  "support_whatsapp": "+234…",
  "support_hours": "9am–6pm, Monday to Saturday",
  "terms_url": "https://…/terms",
  "privacy_url": "https://…/privacy"
}
```

* Any field may be empty; the app hides an option whose value is empty ("Coming soon" for the legal links).
* Cache-friendly: the app fetches it each time those screens open.
* Until this ships, the app reads build-time values (`--dart-define=SUPPORT_EMAIL=…`, `SUPPORT_PHONE`, `SUPPORT_WHATSAPP`, `SUPPORT_HOURS`, `TERMS_URL`, `PRIVACY_URL`). **None are set today.** We still need the real support contacts and published Terms and Privacy URLs from the business.

The **cancellation policy** and **caution fee** explanations on the Terms screen come from the app itself (`ShortLetCancellationPolicy.defaultSummary`), so they need nothing from you.

---

## 4. Support messages

"Send us a message" (Help & support) and "Report an issue" (chat details) both open the same form: a category plus free text.

### `POST /support/tickets/`

```json
{
  "category": "BOOKING",
  "message": "The host has not shared the gate code and we arrive in 3 hours.",
  "short_let_booking_id": "b-7f3a91c2",
  "conversation_id": "c-1"
}
```

| Field | Notes |
| --- | --- |
| `category` | One of `BOOKING`, `PAYMENT`, `VAULT`, `ACCOUNT`, `SAFETY`, `OTHER`. "Report an issue" from a chat defaults to `SAFETY` |
| `message` | 10–2000 characters (the app enforces 10 minimum) |
| `short_let_booking_id` | Optional. Sent when the report comes from a conversation whose booking the app knows |
| `conversation_id` | Optional. Sent from chat |

* Response `201`: `{ "id": "…", "reference": "OAS-4821" }`. The app shows the reference in the confirmation ("Sent (ref OAS-4821). We'll reply by email.").
* The copy promises an **email reply**, so please make sure each ticket reaches a human and an acknowledgement email goes to the user's address.
* Validate that the booking and conversation belong to the requester; ignore or reject IDs that do not.
* Until this ships, a `404` makes the app open the mail app with the message prefilled, if `support_email` is known (§3); otherwise it says messaging support is not available yet.

---

## 5. Host phone number in shortlet conversations

The chat details sheet (the "…" in a conversation) has **Call host**. It reads `counterparty.phone`:

```json
"counterparty": {
  "id": "…",
  "full_name": "Tolu Adeyemi",
  "role": "OWNER",
  "verification_status": "VERIFIED",
  "phone": "+2348011112222"
}
```

**Proposed rule:** include `phone` only for `context_type: SHORT_LET` conversations whose booking is paid (`PAID`, `CHECKED_IN`, `CHECKED_OUT`, `COMPLETED`, `DISPUTED`), and send an empty string otherwise. It is the same moment check-in notes are released, and it keeps numbers private before money has moved. Should a host be able to opt out of sharing? Please confirm the policy. The app shows the row disabled ("Their number isn't shared yet") whenever `phone` is empty.

The app also accepts `phone_number` as an alias.

---

## 6. Blocking in conversations

The chat details sheet has **Block host** (or **Block guest**), after a confirmation that says: *"They will not be able to message you, and this conversation becomes read-only. Your booking itself is not cancelled."*

### `POST /conversations/{conversation_id}/block/`

```json
{ "reason": "optional free text" }
```

* `200` with the conversation (or `204`). The app then marks the thread `CLOSED` locally and shows its read-only notice.
* **Effect:** the other person can no longer send messages in this thread, and it should read as `status: "CLOSED"` for both sides on the next fetch. Please don't reveal to the blocked person that they were blocked, beyond the thread being closed.
* **Does not** cancel or alter the booking.
* **Idempotent:** blocking twice returns success.
* Either participant can block. Please record who blocked whom, and when, for the support team. A block that comes with a "Report an issue" ticket should be easy to find from that ticket.
* Unblocking is not offered in the app yet. If you add it, `DELETE` on the same path would be the natural pair.

---

## 7. Caution fee: checkout inspection

**Why:** the caution fee rules are right (guide 19: the host can claim within 24 hours of checkout; unclaimed, it refunds to the guest), but nothing *prompts* the host to inspect, a host who finds everything fine can't release the money early, and the guest can't see a claim on their own trip. The app now has:

* **Host:** a *Checkout inspection* card on every booking whose guest has checked out and whose caution fee is still held, with a live countdown to `caution_fee_release_ready_at`, **All good, refund** and **Report damage** (the existing claim). These bookings sort to the top of the Stays tab and count toward its badge, and host Home shows "N checkouts to inspect".
* **Guest:** a caution fee line on each trip and on booking details (held → host checking, back by <time> → back in your vault), and a banner with **Respond** when the host has claimed.

### 7.1 `caution_claim` on booking payloads (host and tenant booking endpoints)

```json
"caution_fee_release_ready_at": "2026-10-22T11:00:00Z",
"caution_claim": {
  "id": "cl-1",
  "status": "OPEN",
  "claimed_amount": "10000.00",
  "reason": "Broken lamp in the living room.",
  "counter_amount": "",
  "evidence": ["https://…/claims/cl-1/1.jpg"],
  "created_at": "2026-10-21T15:02:00Z"
}
```

* `status`: `OPEN` (waiting on the guest), `ACCEPTED`, `REJECTED`, `COUNTERED`, `RESOLVED` (settled by support). The app also accepts `PENDING` for `OPEN` and `CLOSED`/`SETTLED` for `RESOLVED`.
* `null` (or absent) when there is no claim. If there could ever be more than one claim per booking, send the latest.
* **This is the important one.** Today the only way the guest's app learns a claim exists is the `SHORT_LET_CAUTION_FEE_CLAIM` notification's payload, so a guest who misses or clears that notification cannot respond at all. With `caution_claim` on the booking, the trip itself shows the claim and the Respond button.
* Please make sure `caution_fee_release_ready_at` is present on **every** paid booking with a caution fee, on both the host and tenant booking lists. It drives the countdown; without it the app says "within 24 hours of checkout" instead of a time.

### 7.2 Host releases the caution fee early

```text
POST /api/users/landlord/short-let-bookings/{booking_id}/caution-fee/release/
```

No body. Response `200` with the updated booking (or `204`).

* Allowed only for the booking's host, after checkout, while the caution fee is still held and no claim is open. Otherwise `400` with a readable `message` (the app shows it verbatim).
* Effect: refund the full caution fee to the guest's vault now, set `caution_fee_refunded_at`, and close the claim window (a later claim is refused). Idempotent: releasing an already-refunded fee returns success.
* Notify the guest (for example `SHORT_LET_CAUTION_FEE_REFUNDED`: "Your ₦50,000 caution fee is back in your vault").
* Until this ships, a `404` makes the app say: "Refunding early is not available yet. The caution fee goes back to the guest automatically when the 24 hours are up."

### 7.3 Prompt the host at checkout

Push is out of MVP, so this is an in-app notification (and email if you send those for bookings):

* **At checkout** (when the booking reaches `CHECKED_OUT`, or at the checkout time on the check-out date): notify the host, type `SHORT_LET_CHECKOUT_INSPECTION`, for example *"Jemima has checked out of The Lumière. Check the place and refund the ₦50,000 caution fee, or report damage before 11:00 tomorrow."* Include `booking_id` and `release_ready_at` in `data`.
* **Reminder** about 3 hours before `caution_fee_release_ready_at` if the host has done nothing.
* The app's inspection card is the real prompt; the notification is what brings the host back to it.

### 7.4 Run the release job hourly

`release_ready_shortlet_escrows` runs once a day (07:00 UTC per guide 19 / spec v15). For caution fees that means a guest can wait up to ~48 hours after checkout, while the app says 24. Please run it **hourly** (or at least every few hours) so the refund lands close to `caution_fee_release_ready_at`. Since guide 20 this matters for the host payout too: it is now due 24 hours after checkout, at the same moment, so a daily job delays both.

### 7.5 Damage photos for claims

The claim endpoint already accepts `evidence` as URLs, but the app has nowhere to upload a photo to get one.

```text
POST /api/users/landlord/short-let-bookings/{booking_id}/caution-claims/evidence/   (multipart, field "photo")
→ 201 { "url": "https://…" }
```

The app will then send those URLs in `evidence` when opening the claim, and show them to the guest on the claim banner. (The claim sheet is text-only until this exists.)

### 7.6 The guest's claim response, from the trip

No new endpoint: the trip's **Respond** button uses the existing `POST /tenant/short-let-caution-claims/{claim_id}/respond/` with the `id` from §7.1. After a response, the app re-reads the booking list, so the new `caution_claim.status` should be reflected there straight away.

---

## 8. Open questions and follow-ups

1. ~~**Host onboarding in v2.**~~ **Answered:** `POST /host/listings/`. Built in the app; see §9.
2. ~~**Payout timing.**~~ **Answered:** the host payout is now held until 24 hours after checkout (`host_payout_release_at` / `escrow_release_at`). The app's copy is updated; see §9.
3. **Support contacts and legal URLs** (§3): `/app-config/` is live and returns every value empty. Waiting on the business for the support email, phone, WhatsApp, hours, and the Terms and Privacy links. The app hides each one until it is set.
4. ~~**Phone sharing policy** (§5).~~ **Answered:** blank until the booking is paid.
5. ~~**Locked fields after verification** (§2).~~ **Answered:** the name. The app shows it read-only for verified users.

---

## 9. Follow-up after API guide 20 (2026-10-23)

What the app now does with the live endpoints, and three small asks.

| Area | App behaviour |
| --- | --- |
| Saved shortlets | Reads and writes the server. The on-phone copy is only a cache now. |
| Profile | Name is read-only for ID-verified users ("Your name comes from your ID check. Contact support to change it."). Phone, birthday, bio and photo save as before. |
| App config | An empty value from the server is final: that contact or link is hidden ("Coming soon" for Terms and Privacy). Build-time values are used only when the server cannot be reached. |
| Support tickets | Sent to `POST /support/tickets/`; the `OAS-` reference is shown. |
| Host phone | When `counterparty.phone` is empty, **Call host** says "Shared once the booking is paid" (or "Their number isn't available" on a paid booking). |
| Block | Unchanged; the returned `CLOSED` conversation is shown read-only. |
| New host | **List a place** opens on "A new place": name, address, state and city, a map pin, flat or unit (optional, sent as `"1"` when blank), bedrooms, bathrooms, then the usual listing fields. It posts to `POST /host/listings/`, then opens the unit's photo upload (`/units/{unit_id}/photos/`). Hosts with existing properties can still choose "One of my units". |
| Payout timing | The host's payout line reads "Releases {date}, a day after checkout, unless the guest reports a problem first", from `host_payout_release_at` (falling back to `escrow_release_at`). That line now takes precedence over `host_payout_status_description`. |

**Asks, answered 2026-10-23**

1. ~~**`POST /host/listings/` response.**~~ **Answered:** `201` with the normal short-let listing object (not a wrapper), with `property` and `unit` nested. The app parses it as a listing and takes the property and unit ids from the nested objects.
2. ~~**Visibility of a new place.**~~ **Answered:** for now a new place is visible to guests as soon as it exists if `is_active` is true (the default), even while the property is `PENDING_REVIEW` and before any photos. The backend will later hold it back until review is done and photos are uploaded. The app handles a listing with no `cover_photo_url` and empty `photo_urls` everywhere: listing cards, trips and booking details show a plain "No photos yet" tile (never a stock photo), the listing page shows an empty photo header, and the host gets an "Add photos" prompt right after creating the place and on the listing in **My places**.
3. ~~**Payout description copy.**~~ **Answered:** the guide wording is stale and will be corrected. The rule is 24 hours after checkout, provided there is no dispute; `host_payout_release_at` and `escrow_release_at` are the source of truth, which is what the app already shows.

**Live check, 2026-10-26.** Every path the app calls was requested on staging without a token: all answer `401` (they exist) except the two §7 caution-fee paths (`…/caution-fee/release/`, `…/caution-claims/evidence/`), which answer `404`. `GET /app-config/` still returns every value empty. The app also has a `/notifications/unread-count/` constant that staging does not serve; nothing calls it, so no action is needed.

**Still to do on the backend:** gating a new place until it is reviewed and has photos (item 2), correcting the guide wording (item 3), the business inputs in §8 Q3 plus `SUPPORT_TICKET_RECIPIENT_EMAIL`, and §7.

---

## Client references

| Area | File |
| --- | --- |
| New endpoint paths | `lib/core/network/api_constants.dart` (block marked "v2 (spec v16)") |
| New host listing | `lib/features/shortlets/views/create_shortlet_sheet.dart` (`_newPlace`), `…/services/shortlet_service.dart` (`createHostListing`), `…/models/shortlet_models.dart` (`HostListingResult`) |
| Saved | `lib/features/shortlets/services/saved_shortlets_service.dart`, `…/controllers/saved_shortlets_controller.dart`, `…/views/v2/v2_saved_screen.dart` |
| Profile | `lib/features/profile/services/profile_service.dart`, `…/views/v2_edit_profile_screen.dart`, `lib/features/auth/models/user_model.dart` |
| Config and support | `lib/features/support/services/support_service.dart`, `…/views/v2_help_screen.dart`, `v2_terms_screen.dart`, `v2_support_message_sheet.dart` |
| Phone and block | `lib/features/messaging/models/conversation_models.dart`, `…/services/messaging_service.dart`, `…/controllers/messaging_controller.dart`, `…/views/conversation_screen.dart` |
| Caution fee inspection | `lib/features/shortlets/models/shortlet_models.dart` (`CautionClaim`, `cautionFeeStage`, `isAwaitingCheckoutInspection`), `…/views/widgets/caution_fee_widgets.dart`, `…/views/landlord_shortlets_screen.dart`, `…/views/v2/v2_host_home_screen.dart`, `…/views/my_shortlet_bookings_screen.dart`, `…/views/v2/v2_booking_details_screen.dart` |
| v1 switched off | `docs/v1_disabled.md` |

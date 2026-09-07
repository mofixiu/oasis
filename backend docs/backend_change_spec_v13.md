# Landa OS Backend Change Specification — v13

> **Audience:** Backend developer implementing on the Django API (`landa_os`, `users` app).
>
> **Companion document:** `flutter_api_guide (18).md`, received 2026-09-06. This document is a response to it.
>
> **Date:** 2026-09-06
>
> **Status:** Guide 18 closed almost all of v11 and v12 — the realtime socket, the stay description, the bedrooms filter, `PATCH /units/{id}/`, the application rent freeze and the price-drop notifications are all live, and the app has been updated to match. Nothing here is a new feature request. It is four contradictions or gaps in the guide that the app has had to guess at, and one UX item the guide asked the app team for.

---

## What the app changed in response to guide 18

Recorded first, because four of these were silent breakages — the app was making requests the backend had stopped honouring, with no error anywhere.

| Change | Was | Now |
| --- | --- | --- |
| Short-let **edit** | `POST /landlord/short-lets/` (treated as an edit) | `PATCH /landlord/short-lets/{listing_id}/` |
| Message polling cursors | `?after=` / `?before=` | `?since_message_id=` / `?before_message_id=` |
| WebSocket heartbeat | App pinged every 25s, ignored the server's ping | App answers the server's `ping` with `pong` |
| `conversation.updated` payload | Read as a bare conversation | Unwrapped from `{"conversation": {...}}` |
| `409 LISTING_EXISTS` | Not handled | Refetches, then opens the listing that already exists |
| Notification types | 5 unknown, rendered as "Update" | `UNIT_PRICE_CHANGED`, `SHORT_LET_PRICE_CHANGED`, `SHORT_LET_BOOKING_REPRICED`, `VERIFICATION_SUCCEEDED`, `VERIFICATION_FAILED` all named, coloured and iconed |

The messaging one is worth calling out: `after`/`before` were never documented, and the backend was ignoring them. Every four-second poll on an open thread was re-downloading the whole conversation. That is now what it was always meant to be — a request for the two lines that are new.

---

## 1. `PATCH /landlord/short-lets/{listing_id}/` is in the route table and nowhere else

Guide 18 §"Endpoint Summary" lists:

```text
| Edit short let listing | PUT/PATCH | /api/users/landlord/short-lets/{listing_id}/ | Yes + verified | OWNER |
```

That is the only mention of it. There is no request body, no response shape, and no statement of semantics — but it is now the **only** way to change a listing, because `POST` refuses a duplicate. The app is using it on a reading of the route table alone.

### What the app currently sends

The complete listing, every field, on every edit:

```text
PATCH /api/users/landlord/short-lets/{listing_id}/

{
  "nightly_price": "42000.00",
  "minimum_nights": 2,
  "maximum_guests": 4,
  "description": "…",
  "caution_fee": "25000.00",
  "cancellation_policy": "MODERATE",
  "available_from": "2026-09-01",
  "available_to": "2026-12-31",
  "blocked_dates": ["2026-10-10"],
  "house_rules": "No parties.",
  "check_in_notes": "Code shared after payment.",
  "is_active": true
}
```

`unit` is deliberately **absent** — the listing already knows its unit, and moving one between units is not something the API offers.

The full body is sent even from the price-only editor, where the host changed one number. That is the conservative reading: if `PATCH` behaves like `PUT` and replaces, an omitted key is a house rule deleted and a calendar wiped, and there is no way for the app to find out that happened.

### What is needed

1. **Say which it is.** If `PATCH` is a genuine partial update, the app will send only the fields that changed — which is both cheaper and much safer, because it removes the whole class of "the price sheet forgot to carry a field through". If it replaces, the app keeps sending everything.
2. **Document the response.** The app parses it as a listing and writes it back into the row it edited. A response that omits `photo_urls` or `bedrooms` blanks those on screen until the next refresh.
3. **Confirm `409 LISTING_EXISTS` cannot fire on `PATCH`.** It is a create-time conflict; a listing patching itself is not a duplicate of itself. If it can fire, say when.

---

## 2. `nightly_rate` or `nightly_price`? The guide says both

Guide 18, §"Short-Let Bedroom Filter & Room Counts", under **Listing Fields Exposed**:

```json
{
  "id": "123e4567-e89b-12d3-a456-426614174000",
  "name": "Luxury Oceanview Apartment",
  "description": "Spacious 2-bedroom short-let with fast Wi-Fi and 24/7 power.",
  "bedrooms": 2,
  "bathrooms": 2,
  "nightly_rate": "45000.00"
}
```

Every other reference in the guide — the create body, the reprice note in §11 — calls it `nightly_price`, and `nightly_price` is what the app has always sent and received. This snippet also gives a listing a top-level `name`, which appears nowhere else.

The app now reads `nightly_price ?? nightly_rate`, and `property_name ?? property.name ?? name`. That is two lines of defensiveness against what is almost certainly a typo in an illustrative snippet — but the cost of being wrong is every stay in the marketplace advertised at **₦0**, with no error, so it was not worth assuming.

**Please confirm the serializer emits `nightly_price`,** and correct the snippet. If it really does emit `nightly_rate` on the browse route while emitting `nightly_price` elsewhere, that is worth knowing quickly.

---

## 3. Two things about the socket that the app is now relying on

Both are behaviours guide 18 implies but does not state, and both are load-bearing.

### 3.1 An unsolicited client frame must not close the connection

The app sends exactly one thing up the socket: `{"type":"pong"}`, in reply to the server's `ping`. It sends nothing else, ever.

Please confirm the consumer tolerates that frame — and, if the connection is ever going to carry client-originated frames (a "reading this thread" hint, say), that an unrecognised `type` is ignored rather than treated as a protocol error. A consumer that closes on an unexpected frame turns a forward-compatible client into a reconnect loop.

### 3.2 What a rejected handshake looks like

Guide 18 says the token goes in the `Authorization` header and that each connection is bound to its user. It does not say what happens when the token is missing or expired.

The app treats **close code `4001`** as "this session is not authenticated, stop trying" and every other close as transient, reconnecting with backoff (1s, 2s, 5s, 10s, 30s, 2m, then holding at 2m). If an expired token produces an ordinary close instead, every phone with a stale token reconnects against a server that will refuse it every time, for as long as the app is open.

Either reject the upgrade outright with `401`/`403` before the socket exists, or close with `4001`. Anything else and the app cannot tell "try again" from "never".

---

## 4. `min_bedrooms` and studios

Confirmed working. One question the guide does not answer: what happens to a listing with `bedrooms = 0`.

`min_bedrooms=1` should exclude studios — that is the point of the filter. The app never sends `min_bedrooms=0`, because a zero floor matches everything and would be a filter that claims to narrow and does not.

The app also still filters the response client-side as a fallback, guarded so it only runs when at least one listing in the response carries a non-zero bedroom count. Once §2 above is confirmed and `bedrooms` is reliably present on every payload, that guard can go — it is there because a backend that omits `bedrooms` parses every listing as zero, and filtering on that would empty the list rather than fail to narrow it.

---

## 5. The artisan "registered successfully" screen — what the app does now

Guide 18 §12 asks the app team for this, so here is the current state and what is actually missing.

**Already true.** Registration has never dropped an artisan into the app as though they were finished: `POST /register/` succeeding routes straight to the identity verification screen, and `MainScaffold` refuses every product screen until the profile reads `VERIFIED`. The gate was already there.

**Changed today, because of `VERIFICATION_SUCCEEDED`.** The app used to learn about clearance only by polling `GET /verify/status/`, which meant an artisan could sit on the verification screen for minutes after being approved. It now re-reads the profile the moment that notification lands over the socket, and the shell lets them through on the next frame. Your artisan-specific wording — *"You're verified! Your Landa artisan registration is complete and landlords and tenants can now find and contact you."* — is shown as sent, in an in-app banner.

The post-signup message was also reworded, because it overstated things: "Account created successfully!" now reads *"Account created. Verify your identity to start taking jobs."*

**Still a decision, not a gap.** A dedicated full-screen "you are registered" moment for artisans is a design question rather than an integration one, and it is not built. Between the gate, the notification and the banner, an artisan is now told the right thing at the right time; whether that deserves its own screen is a product call.

Nothing is needed from the backend for any of this.

---

## Nothing outstanding from v11 or v12

For the record, since both documents can now be closed:

* **v11** — realtime socket, stay `description`, `min_bedrooms`: all shipped in guide 18. The one correction is that the heartbeat runs server-first, not client-first as v11 §1 proposed; the app follows the guide.
* **v12** — `PATCH /units/{id}/`, short-let reprice safety, application rent freeze, price-drop notifications, price audit trail: all shipped. §2's third case was answered with new behaviour (a pending booking re-prices on approval and the guest is notified), which is a reasonable answer and the app handles the notification.

The only v12 item that came back differently from the ask is worth a note: the app still carries its 404/405 fallback message for `PATCH /units/{id}/` ("This server cannot change a rent yet — your unit is unchanged"). That is now dead code against staging and will stay until every deployment has the route.

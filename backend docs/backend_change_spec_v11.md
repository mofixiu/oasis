# Landa OS Backend Change Specification — v11

> **Audience:** Backend developer implementing on the Django API (`landa_os`, `users` app).
>
> **Companion documents:** `flutter_api_guide (17).md` (received 2026-09-03) is the current source of truth for REST. `backend_change_spec_v10.md` is still open on its own points; nothing here supersedes it. §1 below introduces a **second transport** alongside REST and is the largest single item in this document.
>
> **Date:** 2026-09-05
>
> **Status:** The app has shipped a realtime layer, an in-app popup system, a short-let description and a bedrooms filter. Every one of them **works today against the current backend**, degraded: the socket fails to connect and the app falls back to polling, the description round-trips as an empty string, and the bedrooms filter is applied client-side. None of it is blocking. All of it is worse than it needs to be until this ships.

---

## Priority

| §   | Change                                                       | Blocking? | Effort |
| --- | ------------------------------------------------------------ | --------- | ------ |
| 1   | Realtime WebSocket (`/ws/realtime/`)                         | No — app polls as fallback | Large |
| 2   | `description` on a short-let listing                         | No — saves as `""` today   | Small |
| 3   | `min_bedrooms` filter, and `bedrooms` on every listing payload | No — app filters locally | Small |
| 4   | `?after=` on the messages endpoint must actually filter      | No — but it is the poll's whole cost saving | Small |
| 5   | `GET /conversations/unread-count/` is now on the hot path    | No — confirm it is cheap | Check |
| 6   | Push notifications (out of scope here, named so it is planned) | No | — |

---

## 1. Realtime: one WebSocket at `/ws/realtime/`

**This is the item worth doing.** Everything else in this document is a field or a query parameter.

### The problem it solves

Messaging is currently polled. An open thread asks `GET /conversations/{id}/messages/?after=…` every four seconds, and the inbox asks for the conversation list on a slower timer. That has three costs, in increasing order of importance:

1. **Requests.** A hundred people with a thread open is 1,500 requests a minute for, almost always, an empty list.
2. **Latency.** A reply takes up to four seconds to appear, and only if the recipient happens to have that screen open.
3. **Everything that is not messaging.** A booking request landing, an application being approved, rent being confirmed — none of it reaches a user who is not on the screen that shows it. The app has an in-app popup system now (a banner that drops from the top of any screen), and without a push channel it has nothing to raise banners *from* except a slow poll.

### What the app now does

`lib/core/network/realtime_socket.dart` holds one WebSocket for the whole app, and `lib/core/session/realtime_hub.dart` routes what comes down it. The socket:

* connects on sign-in and on the app returning to the foreground; disconnects on sign-out and on backgrounding;
* reconnects on its own with backoff — 1s, 2s, 5s, 10s, 30s, 2m — and never gives up;
* tears itself down and rebuilds if **nothing at all** arrives for 70 seconds;
* is never load-bearing. Every screen behind it still fetches over REST, and messaging keeps its four-second poll armed, skipping the request while the socket is up. **If `/ws/realtime/` is never implemented, the app behaves exactly as it does today.** That is deliberate, and it is why this is not blocking.

### The endpoint

```text
wss://landa-os-staging.onrender.com/ws/realtime/
```

Routed by Django Channels at the **project root**, not under `/api/users/`. The app derives it from the REST base URL: same host, same port, `https` → `wss`.

### Authentication

The token travels in the **`Authorization` header on the opening handshake**:

```text
GET /ws/realtime/ HTTP/1.1
Upgrade: websocket
Authorization: Bearer <access token>
```

Please do **not** ask for it in the query string. A URL is written to every proxy and access log between the phone and Render, and a JWT in one is a credential sitting on somebody else's disk.

Expected behaviour:

* valid token → accept, and the connection is scoped to that user for its lifetime;
* missing, malformed or expired token → **reject the handshake** (HTTP 401/403 before the upgrade, or close with code `4001`). Do not accept and then stay silent — the app treats an accepted-but-silent socket as alive for 70 seconds before it gives up.

A user is only ever sent events addressed to them. There is no subscribe step and no channel names on the wire: the server already knows who is connected, and letting a client name a channel is how a client ends up reading someone else's.

### Frames

Every frame is a JSON object with a `type`. The app accepts either of these two shapes, so pick whichever is natural:

```json
{ "type": "message.created", "data": { "…": "…" } }
```

```json
{ "type": "message.created", "conversation_id": "…", "message": { "…": "…" } }
```

Unknown `type` values are logged and ignored, so new events can ship server-first without breaking an older build.

#### `message.created`

Sent to **both** parties of a conversation when a message is created — including the sender, whose app matches it against the optimistic bubble by `client_message_id` and replaces it rather than showing the sentence twice.

```json
{
  "type": "message.created",
  "data": {
    "conversation_id": "CONVERSATION_UUID",
    "message": {
      "id": "MESSAGE_UUID",
      "conversation": "CONVERSATION_UUID",
      "body": "Good afternoon, I am ready for the next step.",
      "sender_role": "TENANT",
      "sender_name": "Ada Okafor",
      "is_system": false,
      "client_message_id": "CLIENT_GENERATED_ID",
      "read_at": null,
      "created_at": "2026-08-25T09:05:00Z"
    }
  }
}
```

`message` is **the same serializer as `GET /conversations/{id}/messages/`**. That is not a nicety — the app parses it with the same `Message.fromJson`, and a socket payload shaped differently from the REST one is a second contract to keep in step and a class of bug that only appears in production.

#### `notification.created`

Sent when a notification row is created for this user.

```json
{
  "type": "notification.created",
  "data": {
    "notification": {
      "id": "NOTIFICATION_UUID",
      "notification_type": "SHORT_LET_BOOKING_REQUESTED",
      "title": "New booking request",
      "message": "Ada asked for 12–14 March.",
      "is_read": false,
      "created_at": "2026-09-05T09:00:00Z",
      "data": { "booking_id": "BOOKING_UUID" }
    }
  }
}
```

Again: **the same serializer as `GET /notifications/`**, `data` payload included. The deep-link ids in there are what let a popup open the right screen when it is tapped.

Note the app already suppresses the popup for `MESSAGE_RECEIVED` and `SHORT_LET_MESSAGE_RECEIVED` while the socket is connected, because `message.created` has already raised a better one. Keep sending both; the app sorts it out.

#### `conversation.updated`

Sent when a thread's own state changes — it closes because the relationship ended, or its unread count is cleared because the user read it on another device.

```json
{
  "type": "conversation.updated",
  "data": { "id": "CONVERSATION_UUID", "status": "CLOSED", "unread_count": 0 }
}
```

Same serializer as the conversation list.

#### `unread.counts`

Optional but cheap and worth it. Send it once immediately after a socket is accepted.

```json
{ "type": "unread.counts" }
```

A reconnect can have missed events entirely, and the app cannot know what it missed. Receiving this makes it re-read both badge counts from the REST endpoints, which is the only way a badge is guaranteed correct after a tunnel or a lift. The app also does this on its own whenever the socket reaches `connected`, so this frame is belt-and-braces rather than a requirement.

#### `ping` / `pong`

The app sends `{"type":"ping"}` every 25 seconds and ignores whatever comes back. Please:

* accept and discard a client `ping` (or answer `{"type":"pong"}` — either is fine);
* send the server's own periodic frame at **under 70 seconds**, whatever it is. The app tears the socket down after 70 seconds of complete silence, because a TCP connection through a mobile NAT can be dead for minutes with neither end being told.

### Close codes

Anything other than a clean close makes the app reconnect with backoff. If you want it to *stop* — an authentication failure it should not retry — close with **`4001`** and it will treat the session as unauthenticated. Any other code is treated as transient.

### What this does not cover

The socket only delivers while the app is in the foreground. It is not push. See §6.

---

## 2. `description` on a short-let listing

A short-let listing currently has `house_rules` (what a guest may not do) and `check_in_notes` (arrival logistics, released only after payment). It has nothing that says **what the place is like** — which is the only field a guest actually reads while choosing between two flats at the same price.

Landlords have asked for it, and it is now in the app: a field on the create/edit sheet, shown at the top of the guest-facing listing, with a nudge on the host's own listing row when it is missing.

### What the app now sends

`POST /api/users/landlord/short-lets/` — one new key, on **every** save:

```json
{
  "unit": "UNIT_UUID",
  "nightly_price": "50000.00",
  "minimum_nights": 2,
  "maximum_guests": 3,
  "description": "A quiet two-bedroom flat five minutes from the airport. Fast wifi, 24-hour power, parking in the compound.",
  "caution_fee": "25000.00",
  "cancellation_policy": "FLEXIBLE",
  "available_from": "2026-09-01",
  "available_to": "2026-12-31",
  "blocked_dates": ["2026-10-10"],
  "house_rules": "No parties.",
  "check_in_notes": "Code shared after payment.",
  "is_active": true
}
```

Always sent, including as `""`. Same reasoning as the booking window in v10 §1: an omitted key cannot *clear* a paragraph the host has just deleted, and an absent key is indistinguishable from a field the backend has never heard of.

### What is needed

1. `description` — `TextField(blank=True, default="")` on the short-let listing model.
2. Accepted on `POST /landlord/short-lets/`, **max length 1000 characters** (the app enforces the same ceiling in the field, so a rejection here means the two have drifted).
3. Returned on `GET /landlord/short-lets/` **and** `GET /tenant/short-lets/`, and on the listing nested inside a booking payload.
4. Unless the field is already there, an existing listing gets `""`, which the app reads as "not written yet" and renders nothing for.

### One thing worth considering

If the **unit** already carries a `description`, send it through as the listing's when the listing has none of its own. The app reads `unit.description` as a fallback for exactly this reason: a host who wrote the flat up when they added it should not have to write it again to let it by the night.

---

## 3. `min_bedrooms`, and `bedrooms` on every listing payload

### 3.1 The filter

Tenants browsing stays can now filter by number of bedrooms. It is a **floor**, not an exact match — "2+" — because that is how the question is asked: a family of five needs at least three rooms and will happily take four.

```text
GET /api/users/tenant/short-lets/?location=Lekki&min_bedrooms=2
```

Composes with everything already there — `location`, `latitude`/`longitude`/`radius_km`, `check_in`/`check_out`, `min_price`/`max_price` — as an independent narrowing. Absent means no bedroom constraint.

Note that `min_bedrooms=0` is **not** the same as omitting it, and the app never sends it: a studio is legitimately zero bedrooms, so a zero floor would be a filter that matches everything while claiming to filter.

### 3.2 The field it depends on

The filter is only half of it. `bedrooms` and `bathrooms` must be present on **every** short-let listing payload, on both the landlord and the tenant routes. Today they are inconsistent, and the app reads them from either the listing or the nested `unit`, defaulting to 0.

This matters more than a missing filter would suggest. The app applies the bedrooms filter client-side as well, so the control works before this ships — but it is guarded: it only filters when at least one listing in the response reports a non-zero bedroom count. Without that guard, a backend that omits `bedrooms` would parse every listing as zero, and asking for "2+" would empty the list rather than fail to narrow it. An empty list reads as *there is nowhere to stay*, which is a considerably worse failure than a filter that does nothing.

So: send `bedrooms`, and the guard stops mattering.

### 3.3 Related

The same two fields are what "The space — 2 bedrooms · 1 bathroom" on the listing screen is drawn from, so a listing missing them is already rendering "0 bedrooms · 0 bathrooms" to a guest today.

---

## 4. `?after=` on the messages endpoint

The app's fallback poll asks:

```text
GET /api/users/conversations/{id}/messages/?after=<message_id>&limit=50
```

and expects **only messages newer than that id**. This is not documented in `flutter_api_guide (17).md`, so it is worth confirming rather than assuming.

If the parameter is ignored, everything still works — the app de-duplicates by id before merging — but every poll re-downloads the entire thread, on a four-second timer, which is precisely the cost the parameter exists to avoid.

A `304 Not Modified` for "nothing newer" is welcome and the app handles it, but a `200` with an empty list is equally fine.

One related note: the app now sends the request **without** `after` when the thread it holds is empty. That fixes a real bug on the client — an empty thread had no id to anchor to, so the poll bailed out on every tick and the counterparty's *first* message never arrived until the user left the screen and came back. Nothing is needed on the backend for that; it is recorded here because the request pattern changed.

---

## 5. `GET /conversations/unread-count/` is now on the hot path

The Messages button in the app bar carries an unread dot. Until now that dot was derived from the conversation list, which is empty until the inbox has been opened — so the dot only ever appeared *after* visiting the screen it exists to advertise. It now reads `GET /conversations/unread-count/` instead, and **both dashboards call it on every load** (mount, return from a pushed route, app resume) alongside the rest of their fetches.

Nothing new is required. This is a heads-up that an endpoint which was called rarely is now called on essentially every dashboard render, so it is worth a look:

* it should be a `COUNT`, not a serialization of every thread;
* it should be indexed on (recipient, read_at);
* the `conversations_with_unread` field in the documented response is not read by the app — do not spend a second query on it.

While the realtime socket is down, the app also polls `GET /notifications/?is_read=false` every 45 seconds per foregrounded session, to drive in-app popups. That poll stops entirely once §1 ships.

---

## 6. Push notifications — named, not asked for

Out of scope for this document, but worth stating so it is not mistaken for something §1 delivers.

The realtime socket only runs while the app is **in the foreground**. A booking request that arrives while the phone is in someone's pocket reaches them when they next open the app, not before. For a product where a landlord has 24 hours to approve and a guest has 24 hours to pay, that is a real gap, and closing it needs FCM/APNs — a device-token endpoint, a server key, and a payload that mirrors the notification serializer.

That is a separate piece of work with its own certificates and its own consent flow. Flagging it here only so the sequencing is clear: §1 makes the app live while someone is looking at it, and push is what makes it live when they are not.

---

## Summary of what the app sends today

| Call | Change |
| --- | --- |
| `wss://…/ws/realtime/` | **New.** `Authorization: Bearer` header on the handshake. Client `ping` every 25s. Reconnects with backoff; treats 70s of silence as dead. |
| `POST /landlord/short-lets/` | `description` added, sent on every save including as `""`. |
| `GET /tenant/short-lets/` | `min_bedrooms=<n>` added, omitted when no floor is set. |
| `GET /conversations/{id}/messages/` | `after` now omitted when the client holds no server message for that thread. |
| `GET /conversations/unread-count/` | Now called from both dashboards on every load. |
| `GET /notifications/?is_read=false` | Polled every 45s per foregrounded session, **only while the socket is down**. |

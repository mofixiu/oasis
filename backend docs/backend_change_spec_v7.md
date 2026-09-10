# Oasis Backend Change Specification — v7

> **Audience:** Backend developer implementing on the Django API (`landa_os`, `users` app).
>
> **Companion document:** `flutter_api_guide (15).md` in this folder describes the API as it exists today. This document describes only what **changes**. When this ships, fold it into the guide and bump it to `(16)`.
>
> **Base URL (staging):** `https://landa-os-staging.onrender.com/api/users`
>
> **Status:** Six items, in descending order of how badly the app is blocked without them.
>
> | § | Change | Severity | Flutter today |
> | :-- | :--- | :--- | :--- |
> | 1 | Short-let booking window must be genuinely optional | **Blocking** | Landlord cannot list a place without setting dates, despite the field being labelled optional |
> | 2 | Caution fee on a short-let listing | **Blocking for the feature** | Field is collected and sent; ignored server-side, so no deposit is ever charged |
> | 3 | Per-unit photos and tour video | **Blocking for the feature** | Media is collected per unit and uploaded to endpoints that do not exist yet |
> | 4 | Ratings and reviews | **New feature** | Whole UI shipped; degrades to "unrated" against a backend without it |
> | 5 | Conversation on a paid short-let booking | **New feature** | "Message the host" button shipped; fails with the backend's own error until this lands |
> | 7 | Short-let booking status vocabulary is undocumented | **Diagnostic** | An unrecognised status renders a booking with no actions; the app now names the word it could not read |
>
> §1 is the one to do first and is a two-line change.

---

## 1. Blocking: the short-let booking window is not actually optional

### 1.1 The problem

`POST /api/users/landlord/short-lets/` documents `available_from` and `available_to` as part of the body, and the app presents them as **optional** — a host who takes bookings whenever should not have to invent a date range. In practice the serializer requires them, so a landlord who leaves the field alone gets:

```json
{ "available_from": ["This field is required."] }
```

From the landlord's side this reads as the app lying to them: the field says *Any dates*, they leave it, and the save fails with no indication of which of nine inputs is wrong. It is the single most-reported problem in Stays.

There is a second, quieter bug in the same place. Because the app previously **omitted** the keys when no window was set, a host who had set a window and then cleared it could not clear it — the old dates simply survived the save.

### 1.2 What to change

Make both fields optional **and nullable**, and treat null as "no bound".

```python
class ShortLetListingSerializer(serializers.ModelSerializer):
    available_from = serializers.DateField(required=False, allow_null=True)
    available_to = serializers.DateField(required=False, allow_null=True)
```

And on the model:

```python
available_from = models.DateField(null=True, blank=True)
available_to = models.DateField(null=True, blank=True)
```

### 1.3 Semantics

| `available_from` | `available_to` | Meaning |
| :--- | :--- | :--- |
| `null` | `null` | Bookable on any future date. |
| `2026-09-01` | `null` | Bookable from 1 Sep 2026 onwards, no end. |
| `null` | `2026-12-31` | Bookable until 31 Dec 2026. |
| `2026-09-01` | `2026-12-31` | Bookable inside that window only. |

Availability checks (`is_available_for_period` on browse, and the validation on `POST /tenant/short-let-bookings/`) must skip whichever bound is null rather than treating it as an empty window. **A listing with no window must not be treated as bookable on no dates** — that failure mode would silently take every open-ended listing off the market.

Keep validating `available_to >= available_from` when both are present.

### 1.4 What Flutter sends now

Both keys are **always** present, with an explicit JSON `null` when the host set no window:

```json
{
  "unit": "UNIT_UUID",
  "nightly_price": "50000.00",
  "minimum_nights": 1,
  "maximum_guests": 2,
  "caution_fee": "0.00",
  "available_from": null,
  "available_to": null,
  "blocked_dates": [],
  "house_rules": "",
  "check_in_notes": "",
  "is_active": true
}
```

Sending null rather than omitting the key is deliberate: it is the only way to *clear* a window that was set previously.

### 1.5 What the app does until this lands

**Confirmed against staging on 2026-09-03.** A save with `available_from: null` is rejected with:

```json
{ "available_from": ["This field may not be null."] }
```

So `ShortLetController.saveListing` now does this, and only this:

1. Save honestly, with nulls.
2. If — and only if — the host chose no window *and* the rejection body names `available_from` or `available_to`, retry **once** with `today → today + 5 years`, which is as close as this backend can get to expressing "no restriction".
3. Tell the landlord, because their listing now carries a bound they did not choose: *"Listed. This server needs a booking window, so yours runs for the next 5 years. You can narrow it any time."*

A host who **did** set dates and had them refused for some other reason gets that rejection unchanged — the retry never overwrites a deliberate choice.

The workaround is self-cancelling: the day §1 ships, step 1 succeeds and steps 2–3 stop running. Delete `_saveOrWidenWindow` then.

---

## 2. Caution fee on a short-let listing

### 2.1 Why

Nigerian short lets very commonly ask for a refundable deposit against damage, and hosts who ask for one have no way to collect it through Oasis. Today they either forgo it or take it in cash outside the platform, which is exactly the off-platform transaction escrow exists to prevent.

The rule is asymmetric and both halves matter:

- **Optional for the host.** Most will not want one, and they must not be made to think about it.
- **Compulsory for the guest.** If the host set one, the stay is not confirmed until the whole amount — nights plus deposit — is paid, and the guest must see the deposit **before they pick dates**, not at checkout.

### 2.2 Model

Add to the short-let listing:

```python
caution_fee = models.DecimalField(
    max_digits=12, decimal_places=2, default=Decimal("0.00")
)
```

Validation: `caution_fee >= 0`. `"0.00"` means *no deposit* and is the default.

Add to the short-let booking:

```python
# Snapshotted at request time, so a host raising their deposit later cannot
# change what an approved guest owes.
caution_fee = models.DecimalField(
    max_digits=12, decimal_places=2, default=Decimal("0.00")
)
caution_fee_refunded_at = models.DateTimeField(null=True, blank=True)
```

Snapshotting is not optional: a booking must be immune to the listing changing under it between request and payment.

### 2.3 Request and response changes

**`POST /api/users/landlord/short-lets/`** accepts `caution_fee` (see §1.4 for the full body). It is always sent, including `"0.00"`, so that clearing a deposit works.

**`GET /api/users/tenant/short-lets/`** and **`GET /api/users/landlord/short-lets/`** each listing gains:

```json
{ "caution_fee": "25000.00" }
```

**`POST /api/users/tenant/short-let-bookings/`** — unchanged request. The response gains `caution_fee`, copied from the listing at that moment.

**Booking totals.** `total_amount` must **include** the caution fee:

```
amount        = nightly_price × nights
platform_fee  = <as today>
caution_fee   = <snapshot>
total_amount  = amount + platform_fee + caution_fee
```

The app renders `total_amount` as the figure to pay and shows `caution_fee` as a separate line beneath it. It never recomputes the total — if these three do not add up server-side, the guest sees a breakdown that does not sum.

**`POST /api/users/tenant/short-let-bookings/{id}/pay/`** charges `total_amount`, deposit included. Vault payments must check the balance against the full total.

### 2.4 Payout, escrow and refund

**The stay payment must not enter escrow.** On a successful payment, credit the landlord's vault immediately with the accommodation amount due to them. Do not make the host wait for checkout, a daily job, or a manual release to receive payment for an approved stay.

The refundable **caution fee** is the only short-let amount held in escrow. It belongs to the tenant unless a valid damage claim is made, and must remain held until the tenant leaves:

| Component | Destination at successful payment | When it becomes available |
| :--- | :--- | :--- |
| `amount` − `platform_fee` | Landlord vault | **Immediately** on successful payment |
| `platform_fee` | Platform revenue account | Immediately, according to the normal payment-accounting flow; it is not a landlord escrow balance |
| `caution_fee` | Tenant caution-fee escrow | On confirmed checkout, when it is returned to the tenant or resolved through a damage claim |

`total_amount` is still charged in full. The allocation is:

```
total_amount = landlord payout + platform_fee + caution_fee
```

Set `caution_fee_refunded_at` when the escrowed caution fee is returned. A booking with a dispute or damage claim must hold the caution fee until it is resolved, but **must not reverse or delay the already-released landlord stay payout** without an explicit refund/recovery operation.

`release_ready_shortlet_escrows` must therefore release **only caution-fee escrows**. It must never credit the landlord's stay payout, because that credit happens at payment success. Rename the job to `release_ready_caution_fee_escrows` when it is safe to do so; retain the old command as a compatibility alias during rollout.

> **Terminology:** this document uses *caution fee* for the refundable tenant security deposit. It is distinct from `platform_fee`, which is Oasis's service fee. Do not label either field simply “fee” in payment or booking responses.

> **Out of scope for v7:** a host-side damage claim endpoint. Until it exists the caution fee returns on confirmed checkout and a host with a genuine claim goes through support. The immediate landlord payout rule still applies.

### 2.5 What the app shows

- **Browse card** — `+ ₦25,000 refundable deposit` under the nightly price.
- **Listing screen** — a sand-toned notice above the details, before the guest picks dates.
- **Booking quote** — a separate line, then a `To pay when approved` total.
- **Booking card** — `Includes ₦25,000 refundable caution fee (₦100,000 for the stay)`, switching to `₦25,000 caution fee returned` once `caution_fee_refunded_at` is set.

---

## 3. Per-unit photos and tour video

### 3.1 Why

Media is attached to the **property** today: one photo set and one optional video per building. A tenant does not rent a building. In a block of eight flats, all eight advertise themselves with the same photograph of the gate, and the one video — if the landlord bothered — is of the compound.

So the app has moved listing media onto the unit:

- The property keeps its photos, and they mean what they should have meant all along: the building, the gate, the street.
- **Each unit gets its own photos and its own tour video**, and the app now **requires the video** before a unit can be created.
- The property-level tour video is **removed from the add-property flow entirely**.

### 3.2 New endpoints

Mirroring the property media endpoints exactly, so there is nothing new to learn:

| Method | Path | Purpose |
| :--- | :--- | :--- |
| `GET` | `/api/users/units/{unit_id}/photos/` | List the unit's photos |
| `POST` | `/api/users/units/{unit_id}/photos/` | Upload one or more (`multipart/form-data`, repeated `photos` field) |
| `DELETE` | `/api/users/units/{unit_id}/photos/{photo_id}/` | Delete one |
| `POST` | `/api/users/units/{unit_id}/video/` | Upload or **replace** the single tour video (`multipart/form-data`, `video` field) |
| `DELETE` | `/api/users/units/{unit_id}/video/` | Delete it |

- **Authentication:** Required. **Roles:** `OWNER`, and only for a unit in a property they own.
- **Limits:** photos ≤ 5MB each, ≤ 12 per unit, `jpg/jpeg/png/webp`. Video ≤ 50MB, `mp4/mov`. These match what the app enforces client-side before uploading.
- **Photo response shape:** identical to `/properties/{id}/photos/` — `[{ "id", "image_url", "created_at" }]`.
- **Video response shape:** `{ "video_url": "https://…" }`.

One video per unit: a `POST` when one already exists replaces it rather than adding a second.

### 3.3 Serializer changes

The unit serializer — everywhere it appears, which is `GET /properties/{id}/`, `GET /properties/{id}/units/`, `POST /properties/{id}/units/batch/`, `GET /tenant/marketplace/`, `GET /tenant/assigned-unit/` and the nested unit on a short-let listing — gains:

```json
{
  "photo_urls": ["https://…", "https://…"],
  "cover_photo_url": "https://…",
  "video_url": "https://…"
}
```

`cover_photo_url` is the first photo, the same rule the property uses. All three may be absent or null; the app treats a missing `video_url` as "this unit has no walkthrough" and says so to the landlord rather than treating the unit as invalid.

**The short-let listing serializer must source `photo_urls` and `video_url` from the unit**, not the property. A guest booking a flat for the weekend wants the room they will sleep in.

### 3.4 Ordering, and why this is not one request

Unit media cannot be sent with `POST /properties/{id}/units/batch/`, because the upload is keyed on a unit id that does not exist until the batch returns. The app therefore:

1. `POST /properties/{id}/units/batch/` — creates the units.
2. For each created unit, matched back to its row **by `unit_number`**, uploads photos then video.
3. Reports partial media failure without discarding the units, which are already saved.

If you would prefer a single multipart request that carries the whole batch with its media, say so — it is a better shape and the app can be changed to match. It is not proposed here because a batch of eight flats with a 50MB video each is a 400MB request, and a dropped connection loses all of it.

### 3.5 Optional, worth considering

`needs_tour_video: true` on the unit serializer, computed server-side, so the landlord's "3 of 8 units have no tour video" line comes from the backend rather than from the app inferring it from a null. Same shape as the existing `needs_photos` on the property. The app works without it.

### 3.6 What is *not* changing

`POST /api/users/properties/` no longer sends a `listing_video` part. Keep accepting it if anything else depends on it; the app will never send one again. The `verification_video` (the private live ownership walkthrough) and the deed are **untouched** — they are anti-fraud evidence, not listing media, and none of this applies to them.

Property photos are still required at creation (minimum 2) and still sent. Say so if you would rather relax that now that units carry their own photos; the app can drop the requirement in one line.

---

## 4. Ratings and reviews

### 4.1 Why

Nothing on Oasis carries a reputation. A tenant choosing an artisan to let into their flat picks from a list of strangers; a guest picking between two short lets has the price and nothing else. This is the single largest missing trust signal in the product, and it is the one that compounds — a marketplace with reviews gets better as it is used, and one without does not.

The requirement that makes it worth anything is that **a review must be attached to a completed transaction**. Anyone can write a review; only someone who actually stayed, or actually had the work done, can write one here.

### 4.2 Model

```python
class Review(models.Model):
    SUBJECT_CHOICES = [
        ("SHORT_LET", "Short let listing"),
        ("ARTISAN", "Artisan"),
        ("LANDLORD", "Landlord"),
        ("TENANT", "Tenant"),
    ]

    author        = models.ForeignKey(User, on_delete=models.CASCADE)
    subject_type  = models.CharField(max_length=20, choices=SUBJECT_CHOICES)
    subject_id    = models.UUIDField()

    # The booking, job or agreement this came out of. This field is the
    # whole point: it is what makes the review evidence rather than opinion.
    transaction_id = models.UUIDField()

    rating   = models.PositiveSmallIntegerField()   # 1–5
    comment  = models.TextField(blank=True)         # ≤ 1000 chars

    response     = models.TextField(blank=True)     # the reviewed party's reply
    responded_at = models.DateTimeField(null=True, blank=True)

    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        # One review per person per transaction. Not per subject: a guest who
        # stays in the same flat three times has three things to say.
        constraints = [
            models.UniqueConstraint(
                fields=["author", "transaction_id"], name="one_review_per_transaction"
            )
        ]
```

### 4.3 Endpoints

**`GET /api/users/reviews/?subject_type=SHORT_LET&subject_id=<uuid>&limit=20`**

- **Authentication:** Required. Any role — reviews are public to signed-in users.
- Newest first. Paginated envelope (`{"results": [...]}`) or a bare list; the app reads either.

```json
{
  "results": [
    {
      "id": "…",
      "subject_type": "SHORT_LET",
      "subject_id": "…",
      "rating": 5,
      "comment": "Exactly as described. The host met me at the gate.",
      "author_name": "Chidi O.",
      "author_role": "TENANT",
      "response": "Thank you — you were welcome.",
      "responded_at": "2026-09-02T10:00:00Z",
      "created_at": "2026-09-01T18:22:00Z"
    }
  ]
}
```

> `author_name` must **never** be an email address. Reviews are public and the author did not agree to publish their address. A shortened form — first name plus an initial — is what the app renders and expects.

**`GET /api/users/reviews/summary/?subject_type=…&subject_id=…`**

```json
{
  "average_rating": 4.8,
  "review_count": 12,
  "distribution": { "5": 9, "4": 2, "3": 1, "2": 0, "1": 0 }
}
```

`average_rating` must be **null**, not `0`, when `review_count` is 0. The app draws a very deliberate distinction between *unrated* and *badly rated*, and a zero would put a one-star badge on every new host's listing. `distribution` is optional; the bars are simply not drawn without it.

**`POST /api/users/reviews/`**

```json
{
  "subject_type": "SHORT_LET",
  "subject_id": "LISTING_UUID",
  "transaction_id": "BOOKING_UUID",
  "rating": 5,
  "comment": "Exactly as described."
}
```

Validate, and reject with a sentence the app can show as written:

| Check | Rejection |
| :--- | :--- |
| Author was party to `transaction_id` | `403` — "You can only review a stay you booked." |
| The transaction has completed | `400` — "You can review this once your stay is over." |
| `subject_id` matches the transaction's subject | `400` — "That review does not belong to this booking." |
| No existing review by this author for it | `409` — "You have already reviewed this." |
| `1 <= rating <= 5` | `400` |

**`POST /api/users/reviews/{id}/respond/`** — `{"response": "…"}`. Only the reviewed party. One response per review; a second replaces it.

### 4.4 What "completed" means per subject

| `subject_type` | `transaction_id` is | Reviewable when | Author must be |
| :--- | :--- | :--- | :--- |
| `SHORT_LET` | short-let booking id | status `PAID` **and** `check_out` is in the past | the booking's tenant |
| `ARTISAN` | fix job id | status `COMPLETED` | the job's tenant |
| `LANDLORD` | agreement id | agreement `EXECUTED` | the agreement's tenant |
| `TENANT` | agreement or short-let booking id | same as above | the landlord/host |

`subject_id` for `SHORT_LET` is the **listing** id, not the unit and not the booking.

### 4.5 Denormalised aggregates on existing payloads

To avoid a summary request per card on a scrolling list, add to serializers the app already fetches:

| Serializer | Add |
| :--- | :--- |
| Short-let listing (tenant browse **and** landlord list) | `average_rating` (nullable), `review_count` |
| Artisan profile (`/tenant/fix/artisans/`, `/landlord/fix/artisans/`, `/artisans/me/`) | `average_rating` (nullable), `review_count` |
| Short-let booking | `has_review: true/false` — whether **this caller** has already reviewed it |

`has_review` is what stops the app offering a form the backend would reject as a duplicate.

### 4.6 What the app does until this lands

`ReviewService` treats a `404` on either read endpoint as "no reviews yet" and renders an unrated subject. The booking and job screens still show their "Rate this stay" / review prompt; posting one surfaces the backend's error. Nothing else on those screens is affected.

---

## 5. Conversation on a paid short-let booking

### 5.1 Why

A confirmed short let has a set of practical questions attached to it — what time the guest lands, where the key is, what the gate code is — and today there is nowhere to ask them. Guests have been writing them into the booking-request note, which nobody reads again after approval, and hosts have been putting phone numbers in `check_in_notes`.

Messaging already exists and already has exactly the right shape: a thread exists because a relationship exists, never because someone went looking for a person.

### 5.2 What to add

A third context on the existing conversation model:

```python
CONTEXT_CHOICES = [
    ("APPLICATION", "Application"),
    ("TENANCY", "Tenancy"),
    ("SHORT_LET", "Short let booking"),   # new
]
```

**`POST /api/users/conversations/`** accepts a fourth identifier:

```json
{ "short_let_booking": "BOOKING_UUID" }
```

Idempotent, as the others are: a second call returns the existing thread.

**Gate it on payment.** Open a thread only for a booking whose status is `PAID` or `DISPUTED`. A pending or approved-unpaid request is not yet a relationship, and a channel to a host before one exists is a channel to a stranger. Reject anything else with a sentence worth reading:

> `403` — "You can message the host once your stay is paid for."

**Close it** — `status: "CLOSED"`, read-only — 7 days after checkout, alongside the escrow release job. The history stays readable; it is evidence if the stay is ever disputed.

Conversation payloads for this context should carry the property and unit as they do today, so the inbox row reads the same.

### 5.3 Optional, and worth it

`conversation_id` on the short-let booking serializer once a thread exists. The app reads it (`ShortLetBooking.conversationId`) and would use it to badge unread messages on the booking card. It works without it — the button opens or creates the thread either way.

### 5.4 Notifications

Add `SHORT_LET_MESSAGE_RECEIVED` to the notification types, fanned out like the existing message notifications.

---

## 6. Summary of every wire change

### New endpoints

| Method | Path |
| :--- | :--- |
| `GET`/`POST` | `/api/users/units/{unit_id}/photos/` |
| `DELETE` | `/api/users/units/{unit_id}/photos/{photo_id}/` |
| `POST`/`DELETE` | `/api/users/units/{unit_id}/video/` |
| `GET`/`POST` | `/api/users/reviews/` |
| `GET` | `/api/users/reviews/summary/` |
| `POST` | `/api/users/reviews/{id}/respond/` |

### Changed request bodies

| Endpoint | Change |
| :--- | :--- |
| `POST /landlord/short-lets/` | `caution_fee` added; `available_from`/`available_to` now accept `null` |
| `POST /conversations/` | `short_let_booking` accepted as a fourth identifier |
| `POST /properties/` | `listing_video` part no longer sent |

### Changed response payloads

| Serializer | Added fields |
| :--- | :--- |
| Short-let listing | `caution_fee`, `average_rating` (nullable), `review_count`, `photo_urls`/`video_url` sourced from the unit |
| Short-let booking | `caution_fee`, `caution_fee_refunded_at`, `has_review`, `conversation_id`; `total_amount` now includes the deposit. Accommodation payout is immediate; only the caution fee is escrowed. |
| Unit (everywhere it appears) | `photo_urls`, `cover_photo_url`, `video_url`, optionally `needs_tour_video` |
| Artisan profile | `average_rating` (nullable), `review_count` |
| Conversation | `context_type` may now be `SHORT_LET` |

### New notification types

- `SHORT_LET_MESSAGE_RECEIVED`
- `REVIEW_RECEIVED` (optional — the app does not depend on it)

---

## 7. Document the short-let booking status vocabulary

### 7.1 The problem

The enum table in the guide (§"Enums") lists a status vocabulary for users, properties, agreements, payments and vault top-ups. **It lists none for short-let bookings.** The app's `ShortLetBookingStatus.fromString` was therefore written from the prose of the Short Let section, and covers:

`PENDING` · `REQUESTED` · `APPROVED` · `PAID` · `ESCROW` · `CONFIRMED` · `REJECTED` · `DECLINED` · `CANCELLED` · `CANCELED` · `DISPUTED` · `EXPIRED`

Anything else falls through to an internal `unknown`. That is the safe default — it never guesses "paid" or "approved", because both unlock actions involving money and travel — but it is a **dead end** for the guest: paying, cancelling, messaging and disputing are all gated on a recognised status, so an unrecognised one leaves a booking on screen with no buttons under it and no explanation.

**This was seen in the wild, and the missing string turned out to be `IN_ESCROW`.** The app knew `ESCROW` — the spelling in the guide's Payment status enum — but staging sends `IN_ESCROW`, the spelling the guide uses only once, in prose, at the tenancy-agreement section. So a stay that had been paid for successfully rendered as unreadable: no check-in notes released to the guest, no "Message the host" button, no card on their dashboard, and no way to raise a problem while the money was still held. Nothing was wrong with the payment or with Paystack.

That is the cost of the gap, and it will recur: `RELEASED` (the terminal status after the caution-fee release path completes) was equally unmapped, which would have made **every past stay** unreadable after checkout. Both are now handled, but only because one of them broke visibly.

### 7.2 Canonical enum row to add

Add this row to the guide's enum table, using the complete set of values emitted by `ShortLetBooking.status`. This is the app's current compatibility mapping; backend must confirm that no other persisted or emitted values exist.

| Value | App state |
| :--- | :--- |
| `PENDING`, `REQUESTED` | Awaiting host |
| `APPROVED` | Approved, awaiting payment |
| `PAID`, `CONFIRMED` | Paid; landlord payout released and stay active |
| `ESCROW`, **`IN_ESCROW`** | Legacy/transition state: a caution fee is held; not a hold on the stay payout |
| `RELEASED`, `COMPLETED`, `CHECKED_OUT` | Stay complete; caution fee released or awaiting its recorded resolution |
| `DISPUTED` | Under review |
| `REJECTED`, `DECLINED` | Declined |
| `CANCELLED`, `CANCELED` | Cancelled |
| `EXPIRED` | Expired unpaid |

**Please confirm this list is complete**, and in particular whether any of these exist — the app has no case for them and would render a booking unreadable:

`PAYMENT_FAILED` · `FAILED` · `AWAITING_PAYMENT` · `PENDING_PAYMENT` · `PROCESSING` · `REFUNDED`

**Canonical choice:** stop emitting `ESCROW`. **`IN_ESCROW` is the canonical spelling** because it is the value observed from staging. Use it consistently in the enum table, database transition code, payment serializer and booking serializer. The app accepts `ESCROW` only as a legacy read alias; new writes and responses must use `IN_ESCROW`.

For each, the app needs to know two things beyond the name:

| Question | Why it matters |
| :--- | :--- |
| Has money moved? | Gates check-in notes, messaging, disputes and the dashboard card. |
| Can the tenant still pay, or still cancel? | Gates the two buttons. A state where neither is true must be terminal, or the guest is stuck. |

### 7.3 Specifically: what happens to a booking whose payment fails

`POST /tenant/short-let-bookings/{id}/pay/` can fail at the provider. The guide does not say what the booking's status becomes. Three behaviours are possible and the app must be told which:

1. The booking stays `APPROVED` and the tenant may simply try again — **preferred**, and the app already handles it with no change.
2. The booking moves to a distinct failure status, and the tenant may still retry inside the 24-hour window.
3. The booking moves to a terminal failure status and the tenant must ask again from scratch.

If it is (2) or (3), name the status and say whether `POST .../pay/` is still accepted on it.

### 7.4 What the app does now

Unchanged in substance — an unrecognised status still unlocks nothing, which is the correct conservative behaviour. What changed is that it stops being silent:

- `ShortLetBookingStatus.fromString` logs the unrecognised value: `⚠️ [SHORTLET] Unrecognised booking status "X"`.
- `ShortLetBooking.rawStatus` keeps the backend's word verbatim.
- The booking card renders it — *"The server calls this booking "Payment failed", which this version of the app does not recognise"* — with the refresh and support routes, instead of a bare pill.
- The pill reads **"Status unclear"** rather than the previous **"Processing"**. The old word described a payment moving through a provider, which is not what the state is, and it sent people looking at Paystack for a bug that was in the Flutter enum.

---

## 8. Two things worth pushing back on

Both of these are places where the app has made a judgement call that is cheap to reverse, and you may have better information:

1. **Unit tour video is required at creation, photos are not.** The video is enforced by the app before a unit batch can be saved; unit photos are encouraged but optional. That split follows the product decision as stated, but the backend should probably not enforce the video — a landlord importing a twelve-flat building through a future bulk path would be blocked by it. **Recommendation: accept units without a video, and let the app own the requirement.** That is what it currently assumes.

2. **The caution fee refunds automatically.** With no damage-claim endpoint, every deposit returns on confirmed checkout regardless. That is the honest behaviour for v1 — the alternative is holding guests' money with no defined way to release it — but it does mean a host with a real claim has only the support route. If you want the claim endpoint in this release, it is a sibling of the existing dispute flow and the app will need a small host-side sheet.

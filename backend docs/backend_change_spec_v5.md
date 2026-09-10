# Oasis Backend Change Specification — v5

> **Audience:** Backend developer implementing on the Django API (`landa_os`, `users` app).
>
> **Companion document:** `flutter_api_guide (13).md` in this folder describes the API as it exists today, including §7B Artisan Fix V1. This document describes only what **changes**. When this ships, fold it into the guide and bump it to `(14)`.
>
> **Base URL (staging):** `https://landa-os-staging.onrender.com/api/users`
>
> **Status:** One blocking gap, two clarifications, one small quality-of-life change. The Flutter Fix feature is built and shipped against §7B as written — see [§6 Fallback Behaviour](#6-fallback-behaviour-what-the-app-does-today) for what it does in the meantime. Only §1 actually blocks a landlord from completing a documented flow.

---

## 1. Blocking: A Landlord Cannot Look Up An Artisan

### The problem

`POST /api/users/units/{unit_id}/artisan-recommendations/` takes an `artisan_id`:

```json
{ "category": "PLUMBING", "artisan_id": "artisan-profile-uuid" }
```

There is no endpoint an `OWNER` may call that returns one. The only artisan directory in the API is:

| Feature | Method | Path | Roles |
| :--- | :--- | :--- | :--- |
| Tenant Fix artisan list | `GET` | `/api/users/tenant/fix/artisans/` | `TENANT` |

A landlord calling it gets `403`. So the recommendation endpoint asks the landlord for an identifier the API gives them no way to obtain. As specified, the whole landlord half of Fix is unreachable from any client.

This is not a Flutter problem — no client can implement §7B's landlord flow as written.

### What to add

`GET /api/users/landlord/fix/artisans/`

- **Authentication:** Required
- **Roles:** `OWNER`, verified
- **Query parameters:**
  - `category` — required, one of the artisan category values.
  - `search` — optional, case-insensitive match on artisan name or location.

Returns the same serializer as the tenant list, with two differences:

- `phone` is **always `null`**. A landlord has no accepted job with this artisan, and nothing about recommending someone should hand out their number. The rule that a phone number is released by acceptance must not be quietly weaker on the landlord's side.
- `is_recommended` is **absent**, or `false`. It is a property of a tenant's unit, not of a landlord's browse.

```json
[
  {
    "id": "artisan-profile-uuid",
    "full_name": "Ada Fixer",
    "email": "artisan@example.com",
    "phone": null,
    "category": "PLUMBING",
    "category_label": "Plumbing",
    "location": "Lekki Phase 1",
    "bio": "Reliable plumber.",
    "years_of_experience": 5,
    "verification_status": "VERIFIED",
    "is_active": true,
    "recently_online": true
  }
]
```

Same filtering as the tenant list: **verified, active artisans only**. A landlord must not be able to recommend somebody a tenant would then be refused when booking — that failure surfaces as a broken app at the worst possible moment, when something in the flat is broken.

### The acceptable alternative

If you would rather not add a route, widening `GET /api/users/tenant/fix/artisans/` to accept `OWNER` works just as well, provided:

- `unit` is rejected for an owner, or scoped to units they own.
- `phone` stays `null` for them.

Say which you chose. The app tries `/landlord/fix/artisans/` first and falls back to `/tenant/fix/artisans/` on a `404`/`403`/`405`, so either lands working — but the fallback is a workaround, not the intended shape, and should come out once this is settled.

---

## 2. Clarification: The Fix Job Response Body

### The problem

§7B documents every **request** body and not one **response** body. The app therefore reads a job defensively — every field optional, unknown values degrading to something that unlocks nothing. That is the right way to write a client, but it means two things are currently guesses:

1. **The status vocabulary.** The app accepts `PENDING`/`REQUESTED`, `ACCEPTED`, `QUOTED`/`AWAITING_PAYMENT`, `PAID`/`IN_PROGRESS`/`ESCROW`, `DONE`/`AWAITING_CONFIRMATION`/`MARKED_DONE`, `COMPLETED`/`RELEASED`, `DECLINED`/`REJECTED`, `CANCELLED`. Anything else resolves to `unknown`, which offers the tenant no action at all — no pay button, no confirm button, no cancel.
2. **Whether the job is nested.** The app reads a job from the response root, or from `request`, `job` or `data` if the root carries one of those keys.

If the real vocabulary is different, a tenant with a perfectly good quoted job sees "Processing" and no way to pay it.

### What to document

Please publish the response body for `GET/POST /api/users/tenant/fix/requests/` and `GET /api/users/artisan/requests/`, and the exact status values. The app already reads all of these names, so a payload in this shape needs no client change:

```json
{
  "id": "job-uuid",
  "unit": "unit-uuid",
  "unit_number": "A1",
  "property_name": "Sunset House",
  "artisan": {
    "id": "artisan-profile-uuid",
    "full_name": "Ada Fixer",
    "category": "PLUMBING",
    "category_label": "Plumbing",
    "location": "Lekki Phase 1",
    "phone": null
  },
  "tenant_name": "Bola Ade",
  "tenant_email": "tenant@example.com",
  "tenant_phone": null,
  "description": "Kitchen sink is leaking.",
  "urgency": "URGENT",
  "status": "QUOTED",
  "quoted_amount": "10000.00",
  "platform_fee": "500.00",
  "total_amount": "10500.00",
  "payment_id": "payment-uuid",
  "reference": "AJ-REFERENCE",
  "authorization_url": "https://checkout.paystack.com/...",
  "access_code": "...",
  "created_at": "2026-08-31T10:00:00Z",
  "accepted_at": null,
  "completed_at": null
}
```

Three fields matter more than the rest:

- **`artisan.phone`** — `null` until this artisan accepts *this* job, then their number. The app renders its absence as "you'll see their phone number once they accept", so `""` and the field being missing are both treated as withheld. Please send `null` rather than omitting it, so the distinction stays explicit.
- **`total_amount`** — the figure the tenant is charged. The app never recomputes it from `quoted_amount + platform_fee`; it displays and charges what you send. If it is absent the app falls back to `quoted_amount`, which would under-quote the tenant by the fee, so it should always be present once a quote exists.
- **`tenant_phone`** — mirror the artisan rule: withheld until the artisan accepts. An artisan who has not taken the job has no reason to hold the tenant's number. The app already hides it and says why.

### The one place the app deviates from the documented order

§7B has the artisan mark a job `done`, then the tenant `complete` it. The app offers the tenant "Confirm work is done" from the moment the job is **paid**, not only once the artisan has marked it done.

That is deliberate. Gating the release of the tenant's own money on the artisan remembering to press a button strands both of them: the work is finished, the tenant can see it is finished, and the artisan is unpaid. The `done` status still drives the prompting — that is when the tenant is actively asked — but it is not what makes the action exist.

**If `POST /tenant/fix/requests/{job_id}/complete/` rejects a `PAID` job that is not yet `DONE`, please relax it to accept one.** The tenant is releasing money they already paid, to the artisan they already chose; there is no one it can harm. If you would rather keep the restriction, say so and the app will gate on `DONE` instead — but a tenant who cannot pay a finished job will contact support, and that is the failure mode to weigh.

---

## 3. Clarification: `POST /tenant/fix/requests/{job_id}/pay/`

The app sends this exactly as §7B documents, with the `Idempotency-Key` header, and treats it the same way it treats rent and short-let payments. Two things worth confirming, both about not charging somebody twice:

1. **The idempotency key is per payment intent, not per request.** A retry after a timeout reuses the same key; a fresh deliberate attempt after a failure gets a new one. Please confirm the key is honoured on this endpoint the way it is on `POST /payments/`.
2. **A `VAULT` payment settles server-side.** There is no checkout to fall back on, so the app treats "200 but the job is not paid" as a failure and tells the tenant nothing was charged. If a vault payment can legitimately return `200` in a not-yet-settled state, say so — that message would then be wrong.

Response shape as in §2: the app reads the updated job, including `payment_id`, `reference` and (for `CARD`) `authorization_url`.

---

## 4. Small: Let Registration Read The Category List

`GET /api/users/artisans/categories/` is `Yes + verified`.

Artisan registration happens at `POST /api/users/register/`, which is public — there is no token, so the sign-up form cannot fetch the list it is asking the user to choose from. The app therefore ships the four documented values hard-coded:

```
PLUMBING, ELECTRICIAN, GENERATOR_REPAIR, CLEANER
```

The moment a fifth category is added on the backend, nobody can register for it until the app ships again.

**Please drop the auth requirement on `GET /artisans/categories/`,** or expose an unauthenticated mirror of it. It is a static list of four public strings; there is nothing in it worth gating. Everywhere else in the app already reads the live list — the artisan's own profile editor, the tenant's Fix browse, the landlord's recommendation picker — and only registration is stuck with the constants.

Until then the app degrades safely: it renders the four defaults and replaces them with the live list on the first authenticated screen. An unknown category value that arrives later is prettified for display (`AC_REPAIR` → "Ac Repair") rather than dropped.

---

## 5. Confirmations, No Change Requested

Recorded so they do not get changed by accident — the app depends on each:

- **`GET /vault/`, `/vault/transactions/`, `/vault/withdrawals/` include `ARTISAN`.** An artisan's earnings screen is the vault ledger. Good as is.
- **`POST /vault/topups/` is `TENANT` only.** Correct — an artisan's vault fills from completed jobs, and the app never offers them "Add money". This is why role checks in the app now test `role == TENANT` rather than `role != OWNER`; the loose form would have offered an artisan an endpoint that refuses them.
- **`GET /profile/` returns `"role": "ARTISAN"`.** The app routes the whole navigation shell off this. An artisan sees their job queue and their earnings, and none of the rental app — no marketplace, no rent, no agreements, no short lets.
- **Artisans use the same consent + NIN flow.** The app sends them through the identical `POST /consents/` → `POST /verify/` → `GET /verify/status/` screens as owners and tenants, with no artisan-specific branch.
- **Recommendation replace-on-POST.** One recommendation per (unit, category); posting again overwrites. The app relies on this and has no separate update call.
- **`DELETE /units/{unit_id}/artisan-recommendations/` takes a JSON body** naming the category. Unusual for a DELETE, and the app's HTTP client had to be extended to send one, but it is the right shape given the path identifies only the unit. Please keep it.

---

## 6. Fallback Behaviour: What The App Does Today

Nothing here blocks a release except §1, and even that has a workaround in place. For the record, so nobody spends time re-deriving it:

| Gap | What the app does now |
| :--- | :--- |
| §1 landlord directory | Calls `/landlord/fix/artisans/`; on `404`/`403`/`405` falls back to `/tenant/fix/artisans/`. If both refuse, the picker shows "Nobody listed yet" and the landlord can set recommendations later. A `500` is **not** retried — it means the route exists and failed, and retrying elsewhere would report the wrong reason. |
| §2 status vocabulary | Unknown statuses resolve to `unknown`, which offers no action. Nothing is ever assumed paid or accepted. |
| §2 tenant completion | Offered from `PAID` onwards, prompted at `DONE`. |
| §4 categories at sign-up | Four hard-coded defaults, replaced by the live list once authenticated. |

---

## 7. Test Coverage On The App Side

For reference when verifying the backend against the client. These are in `test/fix_flow_test.dart` and `test/fix_screens_test.dart`:

- Request, quote, pay, and recommendation bodies match §7B exactly, field for field.
- `Idempotency-Key` is stable across a retry of one payment and changes for a new attempt.
- A `VAULT` payment returning a non-paid status is surfaced as a failure that says nothing was charged.
- `INSUFFICIENT_VAULT_BALANCE` surfaces the shortfall and offers a top-up.
- An artisan's phone is `null` before acceptance and present after; `""` is treated as withheld.
- An unrecognised status unlocks no action.
- Trade fields are sent on registration **only** for `role: "ARTISAN"`.
- The landlord directory fallback fires on `404` and not on `500`.

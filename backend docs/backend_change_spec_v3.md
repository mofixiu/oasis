# Landa OS Backend Change Specification — v3

> **Audience:** Backend developer implementing on the Django API (`landa_os`, `users` app).
>
> **Companion document:** `flutter_api_guide (8).md` in this folder describes the API as it exists today. This document describes only what **changes**. Where a section says "current behaviour", it is quoting that guide. When this batch ships, fold these sections into the guide and bump it to `(9)`.
>
> **Base URL (staging):** `https://landa-os-staging.onrender.com/api/users`
>
> **Status:** Requested by product ownership. The Flutter app has already been built against this contract and ships behind graceful fallbacks — see [§9 Fallback Behaviour](#9-fallback-behaviour-what-the-app-does-before-this-ships). Nothing below is blocking a release; everything below is needed for the feature to actually work.

---

## 1. What Changes, And Why

Three changes, in implementation order. The order is not arbitrary — the rent schedule (§4) is what the reminders (§5) fire against, and the tenant vault (§2, §3) is what the reminders are telling tenants to fill.

| # | Change | Type | Why it is ordered here |
| :--- | :--- | :--- | :--- |
| 1 | [Tenant vault + top-ups](#2-the-vault-becomes-everyones) | Structural | Widens an existing model to a second role. Everything else assumes it. |
| 2 | [Pay rent from the vault](#3-paying-rent-from-the-vault) | New payment source | Depends on §2. Small, self-contained. |
| 3 | [Rent schedules](#4-rent-schedules) | New data | The dates §5 fires against. Nothing to remind about without it. |
| 4 | [Rent reminders — in-app and email](#5-rent-reminders) | Background job | Depends on §4. |

### Mapping To The Original Request

| Requested as | Covered in |
| :--- | :--- |
| "tenant vault (save money and pay, same flow)" | §2, §3 |
| "it should show when the rent would be due" | §4 |
| "when the rent is about to be due it send notifications and mail" | §5 |
| "6 months 3 months" | §5.2 — the reminder ladder |

The other two items in the same request — moving the profile avatar to the left of the app bar, and turning the landlord's property list into a box that opens its own page — are pure client changes and are already done. They need nothing from the backend.

### The One Behavioural Change To Read First

**`GET /vault/` is currently `OWNER`-only. It stops being.** Every authenticated, verified user gets a vault. A landlord's fills when escrow releases; a tenant's fills when they top it up and drains when they pay rent from it or withdraw it.

This is the same table, the same ledger and the same withdrawal endpoints — not a parallel "tenant wallet". The Flutter app already calls these paths for both roles with no branching, which is only correct if the backend scopes by `request.user` rather than by role.

---

## 2. The Vault Becomes Everyone's

### 2.1 Role Scope

Change the permission on the existing vault endpoints from `OWNER` to any authenticated, verified user. Scope every query to `request.user`'s own vault — a role check is not what keeps one user out of another's money, and never was.

| Endpoint | Was | Becomes |
| :--- | :--- | :--- |
| `GET /vault/` | `OWNER` | Any verified user |
| `GET /vault/transactions/` | `OWNER` | Any verified user |
| `GET /vault/withdrawals/` | `OWNER` | Any verified user |
| `POST /vault/withdrawals/` | `OWNER` | Any verified user |

A tenant withdrawing is not an edge case to design around: it is a tenant who saved for rent and then moved out, or changed their mind. The money is theirs. The existing `PAYOUT_ACCOUNT_REQUIRED` gate applies unchanged.

**Create the vault lazily.** A tenant who has never topped up must still get a `200` with a zero balance from `GET /vault/`, not a `404`. The app renders a zero balance as an invitation to add money; a `404` renders as "something is broken".

### 2.2 One New Field On `GET /vault/`

Add `total_spent` — lifetime rent paid out of this vault. `"0.00"` for a landlord, who never spends from theirs.

```json
{
  "id": "VAULT_UUID",
  "available_balance": "150000.00",
  "pending_withdrawal_balance": "0.00",
  "total_credited": "150000.00",
  "total_withdrawn": "0.00",
  "total_spent": "0.00",
  "currency": "NGN",
  "created_at": "2026-08-24T17:00:00Z",
  "updated_at": "2026-08-24T17:05:00Z"
}
```

Everything else on this payload is unchanged. The app tolerates `total_spent` being absent.

### 2.3 New Ledger Sources

`GET /vault/transactions/` gains two `source_reference` prefixes. The row shape does not change.

| `transaction_type` | `source_reference` | `description` | When |
| :--- | :--- | :--- | :--- |
| `CREDIT` | `topup:TU-1A2B3C4D` | `Vault top-up TU-1A2B3C4D` | A tenant top-up settles |
| `DEBIT` | `rent_payment:LR-9F8E7D6C` | `Rent for Unit 4B` | Rent paid from the vault |

The app renders `description` verbatim, so write it for a person to read.

### 2.4 New: `POST /vault/topups/`

Starts a tenant top-up and returns provider checkout data. Same Paystack flow as rent payment — deliberately, so a tenant who has paid rent once already recognises the screen.

- **Authentication:** Required
- **Roles:** `TENANT` (a landlord's vault fills from escrow; there is nothing for them to top up)
- **HTTP Method:** `POST`
- **Path:** `/api/users/vault/topups/`
- **Content-Type:** `application/json`
- **Required header:** `Idempotency-Key`

#### Request Body

```json
{
  "amount": "150000.00"
}
```

#### Response `201 Created`

```json
{
  "id": "TOPUP_UUID",
  "amount": "150000.00",
  "currency": "NGN",
  "status": "PENDING",
  "reference": "TU-1A2B3C4D",
  "authorization_url": "https://checkout.paystack.com/abc123",
  "access_code": "abc123",
  "provider_reference": "TU-1A2B3C4D",
  "failure_reason": "",
  "created_at": "2026-08-27T09:00:00Z",
  "completed_at": null
}
```

#### Status Values

| Status | Means |
| :--- | :--- |
| `PENDING` | Created; provider checkout not completed. **The vault is not credited.** |
| `SUCCEEDED` | Provider confirmed and the vault has been credited. |
| `FAILED` | The charge did not go through. Nothing was taken. |
| `ABANDONED` | Checkout was closed without paying. |

The app treats any value it does not recognise as still in flight and keeps asking. It will never show "money added" for an unrecognised status — do not add a synonym for `SUCCEEDED` without telling the client.

**Credit the vault exactly once, on provider confirmation, inside the same transaction that flips the status to `SUCCEEDED`.** Never on `POST`, and never twice when the webhook and the verify call race — which they will.

#### Idempotency

`Idempotency-Key` is scoped per user. The app generates one key per top-up *intent* and reuses it across every retry of that intent, so a request that times out and is tried again must return the **same** top-up, not a second one. A deliberately new top-up carries a new key.

#### Common Errors

```json
{
  "code": "AMOUNT_TOO_SMALL",
  "detail": "Enter at least ₦1,000 to top up your vault.",
  "field": "amount"
}
```

```json
{
  "code": "AMOUNT_TOO_LARGE",
  "detail": "The most you can add at once is ₦5,000,000.",
  "field": "amount"
}
```

```json
{
  "code": "PROVIDER_UNAVAILABLE",
  "detail": "Paystack could not be reached."
}
```

The limits above are placeholders — set whatever the provider and compliance actually require, and keep `detail` a sentence the app can show as-is, per the v2 §2.1 error envelope.

### 2.5 New: `POST /vault/topups/{id}/verify/`

Confirms a top-up with the provider after checkout closes.

- **Authentication:** Required
- **Roles:** `TENANT`
- **HTTP Method:** `POST`
- **Path:** `/api/users/vault/topups/{id}/verify/`

#### Request Body

```json
{
  "reference": "TU-1A2B3C4D"
}
```

The body may be empty; fall back to the top-up's stored reference. Response is the same object as §2.4, with the settled status.

**This exists because the in-app checkout browser has no redirect back into Flutter.** The app calls it the moment the user returns to the app, and again if they tap "I have completed checkout". Both are the same call and it must be safe to make repeatedly: verifying an already-`SUCCEEDED` top-up returns it unchanged and credits nothing further.

### 2.6 New: `GET /vault/topups/`

Cursor-paginated list of the tenant's top-ups, same envelope as `GET /vault/transactions/`. Not yet consumed by the app — the ledger already tells the story — but specified here so the resource is complete.

---

## 3. Paying Rent From The Vault

### 3.1 `POST /payments/` Gains A `source`

Current behaviour: `POST /payments/` with `{"agreement": "..."}` creates a `PENDING` payment and returns a Paystack `authorization_url`.

Add an optional `source` field:

```json
{
  "agreement": "AGREEMENT_UUID",
  "source": "VAULT"
}
```

| `source` | Behaviour |
| :--- | :--- |
| `CARD` (default, and the behaviour when the field is absent) | Unchanged. Returns `PENDING` plus checkout data. |
| `VAULT` | Debits the tenant's vault by `total_amount` and returns the payment already in `ESCROW`. No `authorization_url`. |

`VAULT` also requires the `Idempotency-Key` header, scoped per user, for the same reason top-ups do.

#### Response `201 Created` (source `VAULT`)

The existing payment payload, with:

- `"status": "ESCROW"`
- `"authorization_url": null`
- `"access_code": null`
- `"paid_at"` set to now
- `"provider": "VAULT"`

**Debit and escrow in one transaction.** If the debit fails, nothing is created. There is no checkout to fall back to here — a payment record that exists without a debit is a rent bill the tenant thinks they have paid.

The app treats *any* non-`ESCROW` response to a `VAULT` payment as a failure and tells the tenant their vault has not been charged. Make that true.

#### Common Errors

```json
{
  "code": "INSUFFICIENT_VAULT_BALANCE",
  "detail": "Your vault balance does not cover this rent payment.",
  "field": "source"
}
```

```json
{
  "code": "PAYMENT_ALREADY_STARTED",
  "detail": "A payment for this agreement is already in progress."
}
```

The existing gates are unchanged and still apply first: the agreement must be `EXECUTED` with `pay_rent_unlocked`, and the caller must be its tenant.

### 3.2 Escrow Downstream Is Unchanged

A vault-funded payment is a normal escrow payment from the moment it exists. The 48-hour lock, disputes, release, and the credit into the landlord's vault all behave exactly as they do for a card payment. A refund returns money to the tenant's **vault**, not their card — it came from the vault, and it goes back there.

---

## 4. Rent Schedules

### 4.1 The Problem

The app can currently answer "is rent owed right now?" from `rent_payment.status`. It cannot answer "when is my next rent due?", which is the question a tenant with a vault actually has — the whole reason to save is that the bill is months away and large.

### 4.2 New: `rent_schedule` On The Agreement

Add a `rent_schedule` block to every agreement payload — `GET /agreements/`, `GET /agreements/{id}/`, and anywhere else an agreement is serialised. Null (or absent) on agreements that are not `EXECUTED`.

```json
{
  "id": "AGREEMENT_UUID",
  "status": "EXECUTED",
  "rent_payment": { "status": "PAID", "total_amount": "472500.00" },
  "rent_schedule": {
    "plan": "ANNUAL",
    "next_due_date": "2027-06-30",
    "next_amount_due": "472500.00",
    "days_until_due": 307,
    "is_overdue": false,
    "instalments_paid": 1,
    "instalments_total": 1
  }
}
```

| Field | Type | Notes |
| :--- | :--- | :--- |
| `plan` | string | `ANNUAL` \| `SIX_MONTHLY` \| `QUARTERLY` \| `MONTHLY`. Default `ANNUAL`. |
| `next_due_date` | ISO date or null | Null when nothing more is owed on this agreement. The app then shows no bill at all. |
| `next_amount_due` | decimal string | Including platform fee — it is what the tenant will actually be charged. |
| `days_until_due` | integer or null | Negative when overdue. **Compute this server-side.** |
| `is_overdue` | boolean | The authority on lateness. |
| `instalments_paid` | integer | 0 for a plan on its first payment. |
| `instalments_total` | integer | 1 for `ANNUAL`, 2 for `SIX_MONTHLY`, 4 for `QUARTERLY`, 12 for `MONTHLY`. |

**`days_until_due` and `is_overdue` are server-computed on purpose.** The tenancy's timezone, any grace period, and what counts as a day are all backend facts. The app falls back to subtracting dates when the fields are missing, but that fallback does not know about grace periods and will disagree with the reminder emails at the edges.

**`is_overdue` outranks the date.** The app trusts it even when `next_due_date` is in the future — that is how a re-scheduled instalment or a grace period is expressed.

### 4.3 Plans

`plan` is on the agreement, set when the landlord creates it. For this batch, defaulting every agreement to `ANNUAL` and hard-coding `instalments_total: 1` is a complete and correct implementation — Nigerian tenancies are overwhelmingly annual, and the app renders the other plans correctly the moment they appear.

If plan selection is added later, `POST /agreements/` takes an optional `rent_plan` field with the same four values. The Flutter client already parses every one of them, and accepts `YEARLY`, `BIANNUAL` and `THREE_MONTHLY` as synonyms.

---

## 5. Rent Reminders

### 5.1 What This Is

A scheduled job that tells a tenant their rent is coming, in the app and by email, far enough ahead that they can do something about it. Without it, the vault is a savings account nobody remembers to fill.

Run it **once a day**. There is nothing here that needs to be more frequent, and a job that runs hourly will send duplicates the first time somebody's clock moves.

### 5.2 The Ladder

For every `EXECUTED` agreement with a `next_due_date`, send a reminder when the days remaining crosses one of these thresholds:

| Days before due | Notification type | Email | Tone |
| :--- | :--- | :--- | :--- |
| **180** (6 months) | `RENT_DUE_SOON` | Yes | "Start saving." Names the amount and the date. |
| **90** (3 months) | `RENT_DUE_SOON` | Yes | "Here is where you are." Names the vault balance and the shortfall. |
| 30 | `RENT_DUE_SOON` | Yes | "A month to go." |
| 7 | `RENT_DUE_SOON` | Yes | "This week." |
| 0 (due today) | `RENT_DUE` | Yes | "Due today." |
| −1, −7, −14 (overdue) | `RENT_OVERDUE` | Yes | Plain and factual. No threats. |

**The 180 and 90-day milestones are the ones product asked for.** The rest is the standard tail — a six-month warning with nothing between it and the due date is not a reminder system. Put every threshold in a single settings constant so it can be tuned without a deploy.

### 5.3 Rules

- **Send each threshold at most once per agreement per rent cycle.** Record what has been sent. A tenant who gets the same "6 months to go" email twice will stop reading them, and then miss the one that mattered.
- **Skip a threshold that is already in the past.** An agreement executed 60 days before its due date must not receive the 180 and 90-day reminders in a burst on day one. Send the next one that has not yet been passed.
- **Stop the moment rent is paid.** Any payment reaching `ESCROW` for that cycle cancels every remaining reminder in it, including the overdue ones.
- **Never send to an unverified user.** They cannot pay anyway.
- **Email and notification are one event.** If either fails, log it and retry the pair; do not leave a tenant with an email and no in-app record, or the reverse.

### 5.4 Notification Payload

```json
{
  "id": "NOTIFICATION_UUID",
  "notification_type": "RENT_DUE_SOON",
  "title": "Rent due in 3 months",
  "message": "₦472,500 is due on 30 June 2027 for Unit 4B. You have ₦150,000 saved — ₦322,500 to go.",
  "is_read": false,
  "created_at": "2026-08-27T06:00:00Z",
  "data": {
    "agreement_id": "AGREEMENT_UUID",
    "unit_id": "UNIT_UUID",
    "due_date": "2027-06-30",
    "amount_due": "472500.00",
    "days_until_due": 90
  }
}
```

`data.agreement_id` and `data.due_date` are read by the app so the row can open the bill directly. The rest of `data` is available to it and currently unused.

### 5.5 New Notification Types

Add to the notification type enum. The Flutter client already handles all five and renders anything it does not recognise with safe defaults, so shipping these before an app release is safe.

| Type | Sent when | Recipient |
| :--- | :--- | :--- |
| `RENT_DUE_SOON` | A pre-due threshold is crossed | Tenant |
| `RENT_DUE` | Rent is due today | Tenant |
| `RENT_OVERDUE` | Rent is late | Tenant |
| `VAULT_TOPUP_SUCCEEDED` | A top-up settles | Tenant |
| `VAULT_TOPUP_FAILED` | A top-up fails | Tenant |

All five are valid values for the existing `?type=` filter on `GET /notifications/`.

### 5.6 Email

Same content as the notification, in the existing transactional email template. Three things it must have:

1. **The amount and the date in the subject line.** "Your rent" is not a subject line; "₦472,500 rent due 30 June 2027" is.
2. **A deep link into the app**, so the tenant can act rather than remember to.
3. **A working unsubscribe for the pre-due reminders only.** The due-today and overdue emails are transactional and stay.

Should the landlord be copied? Not in this batch. It was not asked for, and a landlord receiving six emails per tenant per year is how a product gets marked as spam.

---

## 6. Endpoint Summary

New and changed only. Everything not listed is unchanged.

| Action | Method | Path | Auth | Roles |
| :--- | :--- | :--- | :--- | :--- |
| Get vault | `GET` | `/api/users/vault/` | Yes + verified | **Any** (was `OWNER`) |
| List vault transactions | `GET` | `/api/users/vault/transactions/` | Yes + verified | **Any** (was `OWNER`) |
| List withdrawals | `GET` | `/api/users/vault/withdrawals/` | Yes + verified | **Any** (was `OWNER`) |
| Request withdrawal | `POST` | `/api/users/vault/withdrawals/` | Yes + verified | **Any** (was `OWNER`) |
| **Start top-up** | `POST` | `/api/users/vault/topups/` | Yes + verified | `TENANT` |
| **Verify top-up** | `POST` | `/api/users/vault/topups/{id}/verify/` | Yes + verified | `TENANT` |
| **List top-ups** | `GET` | `/api/users/vault/topups/` | Yes + verified | `TENANT` |
| Create payment | `POST` | `/api/users/payments/` | Yes + verified | `TENANT` | 

`POST /payments/` gains the optional `source` field described in §3.1; its path and permissions are unchanged.

---

## 7. Data Model Notes

- **`VaultTopUp`** — new table. `user`, `amount`, `currency`, `status`, `reference`, `provider_reference`, `authorization_url`, `access_code`, `failure_reason`, `idempotency_key`, `created_at`, `completed_at`. Unique on `(user, idempotency_key)`.
- **`Vault`** — gains `total_spent`. Drop the `OWNER`-only assumption wherever one is baked in, including any `get_or_create` that only fires on the landlord path.
- **`VaultTransaction`** — no schema change. Two new `source_reference` prefixes (§2.3).
- **`Payment`** — gains `source` (`CARD` | `VAULT`, default `CARD`) and an `idempotency_key`.
- **`TenancyAgreement`** — gains `rent_plan` (default `ANNUAL`) and whatever is needed to compute `next_due_date`. If instalments are modelled as rows rather than derived, that is the better shape — but derive-from-dates is a complete implementation for `ANNUAL`.
- **`RentReminderLog`** — new table, or a JSON field on the agreement. Needs to answer "has threshold N been sent for this agreement's current cycle?" (§5.3). A table with a unique constraint on `(agreement, cycle, threshold_days)` is the honest version, and the constraint is what actually prevents the duplicate.

---

## 8. Test Checklist

The cases worth writing, chosen because each one costs a real user real money if it is wrong.

**Vault scope**
- [ ] A tenant with no vault gets `200` and a zero balance from `GET /vault/`, not `404`.
- [ ] Tenant A cannot read Tenant B's vault, ledger, or withdrawals by any request shape.
- [ ] A tenant can withdraw, subject to the existing payout-account gate.

**Top-ups**
- [ ] Two `POST /vault/topups/` with the same `Idempotency-Key` return one top-up and charge once.
- [ ] The vault is not credited on `POST` — only on provider confirmation.
- [ ] A webhook and a verify call arriving together credit the vault exactly once.
- [ ] Verifying an already-`SUCCEEDED` top-up is a no-op that returns it unchanged.
- [ ] A failed top-up leaves the balance untouched and carries a `failure_reason`.

**Paying from the vault**
- [ ] `source: VAULT` with sufficient balance returns `ESCROW`, debits once, and returns no `authorization_url`.
- [ ] `source: VAULT` with an insufficient balance returns `INSUFFICIENT_VAULT_BALANCE` and creates no payment.
- [ ] A failed debit creates no payment record at all.
- [ ] Two identical vault payments with the same `Idempotency-Key` debit once.
- [ ] A refunded vault payment returns the money to the vault, not the card.
- [ ] Escrow release on a vault-funded payment credits the landlord's vault as normal.

**Schedules**
- [ ] `rent_schedule` is absent or null on an agreement that is not `EXECUTED`.
- [ ] `days_until_due` is negative and `is_overdue` is true past the due date.
- [ ] `next_due_date` is null once nothing more is owed.

**Reminders**
- [ ] Each threshold fires at most once per agreement per cycle, across repeated job runs.
- [ ] An agreement executed 60 days before its due date does not receive the 180 and 90-day reminders.
- [ ] Paying rent cancels every remaining reminder for that cycle.
- [ ] Nothing is sent to an unverified user.
- [ ] The email subject carries the amount and the date.

---

## 9. Fallback Behaviour: What The App Does Before This Ships

The Flutter client is already written against this contract and degrades rather than breaking. Useful for staging a partial rollout — and worth reading, because it says what each piece is actually worth.

| Missing | What the app does |
| :--- | :--- |
| `GET /vault/` rejects tenants | The tenant's balance card shows "Balance unavailable" with the backend's own message. The rest of the payments screen works. |
| `POST /vault/topups/` missing | "Add money" surfaces the error the backend returned. Nothing else is affected. |
| `source: VAULT` unsupported | If the backend ignores `source` and returns a `PENDING` card payment, the app reports the vault payment as failed and says the vault was not charged — which is true. Rent is still payable by card. |
| `rent_schedule` missing | The app falls back to the agreement's `end_date` as the next rent date, with no plan and no instalment counts, because those would be guesses. Rent already owed still shows as owed. |
| `total_spent` missing | Defaults to `"0.00"`. Not currently displayed. |
| Reminder types missing | Nothing to render. The dashboard still shows the due date from §4. |

The reverse is also safe: every field above can ship before an app release. Unknown notification types, unknown top-up statuses and unknown rent plans all render with safe defaults, and none of them are ever interpreted as "your money arrived".

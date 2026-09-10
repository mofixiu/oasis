# Oasis Backend Change Specification — v2

> **Audience:** Backend developer implementing on the Django API (`landa_os`, `users` app).
>
> **Companion document:** `flutter_api_guide (7).md` in this folder describes the API as it exists today. This document describes only what **changes**. Where a section says "current behaviour", it is quoting that guide. When this batch ships, fold these sections into the guide and bump it to `(8)`.
>
> **Base URL (staging):** `https://landa-os-staging.onrender.com/api/users`
>
> **Status:** Requested by product ownership. All six items are in scope for this batch.

---

## 0. Status — Shipped, With Differences

**This spec has been implemented. `flutter_api_guide (8).md` in this folder is now the source of truth.** Keep this document for the reasoning behind each decision, but read the guide for the contract.

The backend shipped differently from this spec in five places. The Flutter app follows the **guide**, not this document:

| Area | Specced here | Shipped |
| :--- | :--- | :--- |
| Payout save | `account_name` accepted but ignored | **Rejected** — `ACCOUNT_NAME_NOT_ACCEPTED`. `POST /payout-account/` takes `resolution_token` and nothing else. |
| Withdrawal statuses | `PENDING` / `PROCESSING` / `PAID` / `FAILED` / `REVERSED` | `PENDING_REVIEW` / `PENDING_TRANSFER` / `PAID` / `FAILED` / `CANCELLED` |
| Withdrawal quote | `GET /vault/withdrawals/quote/` returning a fee breakdown | **Does not exist.** No fee is quoted; the backend validates on submit. |
| `GET /vault/` | Balances plus payout status, limits and recent transactions | Balances only — `available_balance`, `pending_withdrawal_balance`, `total_credited`, `total_withdrawn`. Payout standing comes from `GET /payout-account/`. |
| Chat eligibility | A `PENDING` application could start a conversation | **Approval required.** A pending application returns `403 NO_RELATIONSHIP`. |

The last one is a product change, not a technical one: messaging now opens when the landlord approves, not when the tenant applies.

---

## 1. What Changes, And Why

Six changes were requested. They are listed here in **implementation order**, which is not the order they were requested in — one is a production bug, one is a structural change to how money moves that the others depend on, and the rest are additive.

| # | Change | Type | Why it is ordered here |
| :--- | :--- | :--- | :--- |
| 1 | [Payout account returns 400](#3-payout-account-400-fix) | Bug fix | Landlords cannot complete payout setup today. Blocks every money flow. |
| 2 | [Vault (wallet) + withdrawals](#4-vault-and-withdrawals) | Structural | Changes what escrow release does. Removes payout gating from agreements. Everything money-related depends on this. |
| 3 | [Property photos required](#5-property-photos-become-required) | Validation | Small, self-contained. |
| 4 | [Agreement visibility split](#6-agreement-visibility--dashboard-versus-profile) | Filter | Small backend change; the work is mostly in the app. |
| 5 | [Landlord ↔ tenant messaging](#7-landlord-and-tenant-messaging) | New feature | Largest new surface. Independent of the money work. |
| 6 | [Landlord broadcast messages](#8-landlord-broadcast-messages) | New feature | Depends on the notification model changes in §9. |

### Mapping To The Original Request

| Requested as | Covered in |
| :--- | :--- |
| "make property photos required when adding property" | §5 |
| "move signed agreements from the dashboard to the profile section" | §6 |
| "landlord chat with tenant (uber like)" — either party may start | §7 |
| "fix payout account (400 error)" | §3 |
| "broadcast messages for landlord, add in notifications" | §8, §9 |
| "money saved to a vault first… payout account isn't needed until they want to withdraw" | §4 |

### The One Behavioural Change To Read First

Today, a landlord **cannot execute an agreement** without a verified payout account, and escrow release pushes money straight to their bank. After §4, neither is true:

- Payout account is required **only at withdrawal time**.
- Escrow release credits an in-app **vault balance**. The bank transfer happens later, when the landlord withdraws.

That means `PAYOUT_ACCOUNT_REQUIRED` must be **removed** from `POST /agreements/{id}/sign/` and `POST /payments/{id}/release/`, and appears instead on `POST /vault/withdrawals/`. This is spelled out in §4.7.

---

## 2. Cross-Cutting Conventions For New Endpoints

These apply to everything added in this document. They are stricter than what the current API does, because the new surfaces (money movement, messaging) need them.

### 2.1 Error Envelope

Every 4xx and 5xx from a new or modified endpoint returns this shape:

```json
{
  "code": "MACHINE_READABLE_CODE",
  "detail": "One sentence the app can show the user as-is.",
  "field": "account_number"
}
```

- `code` — SCREAMING_SNAKE_CASE, stable, never localised. The app branches on this.
- `detail` — user-presentable. The Flutter client puts this straight into a toast, so it must not contain stack traces, provider payloads, or the word "Exception".
- `field` — optional. Present only when the error belongs to one request field.

For multi-field validation failures, keep DRF's field-error dict but add the envelope alongside it:

```json
{
  "code": "VALIDATION_ERROR",
  "detail": "Some details are missing or invalid.",
  "errors": {
    "photos": ["At least one property photo is required."],
    "latitude": ["This field is required."]
  }
}
```

### 2.2 Status Code Discipline

The app shows a different screen for each of these, so the distinction matters more than it looks:

| Situation | Status | Example code |
| :--- | :--- | :--- |
| User typed something wrong | `422` | `INVALID_ACCOUNT_NUMBER` |
| User's request conflicts with current state | `409` | `AGREEMENT_NOT_EXECUTED` |
| User is not allowed / needs a prerequisite | `403` | `PAYOUT_ACCOUNT_REQUIRED` |
| Third-party provider rejected a valid-looking request | `422` | `ACCOUNT_NOT_FOUND` |
| Third-party provider is down, timed out, or misconfigured | `502` / `503` | `PROVIDER_UNAVAILABLE` |
| Rate limited | `429` | `TOO_MANY_REQUESTS` (+ `Retry-After` header) |

**A provider outage must never surface as a 400.** The app currently tells the landlord "check your details and try again" on any 400, which is wrong advice when Paystack is down. This is half of the bug in §3.

### 2.3 Idempotency

Any endpoint that moves money or creates a record from a user tap accepts an idempotency key:

```text
Idempotency-Key: 8f14e45f-ea6d-4b0a-9f2c-1b7a55c1e3a2
```

Store `(user, endpoint, key) → response` for 24 hours. A repeat with the same key returns the **stored response** with the original status code, and does not re-execute. Required on:

- `POST /vault/withdrawals/`
- `POST /payout-account/`
- `POST /conversations/{id}/messages/` (also accepts `client_message_id` in the body — see §7.6)

Internal credits (escrow release → vault) use a database-level unique `source_reference` instead, so a webhook retry cannot double-credit. See §4.4.

### 2.4 Cursor Pagination

List endpoints added here are paginated from day one. The current API returns raw arrays with no pagination; message history and ledger entries cannot work that way.

```text
GET /vault/transactions/?limit=25&cursor=eyJpZCI6...
```

```json
{
  "results": [],
  "next_cursor": "eyJpZCI6IjAxOTIzIn0",
  "has_more": true
}
```

- `limit` default 25, max 100.
- Cursor is opaque and encodes `(created_at, id)` — never a page number, so an insert mid-scroll does not shift rows.
- `next_cursor` is `null` when `has_more` is `false`.

> **Note for the app team:** the existing endpoints keep returning raw arrays. Do not paginate them in this batch — it would break the shipped client. New endpoints only.

### 2.5 Money

Unchanged from the current guide, restated because §4 depends on it:

- `DecimalField(max_digits=14, decimal_places=2)`, currency NGN, serialised as a **string**: `"450000.00"`.
- Never a float, anywhere, at any layer.
- Every balance mutation happens inside `transaction.atomic()` with `select_for_update()` on the vault row.

### 2.6 Verification Gating

New endpoints follow the existing rule: authenticated **and** `verification_status == "VERIFIED"`, returning the same `403` the current product endpoints return. Role restrictions are listed per endpoint — vault and broadcast endpoints are `OWNER`-only; agreements and conversations are open to both roles but scoped to records the caller is a party to.

---

## 3. Payout Account 400 Fix

**Symptom:** `POST /api/users/payout-account/` returns `400` for landlords entering valid bank details. Setup cannot be completed, which today also blocks agreement execution and escrow release.

### 3.1 Exactly What The App Sends

`lib/features/payouts/services/payout_service.dart` sends this and nothing else:

```http
POST /api/users/payout-account/
Authorization: Bearer <access>
Content-Type: application/json

{
  "bank_name": "STANBIC IBTC BANK",
  "account_number": "0023966034",
  "account_name": "AYOMIDE AKINDAMOLA AKINTAN"
}
```

Client-side validation before the request: `bank_name` is a value the user picked from `GET /banks/` (never free text), `account_number` is exactly 10 digits, `account_name` is a non-empty free-text string **typed by the user**. `PATCH` sends the identical body.

So by the time the request reaches the backend, only two things can be wrong: the bank name did not resolve, or the typed account name did not match. Both are the backend's to handle.

### 3.2 Ranked Causes

| # | Cause | How to confirm | Likelihood |
| :--- | :--- | :--- | :--- |
| 1 | **`account_name` compared strictly against Paystack's resolved name.** Paystack returns `"AKINTAN AYOMIDE AKINDAMOLA"` — surname first, different spacing, sometimes an initial. Any equality or `!=` check fails for a landlord who typed their name correctly. | Log both strings side by side in the failing branch. | **High** |
| 2 | **`bank_name` → bank code resolution fails.** `GET /banks/` returns names only. If that list is built from a different source, a stale fixture, or a different casing than the list used at resolve time, lookup misses. Paystack also ships near-duplicates (`"Access Bank"` vs `"Access Bank (Diamond)"`, `"Stanbic IBTC Bank"` vs `"STANBIC IBTC BANK"`). | Assert that every name returned by `/banks/` resolves to a code in the same request path. | **High** |
| 3 | **Paystack `resolve` failure surfaced as 400.** Test-mode keys cannot resolve arbitrary real account numbers; a missing or wrong `PAYSTACK_SECRET_KEY` on Render returns 401 from Paystack, which then gets re-raised as a generic 400. | `curl` the resolve call with the same key the Render service holds. | **Medium** |
| 4 | **Re-submitting when an account already exists.** `POST` on a `OneToOneField` hits the unique constraint and DRF renders it as a 400 field error. The app calls `POST` on first submit even when a record exists in a `FAILED` state. | Try `POST` twice with the same landlord. | **Medium** |
| 5 | **Transfer-recipient creation fails after a successful resolve** and is collapsed into the same 400. | Check whether the failing response body mentions `recipient`. | **Low** |

Causes 1 and 2 alone account for the report as described: the landlord's details are genuinely correct, and the request still fails.

### 3.3 The Fix — Stop Trusting A Typed Name

**The account name must come from the provider, not from the user.** This is how every Nigerian banking app does it: pick bank, type 10 digits, the app shows the resolved name back for confirmation. It removes cause 1 permanently and turns cause 2 into a resolvable, testable failure.

Two endpoints replace the single blind `POST`.

#### `POST /payout-account/resolve/` — new

Resolves an account without saving anything. Called as soon as the landlord has picked a bank and typed 10 digits.

- **Auth:** Required, verified
- **Roles:** `OWNER`
- **Rate limit:** 10/minute per user

##### Request

```json
{
  "bank_name": "STANBIC IBTC BANK",
  "account_number": "0023966034"
}
```

`bank_code` may be sent instead of `bank_name`; if both are present, `bank_code` wins.

##### Response `200 OK`

```json
{
  "bank_name": "Stanbic IBTC Bank",
  "bank_code": "221",
  "account_number": "0023966034",
  "account_number_masked": "******6034",
  "account_name": "AKINTAN AYOMIDE AKINDAMOLA",
  "resolution_token": "rsl_01J8ZQ4M2K7X9V",
  "expires_at": "2026-08-23T14:10:00Z"
}
```

`resolution_token` is a short-lived (10 minute) server-side record of `(user, bank_code, account_number, resolved_name)`. It exists so the save step cannot be spoofed with a different account number than the one the user confirmed on screen.

#### `POST /payout-account/` — changed

- **`account_name` is no longer read from the request.** Accept the field for compatibility (see §3.6) but **ignore it** and never compare it.
- Accepts `resolution_token` from the resolve step. When present, skip re-resolving and use the stored resolved name.
- When absent (older app builds), resolve server-side exactly as `resolve/` does and use the provider's name.

##### Request

```json
{
  "bank_code": "221",
  "account_number": "0023966034",
  "resolution_token": "rsl_01J8ZQ4M2K7X9V"
}
```

##### Response `201 Created`

```json
{
  "id": "PAYOUT_ACCOUNT_UUID",
  "bank_name": "Stanbic IBTC Bank",
  "bank_code": "221",
  "account_number": "******6034",
  "account_name": "AKINTAN AYOMIDE AKINDAMOLA",
  "status": "VERIFIED",
  "provider": "paystack",
  "provider_recipient_code": "RCP_xxxxxxxx",
  "verified_at": "2026-08-23T14:02:11Z",
  "last_verified_at": "2026-08-23T14:02:11Z"
}
```

#### `PATCH /payout-account/` — changed

Becomes an **upsert**: if no payout account exists, create one instead of 404-ing. Same body and same response as `POST`. This removes cause 4 — the app can always `PATCH` to change details and always `POST` to create, and neither path can collide.

Additionally, `POST` when a `VERIFIED` account already exists returns `409` with code `PAYOUT_ACCOUNT_EXISTS` and `detail: "You already have a payout account. Update it instead."` — never a bare constraint error.

### 3.4 `GET /banks/` Must Return Codes

```json
[
  {"name": "Access Bank", "code": "044", "slug": "access-bank"},
  {"name": "Stanbic IBTC Bank", "code": "221", "slug": "stanbic-ibtc-bank"},
  {"name": "Zenith Bank", "code": "057", "slug": "zenith-bank"}
]
```

Requirements:

1. Sourced from the **same** cached Paystack `/bank?currency=NGN` response that resolution uses. Cache for 24h; never hand-maintain the list.
2. Filter to `active: true`, `type: "nuban"`, deduplicate by code, sort alphabetically.
3. `name` must be the provider's own spelling, so a round-trip by name still resolves.
4. `code` is additive — the shipped app ignores unknown keys and keeps sending `bank_name`.

### 3.5 Error Codes For Payout Setup

| Code | Status | `detail` shown to the landlord |
| :--- | :--- | :--- |
| `INVALID_ACCOUNT_NUMBER` | `422` | "Account number must be 10 digits." |
| `BANK_NOT_SUPPORTED` | `422` | "We could not find that bank. Pick it again from the list." |
| `ACCOUNT_NOT_FOUND` | `422` | "That account number does not exist at this bank. Check the digits and try again." |
| `RESOLUTION_TOKEN_EXPIRED` | `409` | "That took a while — confirm your account details again." |
| `PAYOUT_ACCOUNT_EXISTS` | `409` | "You already have a payout account. Update it instead." |
| `RECIPIENT_CREATION_FAILED` | `502` | "We couldn't set up transfers to this account yet. Try again in a moment." |
| `PROVIDER_UNAVAILABLE` | `502` | "Your bank couldn't be reached right now. Try again in a moment." |
| `PROVIDER_NOT_CONFIGURED` | `503` | "Payouts are temporarily unavailable. We're on it." |

`PROVIDER_NOT_CONFIGURED` covers a missing/invalid `PAYSTACK_SECRET_KEY`. It must be a 503 and must page whoever is on call — it is a deployment fault, not a user fault, and today it looks identical to a typo.

### 3.6 Compatibility With The Shipped App

The build in the field sends `{bank_name, account_number, account_name}` and expects a payout-account object back. Keep it working:

- Never reject a request because `account_name` differs from the resolved name. **Delete the `ACCOUNT_NAME_MISMATCH` code entirely.**
- `bank_name` stays accepted indefinitely.
- `resolution_token` is optional.
- Keep returning `account_number` masked, and keep the `MISSING` envelope from `GET /payout-account/` exactly as it is — `lib/features/payouts/models/payout_models.dart` parses `status`, `payout_account_required_for` and `detail` from it, and treats an unrecognised `status` as `UNKNOWN`, which blocks the landlord.
- `status` values must stay inside `MISSING | UNVERIFIED | PENDING | VERIFIED | FAILED | NOT_REQUIRED`. A new value silently disables the UI.

### 3.7 Logging Required With This Fix

The reason this bug is still open is that the failure is invisible from the response. Add, on every payout request:

- `X-Request-ID` echoed back in the response headers and included in the error envelope as `request_id`.
- A structured log line: `user_id`, `bank_code`, `account_number` masked to last 4, Paystack endpoint, Paystack HTTP status, Paystack `message`, and the internal `code` returned. **Never log the full account number or the secret key.**
- On a name comparison (during the transition, for observability only — not for rejection), log `submitted_name` and `resolved_name` so the mismatch rate can be measured before the field is dropped.

### 3.8 Acceptance Tests

| Case | Expected |
| :--- | :--- |
| Valid bank + valid 10-digit account, name typed surname-first | `201`, saved with provider's name |
| Valid bank + valid account, name typed with a typo | `201` — the typed name is ignored |
| Valid bank + account number that does not exist | `422 ACCOUNT_NOT_FOUND` |
| Bank name not in the provider list | `422 BANK_NOT_SUPPORTED` |
| 9-digit account number | `422 INVALID_ACCOUNT_NUMBER` |
| Paystack secret key unset | `503 PROVIDER_NOT_CONFIGURED` |
| Paystack times out | `502 PROVIDER_UNAVAILABLE` |
| Same request replayed with the same `Idempotency-Key` | Same stored `201` response, one recipient created |
| `POST` twice, second without idempotency key | `409 PAYOUT_ACCOUNT_EXISTS` |
| `PATCH` with no existing account | `201`, created |
| Tenant calls any payout endpoint | `403` |

Verify against Paystack test-mode NUBANs (`0000000000` / bank `044` resolves in test mode) plus one real account in staging before sign-off.

---

## 4. Vault And Withdrawals

**Requirement as given:** *"The money should be saved to a vault first — just an account — then they can withdraw it. Payout account isn't needed until they want to withdraw from the vault."*

### 4.1 How Money Moves, Before And After

**Today:**

```text
Tenant pays  →  ESCROW (held)  →  landlord taps Release
                                  →  Paystack transfer to landlord's bank
                                  →  payment.status = RELEASED
```

The landlord must have a verified payout account before signing the agreement, and again before releasing.

**After this change:**

```text
Tenant pays  →  ESCROW (held)  →  dispute window ends (or landlord releases)
                                  →  vault credited, payment.status = RELEASED
                                  →  money sits in the landlord's vault

Landlord taps Withdraw (any time, any amount up to the balance)
                                  →  payout account required here, for the first time
                                  →  Paystack transfer
                                  →  withdrawal.status = PAID
```

Escrow does not disappear — it is still the tenant's protection window. The vault is what escrow releases **into**.

### 4.2 Balances

A landlord has exactly one vault, created lazily on first credit or first `GET /vault/`.

| Balance | Meaning | Source |
| :--- | :--- | :--- |
| `pending_balance` | Rent sitting in escrow for this landlord, not yet released | Derived: sum of `amount` on payments with `status = ESCROW` on this landlord's agreements. **Not** stored on the vault. |
| `available_balance` | Withdrawable right now | Stored on the vault row. Mutated only by ledger entries. |
| `withdrawing_balance` | Reserved by withdrawals that are `PENDING` or `PROCESSING` | Stored on the vault row. |
| `total_balance` | `available_balance + withdrawing_balance` | Computed at serialisation. |

Rules:

- A withdrawal request **debits `available_balance` immediately** and adds the same amount to `withdrawing_balance`. Money cannot be double-spent by tapping Withdraw twice.
- On `transfer.success`, `withdrawing_balance` drops; `available_balance` is untouched (it was already debited).
- On `transfer.failed` / `transfer.reversed`, `withdrawing_balance` drops and `available_balance` is credited back with a `WITHDRAWAL_REVERSAL` ledger entry.
- `available_balance` may never go negative. Enforce with a `CheckConstraint`, not just application logic.

### 4.3 Data Model

```python
class Vault(models.Model):
    """One per landlord. Balances are stored, never recomputed on read."""
    id = models.UUIDField(primary_key=True, default=uuid4, editable=False)
    owner = models.OneToOneField(User, on_delete=models.PROTECT, related_name="vault")
    currency = models.CharField(max_length=3, default="NGN")
    available_balance = models.DecimalField(max_digits=14, decimal_places=2, default=0)
    withdrawing_balance = models.DecimalField(max_digits=14, decimal_places=2, default=0)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        constraints = [
            models.CheckConstraint(
                check=models.Q(available_balance__gte=0)
                      & models.Q(withdrawing_balance__gte=0),
                name="vault_balances_non_negative",
            )
        ]


class VaultTransaction(models.Model):
    """Append-only ledger. Rows are never updated or deleted."""
    class Type(models.TextChoices):
        ESCROW_RELEASE      = "ESCROW_RELEASE"
        WITHDRAWAL          = "WITHDRAWAL"
        WITHDRAWAL_FEE      = "WITHDRAWAL_FEE"
        WITHDRAWAL_REVERSAL = "WITHDRAWAL_REVERSAL"
        REFUND_DEBIT        = "REFUND_DEBIT"
        ADJUSTMENT          = "ADJUSTMENT"

    class Direction(models.TextChoices):
        CREDIT = "CREDIT"
        DEBIT  = "DEBIT"

    id = models.UUIDField(primary_key=True, default=uuid4, editable=False)
    vault = models.ForeignKey(Vault, on_delete=models.PROTECT, related_name="transactions")
    type = models.CharField(max_length=32, choices=Type.choices)
    direction = models.CharField(max_length=6, choices=Direction.choices)
    amount = models.DecimalField(max_digits=14, decimal_places=2)   # always positive
    balance_after = models.DecimalField(max_digits=14, decimal_places=2)
    description = models.CharField(max_length=255)

    payment = models.ForeignKey("Payment", null=True, blank=True, on_delete=models.SET_NULL)
    withdrawal = models.ForeignKey("Withdrawal", null=True, blank=True, on_delete=models.SET_NULL)

    # The double-credit guard. e.g. "payment:39c5843f:release"
    source_reference = models.CharField(max_length=128, unique=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        indexes = [models.Index(fields=["vault", "-created_at"])]


class Withdrawal(models.Model):
    class Status(models.TextChoices):
        # Reserved for the OTP step in §4.8. Nothing emits it in this batch,
        # but adding it now means the enum does not change once money is real.
        AWAITING_CONFIRMATION = "AWAITING_CONFIRMATION"
        PENDING    = "PENDING"      # accepted, transfer not yet initiated
        PROCESSING = "PROCESSING"   # transfer initiated at the provider
        PAID       = "PAID"
        FAILED     = "FAILED"
        REVERSED   = "REVERSED"

    id = models.UUIDField(primary_key=True, default=uuid4, editable=False)
    vault = models.ForeignKey(Vault, on_delete=models.PROTECT, related_name="withdrawals")
    amount = models.DecimalField(max_digits=14, decimal_places=2)      # what lands in the bank
    fee = models.DecimalField(max_digits=14, decimal_places=2, default=0)
    total_debited = models.DecimalField(max_digits=14, decimal_places=2)  # amount + fee
    status = models.CharField(max_length=16, choices=Status.choices, default=Status.PENDING)

    payout_account = models.ForeignKey("PayoutAccount", on_delete=models.PROTECT)
    bank_name_snapshot = models.CharField(max_length=128)
    account_number_masked = models.CharField(max_length=16)

    reference = models.CharField(max_length=64, unique=True)          # LW-XXXXXXXX
    provider_reference = models.CharField(max_length=128, blank=True) # Paystack transfer code
    idempotency_key = models.CharField(max_length=128, blank=True)
    failure_reason = models.CharField(max_length=255, blank=True)

    requested_at = models.DateTimeField(auto_now_add=True)
    completed_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        constraints = [
            models.UniqueConstraint(
                fields=["vault", "idempotency_key"],
                condition=~models.Q(idempotency_key=""),
                name="withdrawal_idempotency_per_vault",
            )
        ]
```

Every balance change goes through one helper, and nothing else touches `available_balance`:

```python
@transaction.atomic
def post_entry(vault_id, *, type, direction, amount, source_reference, **kw):
    vault = Vault.objects.select_for_update().get(pk=vault_id)
    if VaultTransaction.objects.filter(source_reference=source_reference).exists():
        return None                      # already applied; webhook retry
    delta = amount if direction == CREDIT else -amount
    vault.available_balance += delta
    if vault.available_balance < 0:
        raise InsufficientVaultBalance()
    vault.save(update_fields=["available_balance", "updated_at"])
    return VaultTransaction.objects.create(
        vault=vault, type=type, direction=direction, amount=amount,
        balance_after=vault.available_balance,
        source_reference=source_reference, **kw)
```

### 4.4 Crediting The Vault

#### What gets credited

The landlord receives `payment.amount` — the rent. `payment.platform_fee` is Oasis's, charged on top to the tenant, and is never credited to the vault. With the numbers already in the guide: tenant pays `472500.00`, vault is credited `450000.00`.

#### `POST /payments/{payment_id}/release/` — changed

- **No longer initiates a bank transfer.**
- **No longer requires a payout account.** Remove the `403 PAYOUT_ACCOUNT_REQUIRED` branch from this endpoint.
- Inside one transaction: set `payment.status = RELEASED`, set `released_at`, post an `ESCROW_RELEASE` credit with `source_reference = f"payment:{payment.id}:release"`.
- Disputed payments still cannot be released. `demo_override` keeps working for demos.

##### Response `200 OK`

The existing payment object, plus:

```json
{
  "id": "39c5843f-1e32-4366-af93-275fbb0c89e2",
  "status": "RELEASED",
  "released_at": "2026-08-23T10:00:00Z",
  "settlement_mode": "VAULT",
  "vault_credit": {
    "transaction_id": "VAULT_TXN_UUID",
    "amount": "450000.00",
    "available_balance_after": "1350000.00"
  }
}
```

`settlement_mode` is `VAULT` for everything after this change and `DIRECT_TRANSFER` for historical rows — see §4.10.

#### Automatic release

With money landing in a vault instead of a bank account, release no longer needs a landlord tap. Add a scheduled job (Celery beat, or `manage.py release_due_escrow` on a 5-minute cron):

- Select payments where `status = ESCROW`, `escrow_release_at <= now()`, `disputed_at IS NULL`.
- Release each one through the same code path as the endpoint, with the same `source_reference`, so a manual release racing the job cannot double-credit.
- Emit an `ESCROW_RELEASED` notification and a `VAULT_CREDITED` notification.
- Behind `settings.AUTO_RELEASE_ESCROW` (default **on**), so it can be disabled without a deploy.

**Confirmed by product: escrow releases automatically.** A landlord should never have to tap anything to be paid — the dispute window closing is the event, and the vault is where the money goes. The flag exists to stop the job during an incident, not as a product choice to revisit.

Manual release stays available for landlords who want the money sooner and for demos.

#### Disputes

A dispute raised **before** release freezes the payment as it does today — no credit is posted. A dispute resolved in the tenant's favour after money has already been credited is handled by an admin `REFUND_DEBIT` entry; if `available_balance` is insufficient it must fail loudly for manual handling rather than driving the balance negative. Automatic clawback is out of scope for this batch.

### 4.5 Vault Endpoints

All are `OWNER`-only and require a verified account. A tenant calling any of them gets `403 VAULT_NOT_AVAILABLE_FOR_ROLE` — tenant refunds go back to the card through the provider and do not use a vault in this batch.

#### `GET /vault/`

The whole payments-page summary in one call. The app renders the vault card from this and nothing else.

##### Response `200 OK`

```json
{
  "id": "VAULT_UUID",
  "currency": "NGN",
  "available_balance": "1350000.00",
  "pending_balance": "450000.00",
  "withdrawing_balance": "0.00",
  "total_balance": "1350000.00",
  "can_withdraw": true,
  "withdrawal_blocked_reason": null,
  "payout_account": {
    "status": "VERIFIED",
    "bank_name": "Stanbic IBTC Bank",
    "account_number": "******6034",
    "account_name": "AKINTAN AYOMIDE AKINDAMOLA"
  },
  "limits": {
    "minimum_withdrawal": "1000.00",
    "maximum_withdrawal_per_transaction": "5000000.00",
    "maximum_withdrawals_per_day": 5,
    "withdrawals_remaining_today": 5,
    "fee_flat": "50.00"
  },
  "recent_transactions": [
    {
      "id": "VAULT_TXN_UUID",
      "type": "ESCROW_RELEASE",
      "direction": "CREDIT",
      "amount": "450000.00",
      "balance_after": "1350000.00",
      "description": "Rent released — Sunset House, Unit A1",
      "created_at": "2026-08-23T10:00:00Z"
    }
  ]
}
```

- `recent_transactions` is capped at 5. Full history comes from the ledger endpoint.
- `can_withdraw` is `false` with a `withdrawal_blocked_reason` when the balance is below the minimum, no verified payout account exists, or the daily cap is spent. The app shows that string; it must be a full sentence.
- When the landlord has no payout account, `payout_account.status` is `"MISSING"` and `withdrawal_blocked_reason` is `"Add a bank account to withdraw."` The vault itself still renders with its balance — **this is the whole point of the change: seeing your money must not require bank setup.**

#### `GET /vault/transactions/`

Paginated ledger, newest first. Cursor pagination per §2.4.

Query params: `type` (any `VaultTransaction.Type`), `direction`, `from` / `to` (ISO dates), `limit`, `cursor`.

```json
{
  "results": [
    {
      "id": "VAULT_TXN_UUID",
      "type": "WITHDRAWAL",
      "direction": "DEBIT",
      "amount": "200000.00",
      "balance_after": "1150000.00",
      "description": "Withdrawal to Stanbic IBTC Bank ******6034",
      "reference": "LW-7F3A9C21",
      "payment": null,
      "withdrawal": "WITHDRAWAL_UUID",
      "created_at": "2026-08-23T11:15:00Z"
    }
  ],
  "next_cursor": "eyJpZCI6...",
  "has_more": true
}
```

#### `GET /vault/withdrawals/quote/?amount=200000`

Returns the fee breakdown before the landlord commits. Never mutates anything.

```json
{
  "amount": "200000.00",
  "fee": "50.00",
  "total_debit": "200050.00",
  "available_after": "1149950.00",
  "arrives_estimate": "Within 24 hours, usually minutes",
  "can_proceed": true
}
```

If `can_proceed` is `false`, the response also carries `code` and `detail` from the table in §4.6 so the app can disable the button with the real reason rather than a generic one.

#### `POST /vault/withdrawals/`

- **Auth:** Required, verified, `OWNER`
- **Header:** `Idempotency-Key` required
- **Rate limit:** 10/hour per user

##### Request

```json
{
  "amount": "200000.00"
}
```

`{"full_balance": true}` is also accepted, and withdraws `available_balance - fee`.

##### Response `202 Accepted`

`202`, not `201` — the money has left the vault but has not reached the bank yet, and the app must not tell the landlord it is paid.

```json
{
  "id": "WITHDRAWAL_UUID",
  "reference": "LW-7F3A9C21",
  "amount": "200000.00",
  "fee": "50.00",
  "total_debited": "200050.00",
  "status": "PROCESSING",
  "bank_name": "Stanbic IBTC Bank",
  "account_number": "******6034",
  "account_name": "AKINTAN AYOMIDE AKINDAMOLA",
  "requested_at": "2026-08-23T11:15:00Z",
  "completed_at": null,
  "failure_reason": "",
  "vault": {
    "available_balance": "1149950.00",
    "withdrawing_balance": "200050.00"
  }
}
```

##### Errors

| Code | Status | `detail` |
| :--- | :--- | :--- |
| `PAYOUT_ACCOUNT_REQUIRED` | `403` | "Add a bank account before withdrawing." — plus `"payout_account_required_for": "WITHDRAWAL"` |
| `INSUFFICIENT_VAULT_BALANCE` | `422` | "You don't have enough in your vault for this withdrawal." — plus `available_balance` |
| `AMOUNT_BELOW_MINIMUM` | `422` | "The smallest withdrawal is ₦1,000." |
| `AMOUNT_ABOVE_MAXIMUM` | `422` | "The largest single withdrawal is ₦5,000,000." |
| `DAILY_WITHDRAWAL_LIMIT_REACHED` | `429` | "You've used all 5 withdrawals for today. Try again tomorrow." |
| `WITHDRAWAL_IN_PROGRESS` | `409` | "A withdrawal is already being processed. Wait for it to finish." |
| `PROVIDER_UNAVAILABLE` | `502` | "Transfers are briefly unavailable. Your money is safe in your vault." |

On `PROVIDER_UNAVAILABLE`, the debit must be **rolled back** — the whole handler is one atomic block, and if `initiate_transfer` throws, nothing was debited.

#### `GET /vault/withdrawals/` and `GET /vault/withdrawals/{id}/`

List (cursor-paginated, `?status=` filter) and detail, same object shape as above.

### 4.6 Withdrawal Lifecycle

```text
PENDING ──initiate_transfer ok──> PROCESSING ──transfer.success──> PAID
   │                                   │
   │                                   ├──transfer.failed────────> FAILED    (+ reversal credit)
   └──initiate_transfer throws         └──transfer.reversed─────> REVERSED  (+ reversal credit)
      → 502, nothing debited
```

Ledger entries per withdrawal:

| Moment | Entries |
| :--- | :--- |
| Request accepted | `WITHDRAWAL` debit `amount`, `WITHDRAWAL_FEE` debit `fee` — `source_reference` `withdrawal:{id}:debit` / `:fee` |
| `transfer.success` | None. Only `withdrawing_balance` is cleared and `status → PAID`. |
| `transfer.failed` / `reversed` | `WITHDRAWAL_REVERSAL` credit `total_debited`, `source_reference` `withdrawal:{id}:reversal` |

#### Paystack transfer webhook

`POST /webhooks/paystack/` already exists for charges. Extend it for `transfer.success`, `transfer.failed`, `transfer.reversed`:

1. Verify the `x-paystack-signature` HMAC-SHA512 against the raw body **before** parsing. Reject with `401` on mismatch.
2. Match `data.reference` to `Withdrawal.reference` (send our own reference when initiating so this is deterministic).
3. Apply the state change idempotently — Paystack retries, and a duplicate `transfer.failed` must not credit twice. The unique `source_reference` guarantees this.
4. Always return `200` once the event is persisted, even if it is a duplicate, so Paystack stops retrying.
5. Log every unmatched event rather than silently dropping it.

Also add a reconciliation sweep: any withdrawal `PROCESSING` for more than 30 minutes gets its status polled directly from Paystack's `GET /transfer/{code}`. Webhooks get lost; money must not sit in limbo because of it.

### 4.7 Payout Gating Moves To Withdrawal

This is the part most likely to be missed. Three places currently gate on a payout account and **two of them must stop**.

| Endpoint | Today | After |
| :--- | :--- | :--- |
| `POST /agreements/{id}/sign/` (landlord's final signature) | `403 PAYOUT_ACCOUNT_REQUIRED` | **No payout check.** Executes normally. |
| `POST /payments/{id}/release/` | `403 PAYOUT_ACCOUNT_REQUIRED` | **No payout check.** Credits the vault. |
| `POST /vault/withdrawals/` | — | `403 PAYOUT_ACCOUNT_REQUIRED` with `payout_account_required_for: "WITHDRAWAL"` |

`GET /profile/` changes accordingly:

```json
{
  "role": "OWNER",
  "verification_status": "VERIFIED",
  "payout_account_status": "MISSING",
  "payout_account_required": false,
  "payout_account_required_for": "WITHDRAWAL",
  "can_create_properties": true,
  "can_execute_agreements": true
}
```

- `can_execute_agreements` is now `true` for any verified landlord, regardless of payout status.
- `payout_account_required_for` takes the new value `"WITHDRAWAL"`. `"AGREEMENT_EXECUTION"` is retired — do not send it any more.

> **App-side note:** the shipped Flutter build reads `payout_account_required_for` as an opaque string and only uses it for banner copy, so this value change is safe. `can_execute_agreements` flipping to `true` is what unblocks landlords who are stuck behind the §3 bug today.

### 4.8 Limits, Fees And Security

**The withdrawal fee is whatever the provider charges.** Oasis does not add a margin and does not hardcode a figure. `GET /vault/withdrawals/quote/` resolves the fee for the requested amount from Paystack's transfer-fee schedule at quote time and returns it; the app renders that number and nothing else. `VAULT_WITHDRAWAL_FEE_FALLBACK` exists only for the case where the provider cannot be reached to quote — and when that happens, prefer failing the quote with `PROVIDER_UNAVAILABLE` over guessing, since the landlord is about to be charged the difference.

Fees are banded in Nigeria (roughly ₦10 / ₦25 / ₦50 by amount), so the fee must be resolved per amount rather than fixed per account.

Other limits, configurable in settings and returned to the app in `GET /vault/` so the copy never has to be hardcoded in Flutter:

| Setting | Default | Notes |
| :--- | :--- | :--- |
| `VAULT_MIN_WITHDRAWAL` | `1000.00` | Below Paystack's fee floor it is not worth processing |
| `VAULT_MAX_WITHDRAWAL_PER_TXN` | `5000000.00` | |
| `VAULT_MAX_WITHDRAWALS_PER_DAY` | `5` | Per user, rolling 24h |
| `VAULT_WITHDRAWAL_FEE_SOURCE` | `PROVIDER` | Pass through the provider's actual transfer fee — see below |
| `VAULT_WITHDRAWAL_FEE_FALLBACK` | `50.00` | Used only if the provider does not quote a fee for the amount |
| `AUTO_RELEASE_ESCROW` | `True` | §4.4 |

#### Withdrawal OTP

**Confirmed by product: withdrawals will require a one-time code — but not in this batch, which is a demo.** Build the endpoints without it now, and treat the following as a hard gate before the first naira of real money moves:

- `POST /vault/withdrawals/` responds `202` with `status: "AWAITING_CONFIRMATION"` and sends a 6-digit code to the user's registered email. Nothing is debited yet.
- `POST /vault/withdrawals/{id}/confirm/` with `{"code": "123456"}` performs the debit and initiates the transfer. Codes expire in 10 minutes, allow 3 attempts, then void the withdrawal.
- An unconfirmed withdrawal expires after 30 minutes and never touches the balance.

Designing the endpoints around this now costs nothing — the app already treats `202` as "accepted, not settled" — while retrofitting a confirmation step onto a live withdrawal flow means changing a contract that is moving money. The `AWAITING_CONFIRMATION` status should therefore be added to the enum in this batch even though nothing emits it yet.

> **Demo-mode warning.** Until the OTP step and the reconciliation jobs in §4.9 are both live, this vault should run against Paystack **test keys only**. Everything else in §4 is production-shaped; withdrawal authentication is the one piece deliberately deferred, and it is the piece that matters if an account is taken over.

Other security requirements, all in this batch:

- A withdrawal may only ever target the landlord's **own** verified payout account. The account is never supplied in the request body — it is read from the database. There is no endpoint that accepts an arbitrary destination account.
- Changing the payout account starts a **24-hour withdrawal cooling-off period** for that user (`WITHDRAWAL_LOCKED_AFTER_ACCOUNT_CHANGE`, returned as `withdrawal_blocked_reason`). This is the standard defence against an account-takeover draining a vault, and it costs nothing to implement.
- Every withdrawal request and every payout-account change sends an email to the user's registered address, whether or not it succeeded.
- Log `user_id`, `amount`, `ip`, and `user_agent` for every withdrawal attempt.

### 4.9 Reconciliation

Money in vaults is a liability the platform owes landlords. It must be checkable:

- Daily job asserting `SUM(vault.available_balance + vault.withdrawing_balance)` equals `SUM(credits) - SUM(debits)` across the whole ledger. Any drift pages immediately — a mismatch means a balance was mutated outside `post_entry`.
- Daily job comparing total vault liability against the Paystack settlement balance, allowing for in-flight transfers.
- Django admin read-only views for `Vault`, `VaultTransaction`, and `Withdrawal`. `VaultTransaction` must have **no** add, change, or delete permission for anyone, including superusers — corrections are made by posting an `ADJUSTMENT` entry, never by editing history.

### 4.10 Migrating Existing Data

- Add `Payment.settlement_mode` with values `DIRECT_TRANSFER` | `VAULT`. Backfill every existing row to `DIRECT_TRANSFER`, default new rows to `VAULT`.
- **Do not backfill vault credits for payments already `RELEASED`.** That money has already been transferred to the landlord's bank; crediting it now would pay them twice.
- Create vaults lazily. No data migration needed for users.
- Payments currently in `ESCROW` at deploy time settle into the vault under the new rules. This is the desired outcome and needs no special handling — but tell the landlords affected, because their next release will land in the app rather than their bank.

### 4.11 Acceptance Tests

| Case | Expected |
| :--- | :--- |
| Landlord with no payout account executes an agreement | `200` — no payout error |
| Escrow released with no payout account | `200`, vault credited by `payment.amount` |
| Release called twice for the same payment | One credit only; second call is a no-op or `409` |
| Auto-release job runs twice in the same minute | One credit only |
| Withdraw with no payout account | `403 PAYOUT_ACCOUNT_REQUIRED`, `required_for: WITHDRAWAL` |
| Withdraw more than `available_balance` | `422 INSUFFICIENT_VAULT_BALANCE`, no debit |
| Two concurrent withdrawals of the full balance | Exactly one succeeds; balance never negative |
| Same `Idempotency-Key` replayed | One withdrawal, one transfer, stored response returned |
| `transfer.failed` webhook | Balance restored exactly, `WITHDRAWAL_REVERSAL` posted |
| `transfer.failed` webhook delivered twice | One reversal only |
| Webhook with a bad signature | `401`, nothing changes |
| Paystack down at withdrawal time | `502`, vault balance unchanged |
| Ledger sum vs stored balances after the full suite | Equal to the kobo |
| Tenant calls `GET /vault/` | `403 VAULT_NOT_AVAILABLE_FOR_ROLE` |

---

## 5. Property Photos Become Required

**Requirement as given:** *"When adding a new property, the attached image should be required."*

Scope is the **create-property flow**, and only that. Today `photos` is optional on `POST /properties/`, and the app's add-property sheet marks the photo step `OPTIONAL`, so a landlord can publish a listing with nothing for a tenant to look at.

Two changes make this real, and they have to ship together:

1. **App** — the photo step in the add-property sheet becomes required: the `OPTIONAL` chip becomes `REQUIRED`, and Continue stays disabled until at least one image is attached. Without this the landlord gets a server error they cannot explain.
2. **Backend** — `POST /properties/` rejects a submission with no photos, so the rule holds no matter which client is calling.

### 5.1 Rules

| Rule | Value |
| :--- | :--- |
| Minimum photos at creation | **2** (enforced) |
| Maximum per property | 10 (unchanged) |
| Max size each | 5 MB (unchanged) |
| Accepted types | JPEG, PNG, WEBP (unchanged) |

### 5.2 `POST /properties/` — changed

`photos` moves from optional to required, **minimum two files**. One image tells a tenant almost nothing, and a listing without photos is hidden from the marketplace entirely, so the floor is set where it produces a usable listing.

##### Response `422 Unprocessable Entity`

```json
{
  "code": "VALIDATION_ERROR",
  "detail": "Add at least 2 photos of the property.",
  "errors": {
    "photos": ["At least 2 property photos are required."]
  }
}
```

Validate `photos` **before** touching storage, so a rejected submission does not leave an orphaned verification video or deed in the bucket. The multipart request carries a 100 MB video; failing fast matters.

### 5.3 `DELETE /properties/{id}/photos/{photo_id}/` — changed

Not part of the original request, but without it the rule is one tap away from being bypassed: create with two photos, then delete them. Deleting a photo that would take the property below `PROPERTY_MIN_PHOTOS` returns `409`.

```json
{
  "code": "MINIMUM_PHOTOS_REQUIRED",
  "detail": "A property needs at least 2 photos. Add another before removing this one.",
  "field": "photo_id"
}
```

Status `409`.

### 5.4 Properties That Already Have No Photos

Existing rows cannot be retroactively fixed, and must not 500 or vanish. Add two read-only fields to every property serializer (landlord list, detail, and marketplace):

```json
{
  "photo_count": 0,
  "needs_photos": true
}
```

- `needs_photos` is `true` when `photo_count == 0`. The app uses it to show an "Add photos to publish this listing" prompt on the landlord's own property card.
- Uploading photos through the existing `POST /properties/{id}/photos/` endpoint clears the flag, with no migration needed.
- **Confirmed: `GET /tenant/marketplace/` excludes properties with `photo_count == 0`.** A listing with no photos is not a listing. This is a query filter, not a migration.
- Landlords must be able to rescue an affected listing, so `needs_photos` has to ship **in the same release** as the filter. The app already reads it: a hidden property shows a "Hidden from the marketplace" prompt on the landlord's own property card, with a one-tap upload that posts to the existing `POST /properties/{property_id}/photos/`. Uploading clears the flag and the listing returns with no further action.
- A property hidden this way is otherwise untouched — its units, agreements and payments carry on. It is invisible to tenants browsing, nothing more.

### 5.5 Acceptance Tests

| Case | Expected |
| :--- | :--- |
| Create property with zero photos | `422`, `errors.photos` present, no property row created, no files stored |
| Create property with 1 photo | `422` — below the minimum |
| Create property with 2 photos | `201` |
| Create property with 11 photos | `422`, existing max-count error |
| Delete one of exactly 2 photos | `409 MINIMUM_PHOTOS_REQUIRED` |
| Delete one of three photos | `204` |
| Legacy property with no photos, landlord list | Returned, `needs_photos: true` |
| Legacy property with no photos, marketplace | Absent |
| Legacy property, photos uploaded via `POST .../photos/` | `needs_photos` false, back in the marketplace |

---

## 6. Agreement Visibility — Dashboard Versus Profile

**Requirement as given:** *"The agreements don't need to render in PDF — I just meant move signed agreements from the dashboard to the profile section. It has no purpose there after it has been signed. Only unsigned agreements (not completed) should show in the dashboard."*

No PDF rendering, no document storage, no signed URLs. This is mostly a **Flutter change**. The backend's job is to make the split cheap and unambiguous, so the app is not reimplementing status logic across two screens.

### 6.1 The Split

The agreement status enum has eight values, three of them legacy, which is exactly why the app should not be deciding this client-side.

| Bucket | Statuses | Shown in |
| :--- | :--- | :--- |
| `ACTION_REQUIRED` | `DRAFT`, `PENDING`, legacy `SENT`, legacy `TENANT_SIGNED` | **Dashboard** — something still has to be signed |
| `COMPLETED` | `EXECUTED`, `EXPIRED`, `VOIDED`, legacy `ACTIVATED` | **Profile → My agreements** — a record, not a task |

`PENDING` covers "tenant has signed, landlord has not" as well as "nobody has signed" — both still need a signature, so both stay on the dashboard.

### 6.2 `GET /agreements/` — changed

Two additions. Both are backwards compatible: with no query params the endpoint returns everything exactly as it does today, so the shipped app is unaffected.

##### New query params

| Param | Values | Notes |
| :--- | :--- | :--- |
| `bucket` | `ACTION_REQUIRED` \| `COMPLETED` | What the two screens use |
| `status` | Comma-separated status values, e.g. `?status=PENDING,DRAFT` | For precise queries |

```text
GET /api/users/agreements/?bucket=ACTION_REQUIRED     → dashboard
GET /api/users/agreements/?bucket=COMPLETED           → profile
```

##### New computed fields on every agreement

```json
{
  "id": "69be1df4-cbd1-47cf-b55a-0e2864ef4670",
  "status": "PENDING",
  "bucket": "ACTION_REQUIRED",
  "is_fully_signed": false,
  "awaiting_signature_from": "LANDLORD",
  "signed_at": null
}
```

- `bucket` — server-computed from the table in §6.1. The app switches on this and never has to know that `ACTIVATED` is a legacy synonym for `EXECUTED`.
- `is_fully_signed` — both signature hashes present.
- `awaiting_signature_from` — `"TENANT"`, `"LANDLORD"`, or `null` when nothing is outstanding. Drives the dashboard card's call to action.
- `signed_at` — when the agreement became fully signed; mirrors `executed_at`. Gives the profile list something to sort and label by.

Additive fields only — the Flutter model ignores unknown keys.

### 6.3 One Consequence, Already Handled In The App

**"Pay Rent into Escrow" used to live inside the agreement modal, opened from the dashboard card.** An executed agreement is exactly the one a tenant pays rent from, so moving every executed agreement to the profile would have removed the only route to paying rent.

**Resolved: rent payment now lives on the Payments page.** The app ships a "Rent due" section there, above the ledger, listing executed agreements with no payment started. The dashboard holds only "sign this", the payments page holds "pay this", and the profile holds "what I signed" — each screen has one job.

The app derives that list client-side today, from agreements it already holds. One backend field would make it exact rather than inferred:

Backend support for that is one field on the agreement, so the payments page can render a rent-due row without cross-referencing two lists:

```json
{
  "rent_payment": {
    "status": "DUE",
    "amount": "450000.00",
    "platform_fee": "22500.00",
    "total_amount": "472500.00",
    "payment_id": null
  }
}
```

`status` is `NOT_DUE` (agreement not executed), `DUE` (executed, no payment started), `IN_ESCROW`, `PAID`, or `FAILED`. When a payment exists, `payment_id` points at it.

Without it the app matches payments to agreements by id and treats anything not `FAILED` as settled, which is correct but has to walk both lists. The field is a simplification, not a blocker.

### 6.4 Acceptance Tests

| Case | Expected |
| :--- | :--- |
| `?bucket=ACTION_REQUIRED` with one `PENDING` and one `EXECUTED` agreement | Only the `PENDING` one |
| `?bucket=COMPLETED` | Only the `EXECUTED` one |
| No query params | Both, ordering unchanged |
| Legacy `ACTIVATED` agreement | `bucket: "COMPLETED"` |
| Legacy `TENANT_SIGNED` agreement | `bucket: "ACTION_REQUIRED"`, `awaiting_signature_from: "LANDLORD"` |
| Tenant has signed, landlord has not | `awaiting_signature_from: "LANDLORD"` |
| Executed agreement, no payment yet | `rent_payment.status: "DUE"` |
| `?status=EXECUTED,VOIDED` | Exactly those two statuses |
| `?bucket=NONSENSE` | `422 VALIDATION_ERROR`, not a silent empty list |

---

## 7. Landlord And Tenant Messaging

**Requirement as given:** *"Landlord chat with tenant (uber like) — tenant to landlord only."*

### 7.1 What "Uber-like" Means Here, Concretely

In Uber a chat is not a social feature. It exists **because a trip exists**, it is scoped to that trip, the rider starts it, the driver replies, and it closes when the trip ends. Applied to Oasis:

| Uber | Oasis |
| :--- | :--- |
| A trip creates the thread | An **application** or an **agreement** creates the thread |
| Rider or driver can open the thread | **Either party can start it** — but only against a live relationship |
| Driver replies inside it | Landlord replies inside it |
| Thread dies with the trip | Thread closes when the application is rejected or the tenancy ends |
| No contact list, no search | No user directory. You can only message someone you already have a live relationship with. |

**Confirmed with product:** *either* party can start a conversation, and both can send messages once it is open. The one-way reading of "tenant to landlord only" was checked and rejected.

What stays restricted is **who you are allowed to reach**, and that restriction does all the work: there is no user directory, no search, and no endpoint that accepts a bare user id. A landlord can only open a thread with someone who has applied for one of their units or is already their tenant, and a tenant likewise. Nobody can be messaged out of the blue.

### 7.2 Who May Talk To Whom

A conversation may exist only where there is a live relationship. Check at creation **and** on every send — a relationship can end mid-thread.

| Context | Eligible while |
| :--- | :--- |
| `APPLICATION` | The tenant's application on that landlord's unit is `PENDING` or `APPROVED` |
| `TENANCY` | An agreement between the two is `PENDING` or `EXECUTED`, or ended less than 30 days ago |

There is no other way to reach a user. No search, no user IDs accepted from the client beyond the unit or application being referenced.

When the relationship ends — application `REJECTED`, agreement `VOIDED` or `EXPIRED` past the grace period — the conversation flips to `CLOSED`: still readable by both parties, no new messages, `403 CONVERSATION_CLOSED` on send. History is never deleted; it is evidence in a dispute.

An application-context conversation is **upgraded in place** when that application is approved and becomes a tenancy: same conversation id, `context_type` switches to `TENANCY`, `context_id` points at the agreement, and a system message marks the transition. The tenant does not lose their chat history the moment they become a tenant.

### 7.3 Data Model

```python
class Conversation(models.Model):
    class Context(models.TextChoices):
        APPLICATION = "APPLICATION"
        TENANCY     = "TENANCY"

    class Status(models.TextChoices):
        OPEN   = "OPEN"
        CLOSED = "CLOSED"

    id = models.UUIDField(primary_key=True, default=uuid4, editable=False)
    tenant   = models.ForeignKey(User, on_delete=models.CASCADE, related_name="tenant_conversations")
    landlord = models.ForeignKey(User, on_delete=models.CASCADE, related_name="landlord_conversations")
    property = models.ForeignKey("Property", on_delete=models.CASCADE)
    unit     = models.ForeignKey("Unit", on_delete=models.CASCADE)

    context_type = models.CharField(max_length=16, choices=Context.choices)
    context_id   = models.UUIDField()          # application id or agreement id
    status       = models.CharField(max_length=8, choices=Status.choices, default=Status.OPEN)

    last_message_at      = models.DateTimeField(null=True, db_index=True)
    last_message_preview = models.CharField(max_length=140, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        constraints = [
            models.UniqueConstraint(fields=["tenant", "unit"], name="one_conversation_per_tenant_unit")
        ]
        indexes = [models.Index(fields=["landlord", "-last_message_at"]),
                   models.Index(fields=["tenant", "-last_message_at"])]


class Message(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid4, editable=False)
    conversation = models.ForeignKey(Conversation, on_delete=models.CASCADE, related_name="messages")
    sender = models.ForeignKey(User, null=True, on_delete=models.SET_NULL)  # null = system
    sender_role = models.CharField(max_length=8)      # OWNER | TENANT | SYSTEM
    body = models.TextField(max_length=2000)
    is_system = models.BooleanField(default=False)
    client_message_id = models.CharField(max_length=64, blank=True)
    read_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True, db_index=True)

    class Meta:
        ordering = ["created_at", "id"]
        constraints = [
            models.UniqueConstraint(
                fields=["conversation", "sender", "client_message_id"],
                condition=~models.Q(client_message_id=""),
                name="message_client_idempotency",
            )
        ]
```

The `(tenant, unit)` uniqueness is what makes creation idempotent: a tenant tapping "Message landlord" twice lands in the same thread.

### 7.4 `GET /conversations/`

Both roles. Ordered by `last_message_at` descending, nulls last. Cursor-paginated.

Query params: `status` (`OPEN` | `CLOSED`), `limit`, `cursor`.

```json
{
  "results": [
    {
      "id": "CONVERSATION_UUID",
      "status": "OPEN",
      "context_type": "TENANCY",
      "context_id": "69be1df4-cbd1-47cf-b55a-0e2864ef4670",
      "property": { "id": "PROPERTY_UUID", "name": "Sunset House", "cover_photo_url": "https://..." },
      "unit": { "id": "UNIT_UUID", "unit_number": "A1" },
      "counterparty": {
        "id": "USER_UUID",
        "full_name": "Ada Okafor",
        "role": "TENANT",
        "verification_status": "VERIFIED"
      },
      "last_message": {
        "id": "MESSAGE_UUID",
        "body": "The plumber is coming Thursday morning.",
        "sender_role": "OWNER",
        "created_at": "2026-08-23T12:04:00Z"
      },
      "unread_count": 2,
      "created_at": "2026-08-20T10:00:00Z"
    }
  ],
  "next_cursor": null,
  "has_more": false
}
```

`counterparty` is always the *other* party, resolved per caller — the app never has to work out which of `tenant`/`landlord` it is looking at. Phone numbers are **not** included; contact details stay in the application payload where they already are.

### 7.5 `POST /conversations/`

- **Roles:** `OWNER` and `TENANT`. Both can start a thread, subject to the relationship rules in §7.2.
- Idempotent: an existing conversation for `(tenant, unit)` is returned with `200`, not duplicated — whichever side started it.

```json
{ "unit": "UNIT_UUID" }
```

A tenant sends `unit`, `application`, or `agreement` — any one identifies the relationship, and the backend resolves the landlord itself.

A landlord must identify **which tenant**, since a unit can have several applicants. They send `application` or `agreement`:

```json
{ "application": "APPLICATION_UUID" }
```

A landlord sending only `unit` gets `422 TENANT_NOT_IDENTIFIED` — "Choose which applicant you want to message." Neither role may send a bare `tenant` or `landlord` id; the counterparty is always derived from the application or agreement, which is what makes user enumeration impossible.

`201 Created` (or `200 OK` when it already existed) returns the conversation object from §7.4.

##### Errors

| Code | Status | `detail` |
| :--- | :--- | :--- |
| `NO_RELATIONSHIP` | `403` | Tenant: "You can only message a landlord after applying for one of their units." Landlord: "You can only message someone who has applied for one of your units." |
| `TENANT_NOT_IDENTIFIED` | `422` | "Choose which applicant you want to message." |
| `UNIT_NOT_FOUND` | `404` | "That unit no longer exists." |

### 7.6 `POST /conversations/{id}/messages/`

- **Roles:** both parties to an `OPEN` conversation
- **Rate limit:** 20/minute per user, `429` with `Retry-After`
- **Idempotency:** `client_message_id` in the body — a UUID the app generates so an optimistic bubble can be reconciled and a retry on a flaky network cannot post twice

```json
{
  "body": "Is the unit still available for September?",
  "client_message_id": "b2f1c0de-2f5f-4a7c-9c58-9d2f0a5f3c11"
}
```

##### Response `201 Created`

```json
{
  "id": "MESSAGE_UUID",
  "conversation": "CONVERSATION_UUID",
  "body": "Is the unit still available for September?",
  "sender_role": "TENANT",
  "sender_name": "Ada Okafor",
  "is_system": false,
  "client_message_id": "b2f1c0de-2f5f-4a7c-9c58-9d2f0a5f3c11",
  "read_at": null,
  "created_at": "2026-08-23T12:00:00Z"
}
```

`body` is trimmed, must be 1–2000 characters after trimming, and is stored as plain text. No HTML, no markdown rendering, no attachments in this batch — call it out to product rather than half-building file uploads.

##### Errors

| Code | Status | `detail` |
| :--- | :--- | :--- |
| `CONVERSATION_CLOSED` | `409` | "This conversation is closed." |
| `MESSAGE_TOO_LONG` | `422` | "Messages are limited to 2,000 characters." |
| `TOO_MANY_REQUESTS` | `429` | "You're sending messages too quickly. Wait a moment." |

### 7.7 `GET /conversations/{id}/messages/`

Cursor-paginated **in both directions**, which is what a chat needs:

- `?before=<cursor>` — older messages, for scrolling up through history. Default when neither is given: the newest 50.
- `?after=<message_id>` — anything newer than a known message, for polling.

```json
{
  "results": [],
  "next_cursor": "eyJpZCI6...",
  "has_more": true,
  "latest_message_id": "MESSAGE_UUID"
}
```

Support `ETag` / `If-None-Match` on the `?after=` form and return `304 Not Modified` with an empty body when nothing is new. With a 4-second poll and a handful of open threads this is the difference between a cheap feature and a Render bill.

### 7.8 `POST /conversations/{id}/read/`

```json
{ "up_to_message_id": "MESSAGE_UUID" }
```

Marks every message from the counterparty at or before that id as read. Returns `{"unread_count": 0}`. Omitting the body marks the whole conversation read.

### 7.9 `GET /conversations/unread-count/`

```json
{ "unread_count": 3, "conversations_with_unread": 2 }
```

Cheap enough to poll for the tab badge. One indexed count query — do not serialise conversations for this.

### 7.10 Realtime

**This batch: polling.** The app polls `?after=` every 4 seconds while a conversation is open, and refreshes the list on app resume. The `304` path above makes that sustainable.

**Next batch: WebSockets.** `wss://<host>/ws/conversations/{id}/` with Django Channels, JWT in the connect query string, Redis channel layer. Worth planning for — Render's free tier does not hold WebSockets open reliably, so this needs a paid instance and should not be promised in the same release as the REST endpoints.

Push notifications are out of scope here; §9's `MESSAGE_RECEIVED` notification is what the app surfaces in the meantime.

### 7.11 System Messages

Messages with `is_system: true` and `sender: null`, posted by the backend, rendered as a centred grey line rather than a bubble. They give the thread the same "the trip started / the trip ended" spine Uber's chat has:

| Trigger | Body |
| :--- | :--- |
| Conversation created | "This conversation is about Unit A1 at Sunset House." |
| Application approved | "Your application was approved. This is now your tenancy chat." |
| Application rejected | "This application was closed. You can no longer send messages." |
| Agreement executed | "Tenancy agreement signed by both parties." |
| Rent paid into escrow | "Rent payment received and held in escrow." |
| Tenancy ended | "This tenancy has ended. This conversation is now read-only." |

### 7.12 Abuse And Safety

- Rate limits per §7.6.
- A `POST /conversations/{id}/report/` endpoint taking `{reason, message_id?}`, writing a `ConversationReport` row for admin review. Cheap now, essential the first time it is needed.
- Landlords cannot enumerate tenants: no endpoint accepts a bare user id, and `counterparty` exposes only name, role, and verification status.
- Log message *metadata* (ids, timestamps, sizes) but never message bodies in application logs.

### 7.13 Acceptance Tests

| Case | Expected |
| :--- | :--- |
| Tenant with a pending application starts a chat | `201` |
| Same tenant taps again | `200`, same conversation id |
| Landlord starts a chat from an application | `201` |
| Landlord starts a chat the tenant already started | `200`, same conversation id |
| Landlord sends only `unit` with three applicants | `422 TENANT_NOT_IDENTIFIED` |
| Landlord targets another landlord's application | `403 NO_RELATIONSHIP` |
| Tenant with no application on that unit | `403 NO_RELATIONSHIP` |
| Landlord replies in an open conversation | `201` |
| Either party sends after the application is rejected | `409 CONVERSATION_CLOSED` |
| Application approved | Same conversation, `context_type: TENANCY`, system message present |
| Same `client_message_id` posted twice | One message, `201` then the stored `201` |
| `?after=` with nothing new and a matching `ETag` | `304`, empty body |
| Unread count after the counterparty reads | `0` |
| 21 messages in a minute | `429` with `Retry-After` |
| Non-party requests messages | `404` (not `403` — do not confirm the conversation exists) |

---

## 8. Landlord Broadcast Messages

**Requirement as given:** *"Broadcast messages for landlord — add in notifications."*

A landlord announces something to their tenants — a water schedule, a gate code change, a service charge reminder — and it lands in each tenant's **notification list**, not in a chat thread. Broadcasts are one-way and are not conversations. A tenant who wants to reply opens a chat (§7) — the notification carries `data.unit_id` so the app can offer "Message landlord" straight from it.

### 8.1 Audience

| `audience` | Recipients |
| :--- | :--- |
| `ALL_TENANTS` | Every tenant with an `EXECUTED`, unexpired agreement with this landlord |
| `PROPERTY` | Those tenants, filtered to one property (`property` required) |
| `UNITS` | Those tenants, filtered to an explicit unit list (`units` required, max 50) |

Only tenants with a live tenancy — never applicants, never past tenants. A landlord cannot broadcast to someone who merely applied.

### 8.2 `POST /landlord/broadcasts/`

- **Auth:** Required, verified, `OWNER`
- **Rate limit:** 5 per day per landlord, `429 BROADCAST_LIMIT_REACHED`
- **Header:** `Idempotency-Key` recommended

```json
{
  "audience": "PROPERTY",
  "property": "PROPERTY_UUID",
  "title": "Water supply maintenance",
  "body": "The borehole pump will be serviced on Saturday between 9am and 2pm. Please store water ahead of time."
}
```

- `title` 1–80 characters, `body` 1–1000 characters, both plain text.
- No attachments, no links rendered as links.

##### Response `201 Created`

```json
{
  "id": "BROADCAST_UUID",
  "audience": "PROPERTY",
  "property": { "id": "PROPERTY_UUID", "name": "Sunset House" },
  "units": [],
  "title": "Water supply maintenance",
  "body": "The borehole pump will be serviced on Saturday between 9am and 2pm. Please store water ahead of time.",
  "recipient_count": 12,
  "read_count": 0,
  "created_at": "2026-08-23T08:00:00Z"
}
```

Fan-out happens in a background task when `recipient_count > 25`; the response returns immediately with the computed count. Each recipient gets **one** notification row (§9), created in a single `bulk_create` inside a transaction.

##### Errors

| Code | Status | `detail` |
| :--- | :--- | :--- |
| `NO_RECIPIENTS` | `422` | "You don't have any tenants to send this to yet." |
| `BROADCAST_LIMIT_REACHED` | `429` | "You've sent 5 broadcasts today. Try again tomorrow." |
| `PROPERTY_NOT_OWNED` | `403` | "You can only message tenants in your own properties." |
| `BODY_TOO_LONG` | `422` | "Broadcasts are limited to 1,000 characters." |

### 8.3 `GET /landlord/broadcasts/`

The landlord's sent history, newest first, cursor-paginated. Same object as above, with `read_count` kept current so the landlord can see uptake:

```json
{
  "results": [
    {
      "id": "BROADCAST_UUID",
      "title": "Water supply maintenance",
      "body": "The borehole pump will be serviced…",
      "audience": "PROPERTY",
      "property": { "id": "PROPERTY_UUID", "name": "Sunset House" },
      "recipient_count": 12,
      "read_count": 7,
      "created_at": "2026-08-23T08:00:00Z"
    }
  ],
  "next_cursor": null,
  "has_more": false
}
```

`GET /landlord/broadcasts/{id}/` adds a `recipients` array of `{tenant_name, unit_number, read_at}` — capped at 200 entries — for a delivery-detail view.

### 8.4 Content Rules

Broadcasts reach people who did not opt in, so the rules need to be in the API, not only in the terms:

- Every broadcast is retained and attributable to the landlord. Nothing is anonymous.
- A `POST /notifications/{id}/report/` endpoint lets a tenant flag a broadcast; three upheld reports suspend a landlord's broadcast privilege pending review.
- Broadcasts are for property matters. Marketing another landlord's listings, or anything unrelated to the tenancy, is a terms violation — enforced by review, but the audit trail above is what makes review possible.

### 8.5 Acceptance Tests

| Case | Expected |
| :--- | :--- |
| Landlord with 12 tenants sends `ALL_TENANTS` | `201`, `recipient_count: 12`, 12 notification rows |
| Landlord with no tenants | `422 NO_RECIPIENTS` |
| `PROPERTY` audience for another landlord's property | `403 PROPERTY_NOT_OWNED` |
| Sixth broadcast in a day | `429 BROADCAST_LIMIT_REACHED` |
| Tenant of two of the landlord's units, `ALL_TENANTS` | One notification, not two |
| Tenant opens the notification | `read_count` increments once, not per open |
| Past tenant (expired agreement) | Not a recipient |
| Tenant calls `POST /landlord/broadcasts/` | `403` |

---

## 9. Notification Model Changes

Messaging (§7) and broadcasts (§8) both deliver into the existing notification list, which currently carries only `notification_type`, `message`, `is_read`, and `created_at`. That is not enough to render a broadcast with a title, or to deep-link into a conversation.

### 9.1 New Fields

Additive only. The shipped Flutter build reads `id`, `notification_type`, `message`, `is_read`, `created_at` and ignores everything else, so nothing breaks.

```json
{
  "id": "NOTIFICATION_UUID",
  "notification_type": "LANDLORD_BROADCAST",
  "title": "Water supply maintenance",
  "message": "The borehole pump will be serviced on Saturday between 9am and 2pm.",
  "actor_name": "Mr Adeyemi",
  "is_read": false,
  "created_at": "2026-08-23T08:00:00Z",
  "data": {
    "broadcast_id": "BROADCAST_UUID",
    "property_id": "PROPERTY_UUID",
    "property_name": "Sunset House",
    "conversation_id": null
  }
}
```

- `title` — short heading. For existing types, populate it with the human label the app already shows (`"Agreement executed"`, `"Payment recorded"`) so nothing renders untitled.
- `message` — **keep populating it exactly as today.** For a broadcast, it is the broadcast body. The old app shows this field and only this field.
- `actor_name` — who caused it, when there is a person. `null` for system events.
- `data` — a typed bag for deep links. Keys vary by type; the app treats missing keys as absent, never as an error.

### 9.2 New Types

Added to the `notification_type` enum:

| Type | Sent to | `data` keys |
| :--- | :--- | :--- |
| `LANDLORD_BROADCAST` | Tenant | `broadcast_id`, `property_id`, `property_name`, `unit_id` |
| `MESSAGE_RECEIVED` | Either party | `conversation_id`, `message_id`, `unit_number` |
| `VAULT_CREDITED` | Landlord | `vault_transaction_id`, `payment_id`, `amount` |
| `WITHDRAWAL_PAID` | Landlord | `withdrawal_id`, `amount`, `bank_name` |
| `WITHDRAWAL_FAILED` | Landlord | `withdrawal_id`, `amount`, `failure_reason` |

> The Flutter enum maps unknown types to `unknown` and still renders them with a default icon, so the app does not have to ship on the same day. Ship the backend first.

### 9.3 Message Notification Throttling

One notification per message would make the list unusable during a back-and-forth. Rule: **at most one `MESSAGE_RECEIVED` per conversation per 15 minutes**, and none at all while the recipient has that conversation open (the app suppresses by calling `POST /conversations/{id}/read/` on the newest message). If an unread `MESSAGE_RECEIVED` for that conversation already exists, update its `message`, `data.message_id`, and `created_at` in place instead of creating another.

### 9.4 Filters

`GET /notifications/?type=` already exists and keeps working for the new values. Add `?since=<ISO timestamp>` for cheap polling and `GET /notifications/unread-count/` for the bell badge.

---

## 10. Endpoint Checklist

### 10.1 New

| Feature | Method | Path | Roles |
| :--- | :--- | :--- | :--- |
| Resolve bank account | `POST` | `/api/users/payout-account/resolve/` | `OWNER` |
| Vault summary | `GET` | `/api/users/vault/` | `OWNER` |
| Vault ledger | `GET` | `/api/users/vault/transactions/` | `OWNER` |
| Withdrawal quote | `GET` | `/api/users/vault/withdrawals/quote/` | `OWNER` |
| Request withdrawal | `POST` | `/api/users/vault/withdrawals/` | `OWNER` |
| List withdrawals | `GET` | `/api/users/vault/withdrawals/` | `OWNER` |
| Withdrawal detail | `GET` | `/api/users/vault/withdrawals/{id}/` | `OWNER` |
| List conversations | `GET` | `/api/users/conversations/` | `OWNER`, `TENANT` |
| Start conversation | `POST` | `/api/users/conversations/` | `OWNER`, `TENANT` |
| Conversation detail | `GET` | `/api/users/conversations/{id}/` | Parties |
| List messages | `GET` | `/api/users/conversations/{id}/messages/` | Parties |
| Send message | `POST` | `/api/users/conversations/{id}/messages/` | Parties |
| Mark conversation read | `POST` | `/api/users/conversations/{id}/read/` | Parties |
| Unread message count | `GET` | `/api/users/conversations/unread-count/` | `OWNER`, `TENANT` |
| Report a conversation | `POST` | `/api/users/conversations/{id}/report/` | Parties |
| Send broadcast | `POST` | `/api/users/landlord/broadcasts/` | `OWNER` |
| List broadcasts | `GET` | `/api/users/landlord/broadcasts/` | `OWNER` |
| Broadcast detail | `GET` | `/api/users/landlord/broadcasts/{id}/` | `OWNER` |
| Unread notification count | `GET` | `/api/users/notifications/unread-count/` | `OWNER`, `TENANT` |
| Report a notification | `POST` | `/api/users/notifications/{id}/report/` | `TENANT` |

### 10.2 Changed

| Endpoint | Change | Section |
| :--- | :--- | :--- |
| `GET /banks/` | Adds `code` and `slug`; sourced from the same cached provider list as resolution | §3.4 |
| `POST /payout-account/` | Ignores `account_name`; accepts `resolution_token`; new error codes; `409` on duplicate | §3.3 |
| `PATCH /payout-account/` | Becomes an upsert | §3.3 |
| `POST /properties/` | `photos` required, min 1 | §5.2 |
| `DELETE /properties/{id}/photos/{photo_id}/` | `409` on the last photo | §5.3 |
| Property serializers | Add `photo_count`, `needs_photos` | §5.4 |
| `GET /tenant/marketplace/` | Excludes properties with no photos | §5.4 |
| `GET /agreements/` | Adds `?bucket=` and `?status=` filters; adds `bucket`, `is_fully_signed`, `awaiting_signature_from`, `signed_at`, `rent_payment` | §6.2 |
| `POST /agreements/{id}/sign/` | **Payout gate removed** | §4.7 |
| `POST /payments/{id}/release/` | **Payout gate removed**; credits the vault; adds `settlement_mode`, `vault_credit` | §4.4 |
| `GET /profile/` | `can_execute_agreements` no longer payout-dependent; `payout_account_required_for` becomes `WITHDRAWAL` | §4.7 |
| `GET /notifications/` | Adds `title`, `actor_name`, `data`; new types; `?since=` filter | §9 |
| `POST /webhooks/paystack/` | Handles `transfer.success`, `transfer.failed`, `transfer.reversed` | §4.6 |

---

## 11. What The App Already Does

The Flutter side of this batch is built and merged. Three parts work against the **current** backend and are live now; the rest are wired up and waiting on the endpoints in this document.

### Working against today's API

| Change | How |
| :--- | :--- |
| Photos required | Client-side validation in the add-property sheet: the chip reads `REQUIRED`, and submission is blocked below **2** photos. §5 makes the rule stick server-side. |
| Dashboard / profile split | The app computes `bucket` locally from status and signature data, and prefers the backend's `bucket` field the moment it appears. §6.2 turns it into a server-side filter. |
| Rent due on Payments | Derived from agreements and payments the app already fetches. §6.3. |

### Built, waiting on the backend

| Change | What the app does until the endpoint exists |
| :--- | :--- |
| Vault | The balance card renders an "unavailable" state rather than a zero balance — showing ₦0 would read as "your money is gone". |
| Withdrawals | Sheet, server-quoted fee breakdown and idempotency keys all in place. |
| Payout resolve | The screen tries `POST /payout-account/resolve/`; on a 404 it falls back to the current typed-name flow, so **shipping the app before the endpoint changes nothing**. |
| Messaging | Inbox, thread, polling and optimistic sends are built. Entry points sit on the application cards for both roles. |
| Broadcasts | Composer is in the notifications screen behind a landlord-only action. |
| Hidden-listing rescue | The landlord's property card reads `needs_photos` and shows a "Hidden from the marketplace" prompt with one-tap upload. Falls back to `photo_count == 0` until the field ships, so it works either way. |

Two notes for whoever picks up the backend:

- **`Idempotency-Key` is already being sent** on `POST /vault/withdrawals/`, and the same key is reused across retries of one intent. The server side of that contract needs to exist before withdrawals go live, or a retry over a bad connection will pay out twice.
- **`client_message_id` is already being sent** on every message, for the same reason.

---

## 12. Rollout

### 12.1 Order

The app in the field must keep working at every step. Nothing here requires a coordinated app release except where noted.

| Step | Ships | Safe alone? |
| :--- | :--- | :--- |
| 1 | §3 payout fix + `/banks/` codes | Yes — pure fix, old request body still accepted |
| 2 | §5 photo requirement | Yes — the app already blocks submission without a photo, so the server rule can land whenever. |
| 3 | §4 vault, with `AUTO_RELEASE_ESCROW=False` | Yes — the vault fills via manual release, withdrawals work. Staging only: auto-release is the intended production behaviour and must not stay off. |
| 4 | §9 notification fields | Yes — additive |
| 5 | §6 agreement filters | Yes — additive params and fields. The app can move the lists whenever it ships. |
| 6 | §7 messaging | Yes — new endpoints only |
| 7 | §8 broadcasts | Needs step 4 |
| 8 | Flip `AUTO_RELEASE_ESCROW=True` | After watching step 3 in staging for a few days. **This is the shipped behaviour, not an experiment.** |

### 12.2 What Would Break The Shipped App

Checked against the current Flutter source. Avoid these:

| Do not | Because |
| :--- | :--- |
| Paginate `GET /payments/`, `/agreements/`, `/notifications/`, `/properties/`, `/tenant/marketplace/` | `PaymentService`, `AgreementService` and friends do `if (response is List)` and return `[]` for anything else. A `{results: []}` wrapper renders as an empty screen with no error. |
| Add a `payout_account_status` value outside the documented six | `PayoutAccountStatus.fromString` maps anything unknown to `UNKNOWN`, which the UI treats as "needs setup" and blocks the landlord. |
| Return an unmasked account number | The UI renders `account_number` verbatim. |
| Change money fields to numbers | `OasisCurrency` formats decimal **strings** textually and never parses to double. A JSON number changes the rendered value. |
| Drop `detail` from the payout `MISSING` envelope | It is shown as the explanatory line on the payout screen. |
| Return `403 CONSENT_REQUIRED` from a new endpoint without meaning it | `ApiClient` routes that specific shape to the consent screen. |

Adding fields is always safe — every model parses defensively and ignores unknown keys.

### 12.3 Settings To Add

```python
# Vault
AUTO_RELEASE_ESCROW = True
VAULT_MIN_WITHDRAWAL = Decimal("1000.00")
VAULT_MAX_WITHDRAWAL_PER_TXN = Decimal("5000000.00")
VAULT_MAX_WITHDRAWALS_PER_DAY = 5
VAULT_WITHDRAWAL_FEE_FLAT = Decimal("50.00")
WITHDRAWAL_LOCK_HOURS_AFTER_ACCOUNT_CHANGE = 24

# Messaging
MESSAGING_MAX_MESSAGE_LENGTH = 2000
MESSAGING_RATE_PER_MINUTE = 20
MESSAGING_TENANCY_GRACE_DAYS = 30

# Broadcasts
BROADCAST_MAX_PER_DAY = 5
BROADCAST_MAX_BODY_LENGTH = 1000

# Properties
PROPERTY_MIN_PHOTOS = 2
PROPERTY_MAX_PHOTOS = 10
```

Infrastructure this batch assumes: a background worker (Celery + Redis, or `django-q`) for broadcast fan-out and the escrow-release cron. Nothing else new — no PDF renderer and no additional storage, now that agreements are a filter rather than a document store.

---

## 13. Product Decisions

Every open question from the first draft has been answered. Recorded here so the reasoning survives the meeting.

| Question | Decision |
| :--- | :--- |
| Chat direction | **Either party can start a conversation**, both can send. Restriction is on *who is reachable* — only the counterparty of a live application or tenancy — not on who speaks first. §7 |
| Payout and agreements | **Landlords create, send and execute agreements with no payout account.** §4.7 |
| Signed agreements | **No PDF.** They move off the dashboard into the profile as a filtered list. §6 |
| Where rent is paid | **The Payments page.** Already shipped in the app. §6.3 |
| Withdrawal fee | **Whatever the provider charges**, resolved per amount at quote time. No Oasis margin, no hardcoded figure. §4.8 |
| Escrow release | **Automatic** when the dispute window closes. The landlord never taps anything to be paid. §4.4 |
| Listings with no photos | **Hidden from the marketplace**, with a landlord-facing prompt and one-tap upload to fix it. Both ship together. §5.4 |
| Minimum photo count | **2**, enforced at creation and on deletion. §5.1 |
| Withdrawal OTP | **Yes, before real money.** Not in this batch — the vault runs in demo mode on test keys until it lands. §4.8 |
| Tenant vaults | **Not now.** Refunds go back to the card. A tenant balance is a later phase, not a variation of this one. §4.5 |

### The one thing still worth flagging

The OTP deferral is the only decision in this table that carries risk into production. A vault with money in it and no second factor on withdrawal is a single compromised password away from being drained, and the 24-hour lock after a bank-account change (§4.8) only covers the case where the attacker changes the destination — not the case where they withdraw to an account the landlord already added.

Demo mode on test keys is a complete answer to that. Going live is not, until the confirm step exists.

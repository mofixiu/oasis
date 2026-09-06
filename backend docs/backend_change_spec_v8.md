# Landa OS Backend Change Specification — v8

> **Audience:** Backend developer implementing the Django API (`landa_os`, `users` app).
>
> **Companion:** `flutter_api_guide (15).md` documents the deployed API. Update its Short Let and enum sections as part of this change, then publish the next revision of the guide.
>
> **Status:** Required contract correction. This supersedes v7 §2.4 and §7 where they concern short-let payment allocation and booking-status vocabulary.

---

## 1. Decision summary

A short-let charge contains three different amounts. They must not be represented as one escrowed stay payment.

| Amount | Owner after a successful payment | Holding rule |
| :--- | :--- | :--- |
| `amount - platform_fee` | Landlord | Credit the landlord vault **immediately**. |
| `platform_fee` | Landa/platform | Account for it immediately through the normal platform flow. |
| `caution_fee` | Tenant | Hold it as a separate refundable caution-fee escrow until checkout or claim resolution. |

`total_amount` remains the amount charged to the tenant:

```text
total_amount = (amount - platform_fee) + platform_fee + caution_fee
```

The important consequence is simple: **the stay payment is never a landlord escrow balance.** A landlord must not wait for checkout, an escrow-release command, or a manual operation to access the accommodation payout.

---

## 2. Data model and accounting

### 2.1 Booking snapshot

Keep or add these immutable booking fields, populated when the booking is created or approved according to the existing pricing boundary:

```python
amount = models.DecimalField(max_digits=12, decimal_places=2)
platform_fee = models.DecimalField(max_digits=12, decimal_places=2)
caution_fee = models.DecimalField(max_digits=12, decimal_places=2, default=Decimal("0.00"))
total_amount = models.DecimalField(max_digits=12, decimal_places=2)
```

The values must satisfy the equation above. Do not recalculate the caution fee from the listing during payment: a later edit to a listing must not change an existing booking's debt.

### 2.2 Separate caution-fee escrow record

Represent a non-zero caution fee separately from the booking's stay-payment lifecycle. It may be a dedicated `ShortLetCautionFeeEscrow` model or an equivalently isolated ledger record, but it must contain at least:

```python
booking                 # one-to-one
tenant
amount
status                  # see §4.2
held_at
release_ready_at        # checkout confirmation time, unless a claim/dispute blocks it
released_at             # null until credited back to tenant
claim_or_dispute_id     # nullable
```

Create no escrow record when `caution_fee == 0`. A zero caution fee is not an escrow with a zero balance.

### 2.3 Successful payment transaction

On a verified card payment or successful vault payment, make the following state changes atomically and idempotently:

1. Mark the short-let payment successful and the booking `PAID`.
2. Credit `amount - platform_fee` to the landlord vault.
3. Record `platform_fee` in the platform revenue ledger.
4. Create and fund the separate caution-fee escrow only when `caution_fee > 0`.
5. Persist ledger/source references that prevent a retry, webhook replay, or verify replay from crediting any amount twice.

If the provider confirmation is repeated, return the existing successful payment/allocation. Do not create a second landlord credit or a second caution-fee escrow.

### 2.4 Checkout, release, dispute and refund

At confirmed checkout, release the caution-fee escrow to the **tenant** vault when no damage claim or dispute is active. Set `caution_fee_refunded_at` on the booking at the same time.

If there is a claim or dispute, keep only the caution fee on hold until resolution. It must not undo, suspend, or silently claw back the landlord's already released accommodation payout. Any full-stay refund, partial refund, or recovery requires its own explicit audited operation; it is out of scope for automatic checkout release but is required for the cancellation contract in §3.3.

Rename `release_ready_shortlet_escrows` to `release_ready_caution_fee_escrows` when safe. During rollout, retain the old command as a compatibility alias, but it must release only eligible caution-fee escrows into tenant vaults. It must never create a landlord payout.

---

## 3. API contract

### 3.1 Payment and booking payloads

Expose the allocation explicitly on short-let payment and booking detail payloads. Decimal values are strings.

```json
{
  "status": "PAID",
  "amount": "100000.00",
  "platform_fee": "5000.00",
  "landlord_payout": "95000.00",
  "caution_fee": "25000.00",
  "total_amount": "125000.00",
  "landlord_paid_at": "2026-09-03T10:00:00Z",
  "caution_fee_escrow_status": "IN_ESCROW",
  "caution_fee_release_ready_at": "2026-09-06T11:00:00Z",
  "caution_fee_refunded_at": null
}
```

Rules:

- `landlord_payout` is exactly `amount - platform_fee`.
- `landlord_paid_at` is set as part of successful payment, not checkout.
- `caution_fee_escrow_status`, `caution_fee_release_ready_at`, and `caution_fee_refunded_at` are `null` when `caution_fee` is `"0.00"`.
- Booking list payloads may omit detailed timestamps, but must include `status`, `caution_fee`, `caution_fee_escrow_status`, and `caution_fee_refunded_at` so Flutter can render an honest summary.
- Never overload a generic `escrow_release_at` to mean both a rent-payment escrow and a short-let caution-fee release.

### 3.2 Failed payment

A provider failure must leave the booking in `APPROVED` while its approval window remains valid. The tenant may retry `POST /tenant/short-let-bookings/{id}/pay/`; the failed payment attempt is retained for audit but does not become a booking status.

When the approval window expires, transition the booking to `EXPIRED`. A tenant cannot pay an expired booking and must make a new request. This avoids undocumented states such as `PAYMENT_FAILED`, `FAILED`, `AWAITING_PAYMENT`, `PENDING_PAYMENT`, or `PROCESSING` on `ShortLetBooking.status`.

### 3.3 Optional landlord cancellation and refund policy

Short-let hosts may set a cancellation policy per listing. Landa provides the policy framework, clear disclosure and dispute handling; it does **not** impose one rigid refund rule on every property.

When a host has not selected a policy, apply the platform default `FLEXIBLE`. The default must be shown in the listing and checkout exactly as a host-selected policy would be. A listing may not have an unknown or blank cancellation policy.

Initial v1 policy choices:

| Value | Tenant cancellation outcome |
| :--- | :--- |
| `FLEXIBLE` | Full accommodation refund when cancelled at least 24 hours before check-in; no accommodation refund inside 24 hours. |
| `MODERATE` | Full accommodation refund when cancelled at least 5 days before check-in; 50% accommodation refund from 5 days to 24 hours before check-in; no accommodation refund inside 24 hours. |
| `STRICT` | Full accommodation refund when cancelled at least 14 days before check-in; 50% accommodation refund from 14 days to 7 days before check-in; no accommodation refund inside 7 days. |
| `NON_REFUNDABLE` | No accommodation refund after payment, except when Landa or the property cancels, or an approved exceptional-circumstances case applies. |

These windows and percentages are a product decision, so keep them server-configured rather than hard-coded in Flutter. Future policies may be added without changing the API shape.

The caution fee is **not** the host's cancellation charge. If a paid booking is cancelled before check-in and no damage claim is possible, refund the full caution fee to the tenant regardless of the listing's accommodation-refund policy. `platform_fee` should be refunded or retained only under an explicit platform-fee rule included in the quote; do not make Flutter infer it.

#### Listing and booking fields

Add to `ShortLetListing`:

```python
cancellation_policy = models.CharField(
    max_length=20,
    choices=CANCELLATION_POLICY_CHOICES,
    default="FLEXIBLE",
)
```

The host sends `cancellation_policy` on `POST /landlord/short-lets/`. It is optional in the request; omission selects `FLEXIBLE`. Existing listings must be backfilled to `FLEXIBLE` before the field is made non-null.

Snapshot the complete policy on `ShortLetBooking` when the booking is made, including its version and the calculated cutoff times. The host changing a listing later must not reduce a tenant's refund entitlement after the tenant has requested or paid for a stay.

Every listing response includes:

```json
{
  "cancellation_policy": "MODERATE",
  "cancellation_policy_summary": "Free cancellation until 5 days before check-in; 50% refund until 24 hours before check-in."
}
```

Every booking quote/detail includes the snapshot plus the refund currently available at the server's current time:

```json
{
  "cancellation_policy": "MODERATE",
  "cancellation_policy_version": 1,
  "accommodation_refund_amount": "47500.00",
  "platform_fee_refund_amount": "0.00",
  "caution_fee_refund_amount": "25000.00",
  "total_refund_amount": "72500.00",
  "cancellation_deadlines": {
    "full_refund_until": "2026-09-10T14:00:00Z",
    "partial_refund_until": "2026-09-14T14:00:00Z"
  }
}
```

The backend is authoritative for eligibility and amounts. Flutter displays these values but never calculates time windows, money, or timezone boundaries itself.

#### Cancellation routes and exceptional cases

Extend `POST /tenant/short-let-bookings/{id}/cancel/` to support paid bookings before check-in. It calculates and returns the server-authoritative refund allocation, creates the corresponding explicit refund/recovery operations idempotently, and sets the booking to `CANCELLED` when cancellation completes. The accommodation refund must be an audited debit/recovery against the prior landlord payout (or a documented platform-funded advance with a receivable); it must not be silently taken from or left unaccounted in the caution-fee escrow.

Add a landlord cancellation endpoint:

```text
POST /api/users/landlord/short-let-bookings/{booking_id}/cancel/
```

A property-initiated cancellation always returns the tenant's full `total_amount`, including accommodation, platform fee and caution fee, and requires a reason. It must create an audit record and a high-priority tenant notification. Repeated host cancellations should be measurable for quality enforcement.

Provide an exceptional-circumstances/support path for safety, access failure, material misrepresentation, force majeure, and no-show disputes. It must be reviewed and audited; it must not be implemented as an undocumented client-side override of a host policy.

For no-shows, the listing policy controls the accommodation refund unless Landa approves an exceptional case. The caution fee follows the separate caution-fee rules: it is returned unless a valid, documented claim/dispute requires it to remain held.

#### Transparent price and marketplace incentive

The tenant must see, before payment: nightly accommodation price, any Landa platform fee, caution fee, `total_amount`, and the cancellation-policy summary. The payment receipt must expose the same allocation.

Landa may negotiate a property rate or fund a promotion to make a stay cheaper, but the accounting must remain explicit. For example, on a ₦100,000 accommodation charge with a ₦15,000 platform fee, the landlord payout is ₦85,000. If Landa offers a tenant discount, include `discount_amount`, `discount_funded_by` (`PLATFORM` or `LANDLORD`), and the resulting amounts in the quote and receipt. A discount must never be hidden by changing the landlord payout after payment.

---

## 4. Short-let booking status vocabulary

### 4.1 Booking status is a booking lifecycle, not a money bucket

Add this exact row to the API guide's enum table:

| Enum | Values |
| :--- | :--- |
| Short-let booking `status` | `PENDING`, `REQUESTED`, `APPROVED`, `PAID`, `CHECKED_OUT`, `COMPLETED`, `DISPUTED`, `REJECTED`, `DECLINED`, `CANCELLED`, `CANCELED`, `EXPIRED` |

| Value | Meaning / permitted tenant action |
| :--- | :--- |
| `PENDING`, `REQUESTED` | Awaiting host decision; tenant may cancel. |
| `APPROVED` | Awaiting payment before the approval deadline; tenant may pay or cancel. |
| `PAID` | Payment succeeded, landlord accommodation payout was released, and the stay is active or upcoming. |
| `CHECKED_OUT`, `COMPLETED` | Stay ended; caution fee has been released or is in its separately reported resolution flow. |
| `DISPUTED` | Caution-fee dispute/claim is under review; no automatic caution-fee release. |
| `REJECTED`, `DECLINED` | Host declined the request. |
| `CANCELLED`, `CANCELED` | Tenant cancelled; a paid cancellation carries its explicit refund allocation. |
| `EXPIRED` | Approval window elapsed without a successful payment. |

`PENDING`/`REQUESTED`, `REJECTED`/`DECLINED`, `CANCELLED`/`CANCELED`, and `CHECKED_OUT`/`COMPLETED` remain read compatibility aliases until persisted records are migrated. New responses should use, respectively: `REQUESTED`, `REJECTED`, `CANCELLED`, and `COMPLETED`.

### 4.2 One spelling for the separate escrow state

**Canonical choice: `IN_ESCROW`.** It is the only accepted value for `caution_fee_escrow_status` in newly written records and newly emitted responses.

`ESCROW` is a legacy read alias only. It must be normalized to `IN_ESCROW` at the API boundary during rollout and must not be produced by new database transitions, serializers, jobs, or documentation.

Suggested caution-fee escrow enum:

| Value | Meaning |
| :--- | :--- |
| `IN_ESCROW` | Caution fee funded and held for the tenant. |
| `RELEASED` | Caution fee credited to the tenant after checkout. |
| `DISPUTED` | A claim or dispute prevents automatic release. |
| `RESOLVED` | Claim/dispute resolved; response must include the outcome/refund allocation. |

Neither `ESCROW` nor `IN_ESCROW` belongs in a new short-let **booking** `status` response. A booking with a funded caution fee is `PAID`, with `caution_fee_escrow_status: "IN_ESCROW"` alongside it.

### 4.3 Explicitly unsupported booking-status values

The backend must confirm via a data audit that the following values do not exist in `ShortLetBooking.status`, in historical rows, serializer output, jobs, webhook paths, or tests:

```text
PAYMENT_FAILED
FAILED
AWAITING_PAYMENT
PENDING_PAYMENT
PROCESSING
REFUNDED
ESCROW
IN_ESCROW
RELEASED
```

If any exist, migrate them under an explicit, reviewed mapping before the API guide is published. Do not make Flutter infer their meaning from prose.

---

## 5. Migration and release checklist

1. Audit distinct short-let booking statuses in production and staging, including archived records and webhook-created rows.
2. Add the caution-fee escrow ledger/model and unique constraints/source references needed for payment idempotency.
3. Backfill each existing paid short-let booking: record its landlord payout state accurately; create a caution-fee escrow only for an actually collected non-zero caution fee. Never manufacture an escrow from a missing field.
4. Normalize legacy `ESCROW` caution-fee states to `IN_ESCROW`. Migrate legacy booking `ESCROW`/`IN_ESCROW` rows to `PAID` once a separate escrow record is present; quarantine and investigate records where the allocation cannot be proven.
5. Deploy serializers that expose the allocation and canonical enums before or together with the Flutter release.
6. Switch scheduled work to caution-fee release only. Verify that it credits tenants, not landlords.
7. Backfill existing listings to `FLEXIBLE`; snapshot the configured policy and version on all new bookings.
8. Update the API guide enum table and Short Let payment section; remove wording that says the whole short-let payment enters escrow.

Minimum automated coverage:

- Card verify and vault pay each create exactly one landlord credit, one platform allocation, and one caution-fee escrow where applicable.
- Retried verify, duplicate webhook, and duplicated idempotency key do not duplicate any allocation.
- A zero-caution booking creates no escrow and still credits the landlord immediately.
- Checkout refunds only the caution fee to the tenant.
- Dispute blocks only caution-fee automatic release.
- Failed payment keeps the booking `APPROVED` and retryable until expiry.
- Each cancellation policy produces the server-calculated accommodation, platform-fee and caution-fee refund allocations at its exact cutoff.
- A paid tenant cancellation and a landlord cancellation each produce exactly one audited refund/recovery operation; the latter returns the full tenant charge.
- New API responses never emit booking `ESCROW` or `IN_ESCROW`; new caution-fee escrow responses never emit `ESCROW`.

---

## 6. Flutter compatibility during rollout

Flutter already accepts both `ESCROW` and `IN_ESCROW` while old records are being drained. Keep that tolerance for reads until the migration has been verified, but treat it as temporary compatibility—not a second vocabulary.

Flutter must use `booking.status` to decide booking actions and use `caution_fee_escrow_status` only to describe the refundable deposit. In particular, `PAID` unlocks paid-stay UI (check-in information, conversation and support/dispute routes); `IN_ESCROW` describes only where the caution fee is held.

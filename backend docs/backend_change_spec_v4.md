# Landa OS Backend Change Specification — v4

> **Audience:** Backend developer implementing on the Django API (`landa_os`, `users` app).
>
> **Companion document:** `flutter_api_guide (12).md` in this folder describes the API as it exists today. This document describes only what **changes**. When this ships, fold it into the guide and bump it to `(13)`.
>
> **Base URL (staging):** `https://landa-os-staging.onrender.com/api/users`
>
> **Status:** One change. The Flutter app already ships the feature against a device-local store — see [§7 Fallback Behaviour](#7-fallback-behaviour-what-the-app-does-today). Nothing here is blocking a release; it is what the feature needs to work on more than one phone.

---

## 1. What Changes, And Why

One addition: **vault allocations** — a tenant's record of how much of one vault balance is meant for which tenancy.

### The problem

A tenant renting two units saves for both out of a single vault balance. The backend has one balance and no notion of what any part of it is for, so the app had nothing to measure a savings goal against except the whole balance. Every rent card therefore reported the same figure: ₦10,000 saved towards Unit B1 *and* ₦10,000 saved towards Unit C4, from one ₦10,000. The same money, counted twice, telling a tenant they were halfway to two bills they could only pay one of.

That is fixed in the app, but only on the device it was fixed on.

### What this is not

**This is not a hold, an escrow, or a sub-account.** There is still one vault with one balance. An allocation is a statement of intent — "I am saving this much towards that unit" — and money covered by one is spendable on anything, exactly as it is today. Nothing in this spec should reduce `available_balance`, block a withdrawal, or refuse a payment.

Getting this wrong in the direction of "helpfully" reserving the money would be worse than not shipping it: a tenant who cannot withdraw their own balance because they once set a savings goal has lost access to their money over a note-to-self.

### Why it needs a backend

The app stores allocations in device storage keyed to the user id. That is honest about what they are, and it works — but it does not survive a reinstall, does not reach a second device, and cannot be read by anything else (reminder emails, for instance, cannot say "you are ₦40,000 short on Unit B1"). Those are the reasons to move it, and the only ones.

---

## 2. The Model

One row per (user, agreement). Not per unit: a unit's agreement is what rent is owed against, and it is what the payment endpoints are already keyed on.

| Field | Type | Notes |
| :--- | :--- | :--- |
| `user` | FK | Owner of the vault. |
| `agreement` | FK → TenancyAgreement | Must belong to this user as tenant. |
| `amount` | Decimal | What the tenant says they are putting towards it. `>= 0`. |
| `updated_at` | DateTime | |

Unique together on (`user`, `agreement`).

**Landlords do not get these.** A landlord's vault fills from escrow and is not being saved towards anything. Return `403` if an `OWNER` calls these endpoints, in line with the existing role gating on `POST /vault/topups/`.

---

## 3. Endpoints

### 3.1 `GET /vault/allocations/`

Returns every allocation the tenant has, plus the arithmetic they are measured against — so that every client agrees on the numbers rather than each deriving its own.

- **Authentication:** Required
- **Roles:** `TENANT`
- **Path:** `/api/users/vault/allocations/`

##### Response `200 OK`

```json
{
  "available_balance": "30000.00",
  "total_allocated": "30000.00",
  "unallocated_balance": "0.00",
  "exceeds_balance": false,
  "results": [
    {
      "agreement": "69be1df4-cbd1-47cf-b55a-0e2864ef4670",
      "unit_number": "B1",
      "property_name": "Sunset House",
      "amount": "10000.00",
      "effective_amount": "10000.00",
      "next_amount_due": "26250.00",
      "updated_at": "2026-08-31T09:00:00Z"
    },
    {
      "agreement": "8c1f0a52-4d2b-4e77-9a10-6b3f2c5d1e88",
      "unit_number": "C4",
      "property_name": "Sunset House",
      "amount": "20000.00",
      "effective_amount": "20000.00",
      "next_amount_due": "52500.00",
      "updated_at": "2026-08-31T09:02:00Z"
    }
  ]
}
```

A tenant with no allocations gets `200` with an empty `results` array and a real `available_balance` — not a `404`. The app renders the empty case as "nothing set aside yet", and a `404` renders as a fault.

#### `amount` versus `effective_amount` — read this one carefully

`amount` is what the tenant asked for. `effective_amount` is what that comes to given the balance that actually exists.

They differ the moment money set aside for rent gets spent on something else — a short-let booking, a withdrawal. The plans then promise more than the vault holds. **This is a normal state, not an error.** Do not reject it, do not auto-correct the stored amounts, and do not zero anything.

When `total_allocated > available_balance`, scale every `effective_amount` down by the same proportion:

```text
effective_amount = floor(amount × available_balance ÷ total_allocated)
```

Scaling evenly rather than draining one goal to keep another whole avoids an arbitrary decision about whose savings disappeared. Set `exceeds_balance: true` so the client can explain why the figures moved.

When `total_allocated <= available_balance`, `effective_amount == amount` and `exceeds_balance` is `false`.

`next_amount_due` is a convenience copy of the agreement's `rent_schedule.next_amount_due`, so a client can render "₦10,000 of ₦26,250" without a second call. Omit it (or send `null`) when the agreement has no schedule.

### 3.2 `PUT /vault/allocations/{agreement_id}/`

Sets what is being put towards one tenancy. Idempotent: the same body twice leaves the same state.

- **Authentication:** Required
- **Roles:** `TENANT`
- **Content-Type:** `application/json`

##### Request Body

```json
{
  "amount": "10000.00"
}
```

##### Response `200 OK`

The single allocation object, in the same shape as a `results` row above.

`PUT` rather than `POST` deliberately: the client is declaring the total, not adding to it. The app currently accumulates locally — top up ₦5,000 twice towards the same unit and it holds ₦10,000 — and will send the resulting total. A `POST`-and-add contract would double the figure on any retry, which is exactly the class of bug the `Idempotency-Key` headers elsewhere in this API exist to prevent.

##### Validation

- `amount` must be a decimal `>= 0`. Reject negatives with `400`.
- `amount` **may exceed** `available_balance`. Do not reject that — see §3.1.
- The agreement must exist and have this user as its tenant. Otherwise `404`, not `403`: a tenant should not be able to probe which agreement ids exist.
- The agreement does **not** need to be executed. A tenant saving ahead of a term that starts next year is the main use for this.
- `amount: "0.00"` is equivalent to `DELETE`.

### 3.3 `DELETE /vault/allocations/{agreement_id}/`

Removes the allocation. Returns `204 No Content`, and `204` again if there was nothing there — a client clearing a goal twice has got what it wanted either way.

---

## 4. Rules The Backend Should Own

These are the behaviours that need to hold regardless of which client is talking.

### 4.1 An allocation never restricts the money

Explicitly, this must all remain true with allocations set:

| Action | Behaviour |
| :--- | :--- |
| `GET /vault/` | `available_balance` unchanged. Allocations are not deducted. |
| `POST /vault/withdrawals/` | Succeeds up to the full available balance. No allocation check. |
| `POST /payments/` with `source: VAULT` | Succeeds up to the full available balance, for any agreement, regardless of what is allocated to it. |
| `POST /tenant/short-let-bookings/{id}/pay/` with `source: VAULT` | Same. |

If a tenant has ₦30,000 with ₦30,000 allocated to rent and pays ₦30,000 for a short stay, that goes through. The allocations then read as over-committed on the next `GET`, which is the honest outcome.

### 4.2 Paying rent clears that tenancy's allocation

When a vault-funded payment for an agreement reaches `ESCROW`, delete that agreement's allocation in the same transaction.

The bill it was saved towards is settled, so leaving it would show a tenant progress towards rent they have already paid. This is the one place the backend should mutate an allocation on the tenant's behalf, and it should be silent — no notification.

Do **not** clear it on a card-funded payment for the same agreement. Arguable either way, but the money set aside is still sitting in the vault afterwards, so the goal is still true. (If you disagree, say so and we will settle it — the app follows whatever this document ends up saying.)

### 4.3 Ending a tenancy ends its allocation

When an agreement moves to `EXPIRED` or `VOIDED`, delete any allocation against it. There is nothing left to save for.

### 4.4 Nothing is exposed to the landlord

Allocations are the tenant's private planning. They must not appear on any landlord-facing payload — not on `GET /agreements/`, not on `GET /payments/`, nowhere. A landlord learning that a tenant is ₦40,000 short with three weeks to go is not information this product should be handing over.

---

## 5. Error Shapes

Consistent with the rest of the API.

```json
{
  "code": "VALIDATION_ERROR",
  "detail": "Allocation amount cannot be negative.",
  "field": "amount"
}
```

```json
{
  "detail": "No TenancyAgreement matches the given query."
}
```

```json
{
  "detail": "Only tenants can set vault allocations."
}
```

---

## 6. The Richer Version, If You Want It Later

There is a more rigorous design than §3, and it is worth naming so the choice is deliberate rather than accidental.

Instead of storing an intent, **tag the money**: add an optional `for_agreement` to `POST /vault/topups/`, record it on the resulting ledger credit, and derive each allocation from the ledger — credits tagged for an agreement, minus rent paid on it. Allocations then become auditable, reconcilable against `GET /vault/transactions/`, and impossible to drift from what actually happened.

**Do not build that now.** It is more work, it needs a rule for how untagged spending draws down tagged credits, and the app does not need it. §3 is what the feature requires; §6 is where to go if allocations ever need to be defensible rather than merely useful.

---

## 7. Fallback Behaviour: What The App Does Today

The feature is already live in the Flutter app, storing allocations in device storage keyed to the signed-in user id. Behaviour with no backend:

- Adding money from a rent card records that amount against that agreement.
- Each rent card's savings progress measures against its own allocation, scaled by the rules in §3.1 — the client already implements that arithmetic, so the two will agree.
- The vault card shows the split, labelled as a plan rather than as separate accounts.
- Paying rent from the vault clears that agreement's allocation.
- Signing out wipes the store, so the next person on the phone does not inherit it.

When these endpoints appear, the app will read from them and stop writing to the device. No migration of existing local allocations is planned: they are a few days of savings intent, not records, and a tenant re-setting a goal is a smaller cost than a migration path nobody can test.

**Nothing in the app breaks if this is never built.** It simply stays per-device.

---

## 8. Acceptance Checklist

- [ ] `GET /vault/allocations/` returns `200` with an empty `results` for a tenant who has none.
- [ ] `PUT` then `GET` round-trips the amount unchanged.
- [ ] `PUT` twice with the same body leaves one row with that amount, not two rows or a doubled one.
- [ ] `PUT` with an amount above the balance is accepted, and the next `GET` reports `exceeds_balance: true` with proportionally scaled `effective_amount`s.
- [ ] With allocations set, a withdrawal for the full available balance still succeeds.
- [ ] With allocations set, a vault rent payment for an agreement with nothing allocated to it still succeeds.
- [ ] A vault rent payment reaching `ESCROW` removes that agreement's allocation.
- [ ] A landlord calling any of these gets `403`.
- [ ] A tenant `PUT`ting against another tenant's agreement id gets `404`.
- [ ] No allocation field appears on any landlord-facing payload.

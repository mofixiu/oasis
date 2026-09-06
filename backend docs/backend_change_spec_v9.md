# Landa OS Backend Change Specification — v9

> **Audience:** Backend developer implementing on the Django API (`landa_os`, `users` app).
>
> **Companion documents:** `flutter_api_guide (17).md` (received 2026-09-03) is the current source of truth. `backend_change_spec_v7.md` and `v8.md` are the requests this document is following up on — v7 shipped in full; v8 shipped with one deliberate deviation, noted in §1 below. Both are otherwise superseded by what is written here.
>
> **Status:** The app is integrated against everything in the v17 guide as received. This document is (1) a record of one place where what shipped differs from what v8 asked for, in case that was not a deliberate call, and (2) three response shapes the app had to parse defensively because they were not documented.

---

## 1. Payout timing shipped differently from v8 — please confirm this was deliberate

v8 §1 asked for the accommodation payout to be **released immediately** on successful payment, with only the caution fee held in escrow until checkout. What actually shipped, per the v17 guide's §9, is different: the **whole host payout is held until check-in** (`host_payout_status: HELD`, releasing by default at 12:00 PM Africa/Lagos on the check-in date), and a tenant dispute can push it to `BLOCKED` before that.

The app is built against what shipped — a booking's journey (`status`) and its money (`host_payout_status`) are tracked as two separate fields, shown as two separate lines in the UI, which was the actual point of v8 (never let "the booking is paid" imply "the host has been paid"). That part is intact. Only the *timing* is different: v8's landlord got their payout the moment a guest paid; the shipped version has them waiting until the guest is due to arrive.

This is very plausibly the better design — it gives Landa a window to act if a payment turns out to be fraudulent, and it means a tenant who cancels the day before check-in is not clawing money back out of a landlord's account. But it is a real behaviour change from what was asked for, so: **please confirm the hold-until-check-in model is the intended final design**, not an intermediate step. If it is intentional, no action needed — the app already matches it. If v8's immediate-release was actually the goal, say so and the app's copy (`host_payout_status_description` rendering, the Stays tab subtitle) will need to change to match.

---

## 2. Three response shapes the app had to guess at

None of these were shown with an example JSON body in the guide. The app parses them defensively — reading the same field names the rest of the short-let payloads use — but a confirmed shape (or a corrected one) would remove the guessing.

### 2.1 `GET /tenant/short-let-bookings/{id}/cancel-preview/`

The app assumes this returns the same refund-breakdown fields the guide's §9 "Important Response Fields" example shows on a booking/payment object:

```json
{
  "accommodation_refund_amount": "80000.00",
  "platform_fee_refund_amount": "0.00",
  "caution_fee_refund_amount": "25000.00",
  "total_refund_amount": "105000.00",
  "cancellation_policy": "MODERATE"
}
```

If the real response is shaped differently, the app will silently show no refund quote (it degrades to the generic "Landa will confirm the refund before completing cancellation" wording) rather than breaking — but the number a tenant actually wants to see before they tap Cancel is worth getting right. Please confirm or correct this shape.

### 2.2 `POST /landlord/short-let-bookings/{id}/caution-claims/` and `POST /tenant/short-let-caution-claims/{claim_id}/respond/`

Both requests are documented; neither response is. The app does not try to parse a claim object out of either — it treats both as fire-and-forget and refreshes the booking list afterward. Two consequences worth knowing about:

- **There is no `GET` to list a tenant's open claims.** The only way the app currently learns a claim exists at all is the `SHORT_LET_CAUTION_FEE_CLAIM` notification, whose `data` payload the app reads for `claim_id`, `claimed_amount` and `reason`. If a tenant dismisses or never sees that notification, they have no other way to find and respond to the claim inside the app. A `GET /tenant/short-let-caution-claims/?status=PENDING` (or similar) would close this gap.
- **`evidence` is sent as an empty list.** The request body accepts `"evidence": ["https://…"]`, but there is no documented upload endpoint to get a photo of, say, a broken lamp into a URL the app can put in that array. The claim form only collects a written reason for now. If there is meant to be an upload step, point to the endpoint and this is a small addition.

---

## 3. Search and price filters — received and implemented, no open questions

`min_price`/`max_price` now go out on both `GET /tenant/marketplace/` and `GET /tenant/short-lets/`, replacing `min_rent`/`max_rent` on the marketplace side (the backend still accepts the old names; the app just has no reason to send both). Both price fields are digit-only inputs client-side, and a max below a min is refused before the request is ever sent — covered by `test/marketplace_filter_sheet_test.dart` and `test/shortlet_flow_test.dart`.

---

## 4. Still open from v8 §4.3 — the unsupported-status audit

v8 §4.3 asked for confirmation that `PAYMENT_FAILED`, `FAILED`, `AWAITING_PAYMENT`, `PENDING_PAYMENT`, `PROCESSING` and `REFUNDED` do not appear anywhere in `ShortLetBooking.status` — historical rows included. The v17 guide's canonical list (§9: `REQUESTED`, `APPROVED`, `PAID`, `CHECKED_IN`, `CHECKED_OUT`, `COMPLETED`, `DISPUTED`, `REJECTED`, `CANCELLED`, `EXPIRED`) doesn't mention any of them, which is reassuring but isn't the same as an audit result. The app now logs and visibly explains any status it cannot map (`ShortLetBookingStatus.unknown`, rendered as "Status unclear" with the raw word quoted) rather than failing silently — so if one of those six is still lurking in old data, it will surface itself the next time someone hits it, rather than needing this audit to catch it in advance. Worth doing anyway if it hasn't been.

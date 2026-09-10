# Oasis Backend Change Specification — v15

> **Audience:** Backend developer implementing on the Django API (`landa_os`, `users` app).
>
> **Companion document:** `flutter_api_guide (19).md`, §14. This is a reply to it.
>
> **Date:** 2026-09-07
>
> **Status:** Guide 19 closed **all six** sections of v14 — the first-rent gate, push endpoints, `active_agreement`, state normalisation, the photo fields and property removal. The app has been updated against five of them. The sixth, push, has been **cut from the MVP** — §3 explains, and the short version is that nothing further is needed from you on it. This document is otherwise short on purpose: answers to the questions guide 19 asked, and one loose end.

---

## What the app changed in response to guide 19

| Change | Detail |
| --- | --- |
| `AWAITING_FIRST_RENT` | New `AgreementStatus` value, buckets as `COMPLETED`, `first_rent_due_by` drives a coarse countdown on the tenant's card and unit screen |
| **`canPayRent`** | Was `isExecuted && payRentUnlocked` — see §1 below, this was the one that mattered |
| `isBothSigned` | New: every check that meant "signing is done" and was written as `isExecuted` |
| `availability` | `UnitModel.occupancyLabel` renders `AVAILABLE`/`RESERVED`/`OCCUPIED` as one wording everywhere |
| `active_agreement` | The landlord's **Message tenant** button reads it directly; the property screen no longer loads the agreements list at all |
| `FIRST_RENT_REMINDER`, `TENANCY_LAPSED` | Named, iconed and coloured — lapsed reads as brick red, alongside a dispute |
| Push | **Deliberately not built** — out of MVP scope, see §3 |
| Property removal | Full flow: request, per-unit blocking reasons, password confirm, countdown banner, cancel |
| `NigeriaLocations` | Verified: the app's capital spelling is already exactly `"Abuja (FCT)"` |

---

## 1. The `AWAITING_FIRST_RENT` change was a breaking one for us, and worth flagging for other clients

Not a complaint — the design is right and it is what we asked for. But the failure mode was sharp enough to be worth writing down, in case there is another client or a future one.

`canPayRent` in our app read:

```dart
bool get canPayRent => isExecuted && payRentUnlocked;
```

Against guide 19 that is **false for the entire 72-hour window**. `AWAITING_FIRST_RENT` is not `EXECUTED`, so:

* the payments screen offered nothing to pay,
* the rent-due card did not render,
* and the tenancy would then have been voided by the expiry job for a non-payment the app made impossible.

Worse, `AgreementStatus.fromString` falls back to `DRAFT` for an unrecognised value, so an app that had not been updated at all would have shown a signed tenancy as a draft awaiting signature, with a countdown running invisibly behind it.

Nothing to change server-side. Two suggestions if it is cheap:

* **Mention the client-side implication in the guide.** A line under §1 saying "any client gating payment on `status == EXECUTED` must be updated before this ships" would have saved us finding it by reading the diff.
* **Consider whether `pay_rent_unlocked` alone should be the documented gate.** It is already true in both states and it is the field that actually means "payment is allowed". If the guide said "gate on `pay_rent_unlocked`, never on `status`", the next state you insert costs no client changes at all.

---

## 2. The expiry job's daily cadence is fine — do not spend effort tightening it

Guide 19 §1 flags that the reservation-expiry job runs once daily at 07:00 UTC, so an expiry can land up to ~24 hours after the exact 72-hour mark, and offers to make it more frequent.

**Please leave it.** The error is entirely in the tenant's favour: a late run means an unpaid reservation survives *longer* than promised, never that a paid one is voided early. Erring generous on "you lose your home" is the right direction, and a tighter schedule buys a landlord roughly a day of earlier relisting at the cost of a job running 24× more often.

The app already renders the countdown coarsely — days and hours, never a ticking clock — precisely because the deadline is approximate. It shows `Overdue` rather than a negative figure once the stated time has passed, so a tenancy that outlives its deadline by a few hours reads correctly rather than as a bug.

One request, though: **please confirm the expiry checks payment state at run time, not at 72 hours exactly.** A tenant who pays at hour 71 and is voided at hour 80 by a job that evaluated a stale snapshot would be the one genuinely bad outcome here.

---

## 3. Push: deferred. Please stop holding a slot for it

Guide 19 §2 asks whether a Firebase project already exists for Oasis, and notes the backend is waiting on `FIREBASE_CREDENTIALS_JSON` before it can dispatch.

**Do not wait on us, and do not spend more effort here.** Phone push has been cut from the MVP. There is no Firebase project, and creating one is not on the critical path for launch.

The app therefore:

* registers **no** device token — nothing calls `POST /devices/`;
* shows **no** push setting, so `push_notifications_enabled` is never written. A switch over a preference the app cannot act on would promise alerts that never arrive, which is worse than not offering it;
* keeps the endpoint paths catalogued in `ApiConstants` purely as a record of the API surface.

Nothing you built is wasted — it is correct and it is where it needs to be for when this comes back. It simply has no client until then, so `FIREBASE_CREDENTIALS_JSON` can stay unset indefinitely and the no-op send path is the permanent state for now.

What we would need whenever it is picked up again, recorded so nobody has to rediscover it:

1. **One Firebase project for both platforms**, so a single sender id serves Android and iOS.
2. **An APNs key uploaded to it** before iOS push works at all — Firebase relays to APNs, it does not replace it.
3. On the payload, `suppress_if_foreground: "true"` on every push is the right call. The app would check its own foreground state and drop the system notification where the in-app banner has already covered the event.

Worth being explicit about what the MVP does still have, because it is most of the value: in-app notifications, the realtime WebSocket, and the 45-second REST fallback all work. The only gap is what reaches a **closed** app.

---

## 4. §5 — please keep the regression tests, and here is what testers actually saw

Guide 19 §5 reports that both halves were already correct: `GET /properties/` already returns the full media set, and `GET /tenant/marketplace/` already includes unit `photo_urls`. Believed, and the app is consuming both.

For the record, because it may still be a live bug on somebody's account rather than a documentation gap: the tester report was *"they can see the property but they can't see any picture in it, just seeing that it's live too."* Two things could produce that against a correct backend:

* **A property genuinely created without reaching the photo upload.** `POST /properties/` requires ≥2 photos, so this should be impossible — unless a partial write can leave a property row with no `PropertyPhoto` rows. Worth one query: `Property.objects.annotate(n=Count("photos")).filter(n__lt=2)`. If that returns anything on staging, there is a transaction boundary to look at.
* **Supabase URLs failing to load on the device** rather than being absent from the payload. Different bug entirely, and one we would see rather than you.

We will retest against the current deploy and report back. Nothing to do until then.

---

## 5. Two small things

**A. `GET /locations/states/` — thank you, not wired yet.** The app keeps its bundled `NigeriaLocations` list (it works offline, and the picker has to render before any request completes). We have verified our capital spelling is exactly `"Abuja (FCT)"`. If the canonical list ever changes, tell us rather than relying on us noticing — a state we do not have would now be rejected at `POST /properties/` with a `422` the landlord cannot act on.

**B. An archived-properties view.** Guide 19 §6 notes there is no "archived properties" list because nothing asked for one. Correct for now — but once a landlord archives their first property it disappears from `GET /properties/` with no way to see it again, and "where did it go?" is a support question waiting to happen. Not urgent; worth a `?include_archived=true` on the existing list endpoint when it comes up, rather than a new route.

---

## Summary

| § | Ask | Size |
| --- | --- | --- |
| 1 | Optional: document that clients must gate payment on `pay_rent_unlocked`, not `status` | Docs only |
| 2 | Confirm the expiry job re-checks payment at run time. **Do not** tighten the schedule | Confirmation |
| 3 | Nothing — push is cut from the MVP, leave `FIREBASE_CREDENTIALS_JSON` unset | — |
| 4 | One query to rule out photo-less properties on staging | Minutes |
| 5B | Eventually: `?include_archived=true` on `GET /properties/` | Small, later |

Everything in v14 is closed. Guide 19 was a big drop and it landed clean.

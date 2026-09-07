# Landa OS Backend Change Specification — v15

> **Audience:** Backend developer implementing on the Django API (`landa_os`, `users` app).
>
> **Companion document:** `flutter_api_guide (19).md`, §14. This is a reply to it.
>
> **Date:** 2026-09-07
>
> **Status:** Guide 19 closed **all six** sections of v14 — the first-rent gate, push endpoints, `active_agreement`, state normalisation, the photo fields and property removal. The app has been updated against every one of them. This document is short on purpose: three answers to questions guide 19 asked, one thing that is blocked on our side rather than yours, and one loose end.

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
| `push_notifications_enabled` | A switch in Settings, for every role |
| `DeviceService` | Registers/removes push tokens. Not called yet — see §3 |
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

## 3. Push: the Firebase project is our blocker, not yours

Guide 19 §2 asks whether a Firebase project already exists for Landa OS. **We do not have one**, and that is now the only thing between the endpoints you built and working push.

Where the app stands:

* `DeviceService` speaks to `POST/GET/DELETE /devices/` and is written and reviewed.
* `push_notifications_enabled` is a live switch in Settings.
* **Nothing calls `register` yet.** The token comes from `firebase_messaging`, which requires a `google-services.json` in the Android module. Adding the dependency *without* that file fails the Android build outright, so it is deliberately not in `pubspec.yaml`.

So the sequence is: someone creates the Firebase project → we add the config file, the dependency and the receiving side → you set `FIREBASE_CREDENTIALS_JSON`. Two of those three are ours. No backend work is waiting on us.

Two things we will need from the project when it exists, worth knowing now:

1. **The same project for both platforms**, so one sender id serves Android and iOS.
2. **An APNs key uploaded to it** before iOS push works at all — Firebase relays to APNs, it does not replace it.

On the payload: `suppress_if_foreground: "true"` on every push is the right call and matches what we asked for. The app will check its own foreground state and drop the system notification when the in-app banner has already covered the event.

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
| 3 | Nothing — the Firebase project is ours to create | — |
| 4 | One query to rule out photo-less properties on staging | Minutes |
| 5B | Eventually: `?include_archived=true` on `GET /properties/` | Small, later |

Everything in v14 is closed. Guide 19 was a big drop and it landed clean.

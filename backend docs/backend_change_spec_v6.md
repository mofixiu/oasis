# Oasis Backend Change Specification — v6

> **Audience:** Backend developer implementing on the Django API (`landa_os`, `users` app).
>
> **Companion document:** `flutter_api_guide (15).md` in this folder describes the API as it exists today. This document describes only what **changes**. When this ships, fold it into the guide and bump it to `(16)`.
>
> **Base URL (staging):** `https://landa-os-staging.onrender.com/api/users`
>
> **Status:** One blocking gap and one enhancement. §1 blocks a landlord with an existing building from onboarding truthfully — today the API offers them no way to record a tenancy that started before they found Oasis. §2 makes Discover answer the location question Stays already answers. Both have Flutter shipped against them with a degraded fallback; see §1.6 and §2.4 for exactly what the app does until each lands.

---

## 1. Blocking: A Landlord Cannot Bring Their Existing Tenants With Them

### 1.1 The problem

Every tenancy path in the API assumes the tenancy **begins on Oasis**:

| Path | What it assumes |
| :--- | :--- |
| `POST /tenant/applications/` → `POST /landlord/applications/{id}/approve/` | The tenant found the unit on the marketplace and applied for it. |
| `POST /agreements/` | The landlord is inviting somebody to a unit, starting now. |

A landlord signing up with a twelve-flat building has neither. Their tenants moved in two years ago, paid a year up front in cash, and are seven months into a term. There is no endpoint that describes that situation, and the two workarounds both produce false records:

1. **Invite each tenant with `POST /agreements/`.** Two things break.
   - The tenant must already hold a `TENANT` account. §2 of the guide is explicit: *"The matched account must have `role: "TENANT"`. If no tenant account matches, the backend returns `400 Bad Request`."* A landlord's existing tenants have never heard of Oasis, so **every row fails**. This alone makes the flow impossible, not merely awkward.
   - Even where the tenant does have an account, the agreement starts today. The real tenancy started 2025-03-01 and renews 2026-02-28; the recorded one starts 2026-09-02 and renews 2027-09-01. Every renewal reminder, every rent schedule and every expiry is then wrong by seven months, permanently.
2. **Leave them out and mark the flats vacant.** The landlord's own dashboard then disagrees with their building, and the units appear on the tenant marketplace as available to apply for — homes that somebody is living in.

There is a third failure lying under both, and it is the one that will actually cost trust. If a backdated agreement is created and the rent schedule is generated from `start_date` as it is today, an existing tenant's **first experience of Oasis is being told they owe rent they already paid**, possibly several instalments of it. The backend must be told what has already been settled.

### 1.2 What to add

`POST /api/users/landlord/tenancies/import/`

- **Authentication:** Required
- **Roles:** `OWNER`, verified
- **Purpose:** Record tenancies that predate Oasis, in one batch, inviting tenants who have no account yet.

#### Request body

```json
{
  "tenancies": [
    {
      "unit": "c82c03a7-1a89-41ce-aebe-bce7904f43cf",
      "tenant": "tenant@example.com",
      "rent_amount": "450000.00",
      "start_date": "2025-03-01",
      "end_date": "2026-02-28",
      "rent_plan": "ANNUAL",
      "rules": "No noise after 10 PM. Rent due annually.",
      "is_existing_tenancy": true,
      "rent_paid_until": "2026-02-28"
    }
  ]
}
```

| Field | Type | Required | Notes |
| :--- | :--- | :--- | :--- |
| `unit` | UUID | Yes | Must belong to the authenticated landlord. |
| `tenant` | string | Yes | Email, phone or UUID — the same Tenant Lookup Inputs as `POST /agreements/`, **plus** the new behaviour in §1.4 when nothing matches. |
| `rent_amount` | decimal string | Yes | The annual figure, whatever `rent_plan` says. Same as `POST /agreements/`. |
| `start_date` | ISO date | Yes | **May be in the past.** That is the point of this endpoint. |
| `end_date` | ISO date | Yes | After `start_date`. May also be in the past — see §1.5 on expired terms. |
| `rent_plan` | enum | No | `ANNUAL` \| `SIX_MONTHLY` \| `QUARTERLY` \| `MONTHLY` \| `WEEKLY`. Defaults to `ANNUAL`. |
| `rules` | string | No | As on `POST /agreements/`. |
| `is_existing_tenancy` | boolean | Yes | Always `true` from this route. Marks the agreement as a record of something that happened off-platform, not a tenancy Oasis brokered. |
| `rent_paid_until` | ISO date | No | Rent is settled **up to and including** this date. Absent means nothing has been paid. See §1.5. |

Cap the batch at **50** rows. A landlord entering more than that in one sheet is a data import, not a form.

#### Response `207 Multi-Status` (or `200`)

One result per requested row, **in request order**. The app matches results to rows positionally and shows each verdict against the flat it belongs to — a result it cannot tie back to a row cannot be displayed at all.

```json
{
  "results": [
    {
      "unit": "c82c03a7-1a89-41ce-aebe-bce7904f43cf",
      "status": "CREATED",
      "tenant_status": "EXISTING",
      "agreement": { "...": "the full agreement object, as POST /agreements/ returns" }
    },
    {
      "unit": "8f1d2b44-6c19-4a7e-9b30-2d5e1f0a7c88",
      "status": "CREATED",
      "tenant_status": "INVITED",
      "agreement": { "...": "..." }
    },
    {
      "unit": "1a2b3c44-5d6e-4f70-8901-234567890abc",
      "status": "FAILED",
      "error": "That unit is already assigned to another tenant."
    }
  ]
}
```

| Field | Values | Notes |
| :--- | :--- | :--- |
| `status` | `CREATED` \| `FAILED` | |
| `tenant_status` | `EXISTING` \| `INVITED` | Whether the tenant already had an Oasis account. Absent on a failure. |
| `agreement` | object | Present on `CREATED`. The same serializer `POST /agreements/` returns, so the app needs no second shape. |
| `error` | string | Present on `FAILED`. **User-presentable** — the app shows it verbatim against the flat. "That unit is already assigned to another tenant", not "IntegrityError on units_unit.tenant_id". |

**Rows are independent.** One bad row must not roll back the others. A landlord entering seven tenancies will get one wrong — a mistyped email, a unit they forgot they had already assigned — and losing the other six to a single validation error means retyping the lot. Do not wrap the batch in one atomic transaction; wrap each row.

### 1.3 Why a batch route rather than a flag on `POST /agreements/`

The unit of work is a building, not a flat. But the deciding reason is §1.4: this route creates *user accounts* as a side effect, and that is not a behaviour to smuggle into an existing endpoint that landlords already call for ordinary invitations. Keeping it on its own route means the invite-a-stranger power is scoped to the one flow that needs it.

If you would rather extend `POST /agreements/` with `is_existing_tenancy` and `rent_paid_until` **as well**, that is welcome — the app sends both fields on the fallback path (§1.6) and they would make it materially less degraded. But the batch route is what closes the gap.

### 1.4 Inviting a tenant who has no account

This is the half that `POST /agreements/` cannot do.

When `tenant` matches no account:

1. Create a **claimable placeholder** user with that email or phone, `role: "TENANT"`, in a state that cannot sign in — no usable password, and `verification_status` untouched at its default.
2. Send them an invitation (email and/or SMS) with a link to register against that identity. The existing password-reset delivery is the closest thing already built; reuse it if it fits.
3. Create the agreement against the placeholder, `status: "PENDING"`.
4. Answer with `tenant_status: "INVITED"`.

When they register with that email or phone, they must land on the same account, so the agreement is waiting for them rather than a duplicate being created beside it. **The claim must be verified** — email confirmation or OTP — before the account is usable. A landlord must not be able to create a signed-in-able account for an address they do not control.

Rules that must hold:

- A placeholder account cannot log in, cannot be assigned a payout account, and cannot appear in any tenant-facing directory until it is claimed.
- Re-importing the same email must find the placeholder, not make a second one.
- If a landlord imports an email that belongs to an existing **`OWNER`** or **`ARTISAN`**, that row `FAILED`s with a clear message. Do not silently switch somebody's role.

### 1.5 Backdating, and what `rent_paid_until` must do

This is the part most likely to be implemented in a way that looks correct and is not.

**`start_date` in the past must be accepted from this route.** The current validation (`end_date > start_date`) is sufficient; do not add a "not in the past" rule for imports.

**The agreement is still signed.** Status `PENDING`, `awaiting_signature_from: "TENANT"`, exactly as an invitation. Oasis's entire premise is that a tenancy agreement is a document both parties actually signed — auto-executing an imported one because the landlord asserted it exists would forge the tenant's signature, on the one product that exists to stop that happening. The tenant signs a backdated document, which is normal and legally ordinary; the landlord signs after them as usual.

**`rent_paid_until` governs the rent schedule.** For an imported agreement:

- Every instalment falling due **on or before** `rent_paid_until` is treated as settled. It must not be billed, must not be counted in `is_overdue`, and must not trigger a rent reminder (v3 §5).
- `rent_schedule.next_due_date` is the first instalment falling **after** `rent_paid_until`.
- `rent_schedule.instalments_paid` counts the settled ones, so `instalments_paid: 1, instalments_total: 1` is the correct answer for a fully paid annual term.
- These instalments are **settled, not paid through Oasis**. No `Payment` record, no receipt, no escrow, no platform fee, and nothing that would make them appear in the landlord's vault or payout figures. Money that never moved through Oasis must never show up in Oasis's ledger. If a marker is useful, `"source": "OFF_PLATFORM"` on the schedule entry is the honest one.

Worked example — the common Nigerian case. Tenant moved in 2025-03-01, paid ₦450,000 for the year in cash:

```json
{
  "start_date": "2025-03-01",
  "end_date": "2026-02-28",
  "rent_paid_until": "2026-02-28",
  "rent_schedule": {
    "plan": "ANNUAL",
    "next_due_date": "2026-03-01",
    "next_amount_due": "472500.00",
    "days_until_due": 180,
    "is_overdue": false,
    "instalments_paid": 1,
    "instalments_total": 1
  }
}
```

The tenant signs, sees their real renewal date, and is asked for nothing until it arrives. That is the whole feature.

Where `rent_paid_until` is **absent**, generate the schedule normally from `start_date` — a genuinely-in-arrears tenancy is a real situation and the landlord said so by leaving it off.

Where `end_date` is already in the past (an expired term the landlord is recording for history), create the agreement as `EXPIRED` with no schedule rather than billing a term that is over.

### 1.6 Fallback behaviour: what the app does today

Shipped and live. `AgreementService.importTenancies` posts the batch to `/landlord/tenancies/import/`, and on `404`/`403`/`405` falls back to **one `POST /agreements/` per row**, catching each rejection so the other rows still land. A `400` from the import route is *not* retried row by row — the route existed and rejected the payload, and looping would report the wrong reason once per flat.

On the fallback path the app already sends `is_existing_tenancy` and `rent_paid_until` in each `POST /agreements/` body. DRF drops undeclared keys, so today they are inert; declaring them on the agreement serializer would upgrade the fallback for free.

What the landlord sees until §1 ships:

- Tenants who **already have** an Oasis account: recorded correctly, with backdated dates — but billed from `start_date`, because nothing reads `rent_paid_until` yet. This is the arrears problem in §1.1, live.
- Tenants who **do not**: the row fails with the backend's own `400` on `tenant`, shown against that flat. The landlord is told exactly which tenants could not be added and why. That is the best the app can do, and it is not good enough — it is most of the building.

### 1.7 Acceptance checklist

- [ ] `POST /landlord/tenancies/import/` exists, `OWNER`-only, verified-only, capped at 50 rows.
- [ ] Results come back one per row, in request order, with `status`, `tenant_status`, and a user-presentable `error` on failure.
- [ ] One failing row does not roll back the others.
- [ ] `start_date` in the past is accepted.
- [ ] An unknown `tenant` creates a claimable placeholder and sends an invitation; `tenant_status: "INVITED"`.
- [ ] Registering with an invited email lands on the placeholder account, with the agreement waiting.
- [ ] A placeholder cannot sign in until the identity is verified.
- [ ] An email belonging to an `OWNER` or `ARTISAN` fails the row rather than switching roles.
- [ ] Imported agreements are `PENDING` and require the tenant's signature.
- [ ] Instalments on or before `rent_paid_until` are settled: not billed, not overdue, no reminders.
- [ ] Settled instalments create no `Payment`, no receipt, no escrow, no platform fee, and touch no vault or payout figure.
- [ ] `rent_schedule.next_due_date` is the first instalment after `rent_paid_until`.
- [ ] An agreement whose `end_date` has passed is created `EXPIRED` with no schedule.
- [ ] Importing marks the unit occupied, so it leaves the tenant marketplace.

---

## 2. Enhancement: Discover Cannot Answer "Near Me"

### 2.1 The problem

§7C of the guide gives Stays a location search and gives the marketplace only a typed one:

| Endpoint | `location` | `latitude`/`longitude` | `radius_km` | `distance_km` in response |
| :--- | :--- | :--- | :--- | :--- |
| `GET /tenant/short-lets/` | Yes | Yes | Yes (10km default) | Yes |
| `GET /tenant/marketplace/` | Yes | **No** | **No** | **No** |

The asymmetry is backwards relative to how much each matters. Somebody booking a weekend can name the area they want. Somebody looking for a **home** cares about the commute, and "within 5km of where I am standing" is a question a place name cannot express — Lagos area names do not map cleanly onto distances, and a tenant searching "Yaba" misses the flat four streets away in Ebute-Metta.

Discover is now a bottom-nav tab rather than an icon in the app bar, so this is the screen a tenant opens to find somewhere to live.

### 2.2 What to add

Teach `GET /api/users/tenant/marketplace/` the three parameters Stays already takes, with identical semantics:

```text
GET /api/users/tenant/marketplace/?latitude=6.4450&longitude=3.4720
GET /api/users/tenant/marketplace/?latitude=6.4450&longitude=3.4720&radius_km=10
```

- Coordinates **replace** `location`. If both arrive, coordinates win — that is what the app sends when the tenant taps Near me, and it clears the search box to match.
- `radius_km` defaults to **10**, as on Stays. Do not hard-code a different default here.
- Existing filters still compose: `bedrooms`, `min_rent`, `max_rent` narrow the result within the radius. A tenant asking for "near me" has not withdrawn their budget.
- Results are ordered **nearest first** and each carries `distance_km`:

```json
{
  "id": "property-uuid",
  "name": "Sunset House",
  "distance_km": 2.41,
  "available_units": []
}
```

**Properties with no stored coordinates.** Landlords have been able to skip the map pin, so some rows have no `latitude`/`longitude`. Include them **after** the ranked results with `distance_km: null` rather than dropping them — a missing pin is a gap in the record, not a statement that the home is far away, and hiding a flat somebody could rent because of it is the worse failure. If you would rather exclude them, say so and the app will stop showing them under the "closest first" notice.

### 2.3 Same treatment for Fix, when artisans have coordinates

§7C already notes that artisan distance sorting is deferred until artisan profiles store map coordinates. Nothing here changes that. When it happens, the same three parameters and the same `distance_km` on `GET /tenant/fix/artisans/` would let the app reuse the control it now has on two screens.

### 2.4 Fallback behaviour: what the app does today

Shipped and live, and **this one is not blocked** — it is degraded in a way worth knowing about.

`MarketplaceService.getMarketplace` already sends `latitude`, `longitude` and `radius_km` in exactly the spelling above. DRF ignores them today. The marketplace payload does carry each property's `latitude`/`longitude`, so `MarketplaceController` measures the distance itself (haversine, `lib/core/utils/geo_distance.dart`) and sorts nearest first, showing "1.2 km away" on each card. A server-sent `distance_km` always wins where one arrives, so the two can never print different numbers for the same listing.

What the app cannot do without §2:

- **No radius filter.** Every listing in the country is returned and merely sorted, so a tenant in Lagos scrolls past Abuja rather than not being shown it.
- **No pagination sanity.** Sorting client-side means sorting only what was sent. Once the marketplace paginates, "closest first" silently becomes "closest first within page one", which is a wrong answer that looks like a right one.
- Properties with no pin sort last with no distance shown.

The day §2 ships, the client-side sort becomes a no-op — the results arrive ordered with `distance_km` already set — and no app release is required for it to start working.

### 2.5 Acceptance checklist

- [ ] `GET /tenant/marketplace/` accepts `latitude`, `longitude`, `radius_km`.
- [ ] Coordinates take precedence over `location` when both are sent.
- [ ] `radius_km` defaults to 10.
- [ ] `bedrooms` / `min_rent` / `max_rent` still apply within the radius.
- [ ] Results are ordered nearest first and carry `distance_km`.
- [ ] Properties without coordinates are returned last with `distance_km: null` (or their exclusion is documented).

---

## 3. Endpoint Summary

| Feature | Method | Path | Auth | Roles | Status |
| :--- | :--- | :--- | :--- | :--- | :--- |
| Import existing tenancies | `POST` | `/api/users/landlord/tenancies/import/` | Yes + verified | `OWNER` | **New** |
| Create agreement | `POST` | `/api/users/agreements/` | Yes + verified | `OWNER` | Optionally accepts `is_existing_tenancy`, `rent_paid_until` (§1.3) |
| Tenant marketplace | `GET` | `/api/users/tenant/marketplace/` | Yes + verified | `TENANT` | Adds `latitude`, `longitude`, `radius_km`, returns `distance_km` |

## 4. Test Coverage On The App Side

Already written and passing, so a staging deploy of either section can be checked against them:

- `test/tenancy_import_test.dart` — the backdated wire shape, `rent_paid_until` presence and absence, the `404` fallback to per-row creation, a `400` *not* being retried per row, partial-failure reporting, invited-tenant reporting, and positional matching of results to rows.
- `test/tenant_search_test.dart` — marketplace coordinates replacing `location`, distance ordering, unpinned properties sorting last rather than vanishing, and a server-sent `distance_km` overriding the client's own measurement.
- `test/add_property_flow_test.dart` — the move-in sheet offering only vacant units, refusing to send an incomplete tenancy, and stating what backdating does before anything is typed.

# Request: Applicant details on landlord application endpoints

**From:** Flutter team
**Re:** `GET /api/users/landlord/applications/`
**Priority:** Blocking — landlords currently cannot identify who is applying.

---

## Problem

The landlord applications inbox is live in the app, but the response from
`GET /api/users/landlord/applications/` does not appear to carry any
applicant identity. A landlord sees only the property, unit, rent, and status:

```text
Sunset House · Unit B22          PENDING
₦600000.00/yr
[ Reject ]  [ Approve ]
```

Approving an application creates a binding tenancy agreement and marks the
unit occupied. Asking a landlord to make that decision without showing them
who the applicant is makes the screen unusable for its actual purpose.

The app currently renders "Applicant details not provided by the server" in
that slot so the gap is visible rather than silent.

## What the app already tries to read

Flutter parses defensively and will pick up **any** of these shapes without
further changes, so you can use whichever fits your serializers best.

Flattened:

```json
{
  "id": "...",
  "unit": "...",
  "unit_number": "B22",
  "status": "PENDING",
  "tenant_name": "Ada Okafor",
  "tenant_email": "ada@example.com",
  "tenant_phone": "+2348012345678",
  "rent_amount": "600000.00",
  "created_at": "2026-08-17T09:00:00Z"
}
```

Nested (matches the existing unit-assignment serializer, which already
returns a nested tenant object):

```json
{
  "id": "...",
  "unit": { "id": "...", "unit_number": "B22", "rent_amount": "600000.00" },
  "status": "PENDING",
  "tenant": {
    "id": "f8c88b5d-3d87-4f86-b402-39d8e68bff88",
    "full_name": "Ada Okafor",
    "email": "ada@example.com",
    "phone_number": "+2348012345678"
  },
  "created_at": "2026-08-17T09:00:00Z"
}
```

The nested form is preferred for consistency: `GET /properties/{id}/units/`
already returns exactly this `tenant` object shape (guide §5.14).

### Fields requested

| Field | Type | Why it is needed |
| :--- | :--- | :--- |
| `tenant_email` **or** `tenant.email` | String | Minimum viable identifier; lets the landlord recognise and contact the applicant. |
| `tenant_name` **or** `tenant.full_name` | String | Primary display name on the card. May be empty for accounts with no name set. |
| `tenant_phone` **or** `tenant.phone_number` | String | Optional but useful — landlords commonly call applicants before deciding. |
| `created_at` | ISO 8601 String | Already assumed; the app shows "Applied 2h ago". Please confirm it is present. |

A bare `tenant` UUID is explicitly **not** sufficient — the app detects and
discards UUID-only values rather than displaying an opaque identifier as if
it were a person's name.

## Also worth confirming

These are unrelated to identity but are undocumented in the guide, and the app
is currently guessing at them:

1. **`GET /tenant/marketplace/` response schema.** The guide (§ "Tenant
   Marketplace And Applications") documents the filters and behaviour but
   gives no example response body. Flutter currently accepts a top-level array
   where each entry is either a property object with an `available_units`
   array, or a `{ "property": {...}, "available_units": [...] }` wrapper.
   Please confirm which is correct, or paste a real response.

2. **`GET /tenant/applications/` and the approve/reject responses.** Same
   situation — no documented body. Flutter assumes the same application object
   shape described above.

3. **Whether `property` is included on application objects.** The app shows
   the property name on each card and falls back to the literal string
   "Property" when it is absent.

## Verification-status note

Consider whether the landlord should also see the applicant's
`verification_status`. Every applicant must already be `VERIFIED` to reach
these endpoints at all (guide §5.10), so it may be redundant — but if a
tenant's status can change after applying, surfacing it would matter for the
approve decision.

## Privacy

Only expose applicant contact details to the landlord who owns the unit being
applied for, and only for applications actually addressed to them. Please do
not add applicant contact details to any tenant-facing endpoint.

# Property verification, location and batch-unit API contract

This contract supports the verified-property flow in the Flutter app. A property is **not public or bookable** until its `verification_status` becomes `VERIFIED`.

## Authentication and response conventions

All endpoints require `Authorization: Bearer <access_token>`. Use the existing JSON error format and return field errors with HTTP `422`. Property creation is `multipart/form-data`; all other write endpoints are JSON.

## 1. Create a property with a pin and proof

`POST /api/users/properties/`

### Form fields

| Field | Type | Required | Notes |
| --- | --- | --- | --- |
| `name` | string | yes | Property name |
| `address`, `city`, `state` | string | yes | Human-readable address |
| `latitude`, `longitude` | decimal | yes | WGS84 coordinates; validate range and precision to 6 decimals |
| `verification_method` | string | yes | Currently `LIVE_VIDEO_AND_DEED` |
| `photos` | file[] | no | Repeat this key for each property image |
| `verification_video` | file | yes | A freshly captured MP4/MOV, maximum 60 seconds and 100 MB |
| `deed` | file | yes | PDF/JPG/PNG proof of ownership, maximum 15 MB |

The API must reject a missing location, video, or deed with a field-level `422` error. Store original files privately, malware-scan them, and expose signed URLs only to authorized staff/landlords. Do not make a deed publicly readable.

### Response `201 Created`

```json
{
  "id": "property_01J...",
  "name": "Sunset Beach House",
  "address": "12 Ocean View Road",
  "city": "Lagos",
  "state": "Lagos",
  "latitude": 6.428055,
  "longitude": 3.421944,
  "photo_urls": ["https://signed-cdn.example/property.jpg"],
  "verification_status": "PENDING_REVIEW",
  "created_at": "2026-08-11T10:20:30Z"
}
```

Allowed statuses: `PENDING_REVIEW`, `VERIFIED`, `REJECTED`, `NEEDS_MORE_EVIDENCE`. On rejection or a request for more evidence, return a non-public `verification_note` to the landlord.

### Verification safeguards

- Verify server capture time and video duration; reject old/re-uploaded evidence unless a reviewer explicitly requests it.
- Queue the submission for human review and optionally run a liveness/location consistency check before approval.
- Check that the pin is plausibly near the stated address; do not use client GPS as sole proof of ownership.
- Audit every reviewer decision with reviewer ID, reason, and timestamp.

## 2. List and retrieve properties

`GET /api/users/properties/` and `GET /api/users/properties/{property_id}/`

Return the fields above. The list response should also include `unit_count`, while the detail endpoint should include a `units` array or the client may call the units endpoint below. Return photo URLs as temporary signed URLs. Never return deed/video URLs from public/list responses.

## 3. Units for a property

`GET /api/users/properties/{property_id}/units/`

Each unit should include tenant summary data only for the owner/authorized manager:

```json
{
  "id": "unit_01J...",
  "unit_number": "A1",
  "bedrooms": 2,
  "bathrooms": 2,
  "rent_amount": "450000.00",
  "is_occupied": true,
  "tenant": {
    "id": "user_01J...",
    "full_name": "Ada Okafor",
    "email": "ada@example.com",
    "phone_number": "+2348012345678"
  },
  "created_at": "2026-08-11T10:20:30Z"
}
```

For any unauthorized role, omit `tenant`, `email`, and `phone_number` rather than returning partial sensitive data.

## 4. Create units in a batch

`POST /api/users/properties/{property_id}/units/batch/`

```json
{
  "units": [
    {"unit_number": "A1", "bedrooms": 2, "bathrooms": 2, "rent_amount": "450000.00"},
    {"unit_number": "A2", "bedrooms": 2, "bathrooms": 2, "rent_amount": "450000.00"}
  ]
}
```

Rules:

- Accept 1–100 rows; `unit_number` must be unique within both the request and property.
- Validate every row before insertion and create the full batch in one database transaction.
- A malformed row returns `422` with an indexed error such as `{"errors":{"units.1.unit_number":["Already exists."]}}`; no rows are created.
- Return `201 Created` and an array of the newly created unit objects, in the request order.

## Recommended status endpoints (optional)

If review can take more than a few seconds, add `GET /api/users/properties/{property_id}/verification/` and push/email a notification when a reviewer changes status. This lets the mobile app show `UNDER REVIEW`, `VERIFIED`, or `ACTION REQUIRED` without polling the full property record.

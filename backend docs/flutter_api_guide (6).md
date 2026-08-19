# Landa OS Backend API Documentation & Flutter Integration Specification

> **Audience:** Flutter developers building the Landa OS mobile experience for all supported roles.
>
> **Source of truth:** This guide was generated from the current Django backend in this workspace: `landa_os/urls.py`, `users/urls.py`, `users/views.py`, `users/serializers.py`, and `users/models.py`.

---

## 1. General API Conventions

### Base URLs
- **Local Development:** `http://127.0.0.1:8000/api/users`
- **Android Emulator Local Development:** `http://10.0.2.2:8000/api/users`
- **Physical Device Local Development:** `http://<backend-machine-lan-ip>:8000/api/users`
- **Staging:** `https://landa-os-staging.onrender.com/api/users`
- **Production:** Not configured in the current repository.

> Current route prefix is `/api/users/`, not `/api/v1/`. The Render root URL (`https://landa-os-staging.onrender.com/`) is a health-check endpoint. Flutter should use the staging API base URL above for application requests.

### Machine-Readable API Contract

Flutter can inspect the staging API contract at:

```text
https://landa-os-staging.onrender.com/api/schema/
```

Local development exposes the same contract at:

```text
http://127.0.0.1:8000/api/schema/
```

This endpoint is a lightweight OpenAPI-style contract for Flutter-facing endpoints. It is not a full Swagger UI yet, but it gives the app team a stable machine-readable reference for routes, auth requirements, verification gating, accepted content types, and important enums.

### Health Check

#### `GET /`
Confirms the staging backend is online.

- **Authentication:** Public
- **HTTP Method:** `GET`
- **Path:** `/`

##### Response `200 OK`

```json
{
  "status": "ok",
  "service": "Landa OS API"
}
```

#### `GET /health/`
Returns the same response as `/`.

#### `GET /health/db/`
Confirms the staging backend can connect to the database.

- **Authentication:** Public
- **HTTP Method:** `GET`
- **Path:** `/health/db/`

##### Response `200 OK`

```json
{
  "status": "ok",
  "service": "Landa OS API",
  "database": "ok"
}
```

Flutter does not need to call this during normal app usage, but the backend team should run it before telling Flutter that staging is ready.

### Staging Verification Status

The following staging mobile flow has been tested successfully in prior smoke checks:

```text
database health -> password reset request -> register owner/tenant -> login -> profile -> dashboard gate blocks unverified users -> verification start -> verification webhook completion -> verification status -> property creation with location/proof uploads -> property detail -> batch unit creation -> units -> tenant assignment -> agreements -> signing -> payments -> receipt -> notifications
```

Last full successful staging smoke: 2026-08-14.

Staging checks on 2026-08-15:

- `/health/` returned OK.
- `/health/db/` returned OK.
- The stale agreement `7057c951-503c-4b51-b16e-2495ce905697` and its linked payment were cleared from staging through Supabase SQL Editor.
- New escrow routes are available in the backend code and are covered locally by tests.
- A full remote smoke test from this workspace was attempted twice, but both attempts were interrupted by SSL/network transport errors before completion. These were connection-level failures, not API validation failures.
- Local backend verification passed after the compliance foundation work: 79 tests passed.

The latest staging verification confirms that dashboard/product APIs are blocked until a user reaches `VERIFIED` status.

### Current Verification Provider Mode

Staging currently uses the `mock` verification provider so Flutter integration can continue while Smile ID account enablement is being resolved.

Smile ID sandbox connectivity was tested on 2026-08-14. The backend successfully sent a signed Smile ID request and the job appeared in the Smile ID dashboard, but Smile ID rejected the job with:

```text
Unable to validate ID - This feature is not enabled for your Smile ID account.
```

This means the backend integration path is prepared, but the Smile ID account still needs the correct Enhanced KYC / NIN_V2 product access enabled before real Smile ID verification can complete.

This means Flutter should still build the real verification flow:

- Call `POST /consents/` before first verification.
- Call `POST /verify/` with selfie and NIN.
- Treat the response as `PENDING`.
- Poll `GET /verify/status/`.
- Unlock product screens only when the backend returns `VERIFIED`.

Flutter should not hard-code special Smile ID behavior yet. Once Smile ID enables the required sandbox product access, the backend can switch providers while keeping these same mobile endpoint paths.

Message for Flutter:

```text
For staging, the backend will keep using mock verification while Smile ID account enablement is pending. The mock flow is designed so the mobile app can still move forward: after submitting verification, the app should poll /verify/status/ until it returns VERIFIED. This simulates what Smile ID will later do asynchronously.

Please do not call the Smile ID webhook directly from Flutter. Just call /verify/ and then /verify/status/.
```

### Request & Response Format
- Most endpoints accept and return JSON (`application/json`).
- `POST /verify/` accepts `multipart/form-data` because it uploads a selfie image.
- `POST /properties/` accepts `multipart/form-data` because it uploads property verification files.
- JSON property names use `snake_case`.
- Character encoding is UTF-8.
- Current backend responses are mostly raw Django REST Framework serializer payloads, not the wrapped `status/message/data` format shown in the sample template.
- Internal server errors now return JSON instead of Django HTML error pages.

### HTTP Headers

| Header Name | Value / Format | Requirement | Description |
| :--- | :--- | :--- | :--- |
| `Content-Type` | `application/json` | Required for JSON POST/PATCH requests | Specifies JSON payload format |
| `Content-Type` | `multipart/form-data` | Required for `POST /verify/` and `POST /properties/` | Let Dio/HTTP set the multipart boundary automatically |
| `Accept` | `application/json` | Recommended | Specifies expected response format |
| `Authorization` | `Bearer <ACCESS_TOKEN>` | Required for protected endpoints | JWT authentication token |

---

## 2. Data Handling & Type Standards

### Data Type Mapping Table

| Data Concept | JSON Format | Example Value | Flutter Notes |
| :--- | :--- | :--- | :--- |
| Identifiers | `String` UUID | `"3fa85f64-5717-4562-b3fc-2c963f66afa6"` | Model as `String` in Dart |
| Dates | `String` date | `"2026-09-01"` | Used for tenancy agreement start/end dates |
| Timestamps | `String` ISO 8601 | `"2026-08-06T09:30:00Z"` | Django returns timezone-aware datetimes when `USE_TZ=True` |
| Monetary Amounts | Decimal string or number | `"450000.00"` | Current backend uses `DecimalField`; treat as string-safe decimal in Flutter |
| Booleans | `Boolean` | `true` | Do not parse from `1`/`0` |
| Enums / Statuses | `String` uppercase | `"OWNER"`, `"TENANT"`, `"EXECUTED"` | Use enum mapping with fallback handling |
| Nullable Fields | `null` | `"tenant_signed_at": null` | Support nullable Dart fields |
| Lists / Arrays | Array `[]` | `[]` | List endpoints return raw arrays |

### Current Enums

| Enum | Values |
| :--- | :--- |
| User `role` | `OWNER`, `TENANT` |
| User `verification_status` | `UNVERIFIED`, `PENDING`, `VERIFIED`, `FAILED` |
| Property `verification_method` | `LIVE_VIDEO_AND_DEED` |
| Property `verification_status` | `PENDING_REVIEW`, `VERIFIED`, `REJECTED`, `NEEDS_MORE_EVIDENCE` |
| Tenancy agreement `status` | `DRAFT`, `PENDING`, `EXECUTED`, `EXPIRED`, `VOIDED` |
| Legacy tenancy agreement `status` | `SENT`, `TENANT_SIGNED`, `ACTIVATED` may still appear for older staging records |
| Payment `status` | `PENDING`, `ESCROW`, `DISPUTED`, `FAILED`, `RELEASED`, `REFUNDED` |
| Notification `notification_type` | `AGREEMENT_RECEIVED`, `AGREEMENT_SIGNED`, `AGREEMENT_EXECUTED`, `PAYMENT_INITIATED`, `PAYMENT_RECORDED`, `ESCROW_DISPUTED`, `ESCROW_RELEASED` |

### Tenant Lookup Inputs

For landlord workflows where the app identifies a tenant, the backend accepts any of these values:

- Tenant UUID string, for example `"f8c88b5d-3d87-4f86-b402-39d8e68bff88"`
- Tenant email address, case-insensitive, for example `"tenant@example.com"`
- Tenant phone number, for example `"07054315799"`

This applies to:

- `PATCH /units/{unit_id}/assign/` field `tenant_id`
- `POST /agreements/` field `tenant`

The matched account must have `role: "TENANT"`. If no tenant account matches, the backend returns `400 Bad Request` with a field error on `tenant_id` or `tenant`.

---

## 3. Authentication

The backend uses JWT authentication through `djangorestframework-simplejwt`.

Flutter should store:
- `access`: short-lived JWT used in `Authorization: Bearer <ACCESS_TOKEN>`.
- `refresh`: refresh token used to request a new access token.

If any protected endpoint returns `401 Unauthorized`, Flutter should try token refresh once. If refresh fails, clear local auth state and redirect to login.

### Standard SimpleJWT Error Shape

```json
{
  "detail": "Authentication credentials were not provided."
}
```

or:

```json
{
  "detail": "Given token not valid for any token type",
  "code": "token_not_valid",
  "messages": []
}
```

### Standard Server Error Shape

If an internal backend/database problem occurs, Flutter should expect JSON:

```json
{
  "detail": "A database error occurred. Please try again later.",
  "code": "SERVER_ERROR"
}
```

or:

```json
{
  "detail": "An unexpected server error occurred. Please try again later.",
  "code": "SERVER_ERROR"
}
```

Flutter should show a generic retry message for these responses and should not try to parse Django HTML error pages.

---

## 4. Flutter Integration Architecture

Recommended repository boundaries:

```text
[Flutter UI Widget] -> [Controller / Provider]
                  -> [Repository Interface]
                  -> [Dio/HTTP API Client]
                  -> [Landa OS Django API]
```

Suggested repositories:
- `IAuthRepository`: register, login, refresh token, profile.
- `IVerificationRepository`: identity/selfie verification.
- `IPropertyRepository`: landlord properties and units.
- `IAgreementRepository`: tenancy bridge agreement creation, listing, signing.
- `IPaymentRepository`: demo rent payment and escrow release.
- `INotificationRepository`: list and mark notifications read.

---

## 5. Endpoint Documentation

### 5.1 Register User

#### `POST /register/`
Creates a new user account as either a landlord/owner or tenant.

- **Authentication:** Public
- **HTTP Method:** `POST`
- **Path:** `/api/users/register/`

##### Request Body

```json
{
  "email": "tenant@example.com",
  "password": "Strongpass123!",
  "phone": "+2348012345678",
  "role": "TENANT"
}
```

##### Response `201 Created`

```json
{
  "email": "tenant@example.com",
  "phone": "+2348012345678",
  "role": "TENANT"
}
```

##### Validation Errors

```json
{
  "email": ["user with this email already exists."],
  "password": ["This password is too short."],
  "role": ["Invalid role."]
}
```

---

### 5.2 Login

#### `POST /login/`
Authenticates a user and returns JWT tokens plus the user profile.

- **Authentication:** Public
- **HTTP Method:** `POST`
- **Path:** `/api/users/login/`

##### Request Body

```json
{
  "email": "tenant@example.com",
  "password": "Strongpass123!"
}
```

##### Response `200 OK`

```json
{
  "refresh": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "access": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "user": {
    "id": "b991873e-d49d-4c24-aa6f-d8fce80ebeee",
    "email": "tenant@example.com",
    "phone": "+2348012345678",
    "role": "TENANT",
    "verification_status": "UNVERIFIED"
  }
}
```

##### Response `401 Unauthorized`

```json
{
  "detail": "Invalid email or password."
}
```

---

### 5.3 Refresh Token

#### `POST /token/refresh/`
Returns a new access token from a valid refresh token.

- **Authentication:** Public
- **HTTP Method:** `POST`
- **Path:** `/api/users/token/refresh/`

##### Request Body

```json
{
  "refresh": "<REFRESH_TOKEN>"
}
```

##### Response `200 OK`

```json
{
  "access": "<NEW_ACCESS_TOKEN>"
}
```

---

### 5.4 User Profile

#### `GET /profile/`
Returns the authenticated user's profile.

- **Authentication:** Required
- **HTTP Method:** `GET`
- **Path:** `/api/users/profile/`

##### Response `200 OK`

```json
{
  "id": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
  "email": "tenant@example.com",
  "phone": "+2348012345678",
  "role": "TENANT",
  "verification_status": "UNVERIFIED"
}
```

---

### 5.5 Request Password Reset

#### `POST /password/reset/request/`
Requests password-reset instructions for an email address.

- **Authentication:** Public
- **HTTP Method:** `POST`
- **Path:** `/api/users/password/reset/request/`

The backend always returns the same `202 Accepted` response whether or not the email exists. Flutter should show the same success message in both cases.

##### Request Body

```json
{
  "email": "owner@example.com"
}
```

##### Response `202 Accepted`

```json
{
  "message": "If an account exists for this email address, password-reset instructions have been sent."
}
```

---

### 5.6 Confirm Password Reset

#### `POST /password/reset/confirm/`
Sets a new password using a reset token.

- **Authentication:** Public
- **HTTP Method:** `POST`
- **Path:** `/api/users/password/reset/confirm/`

##### Request Body

```json
{
  "token": "opaque-single-use-token",
  "new_password": "NewStrongpass123!"
}
```

##### Response `204 No Content`

No response body.

##### Response `400 Bad Request`

```json
{
  "code": "INVALID_OR_EXPIRED_TOKEN",
  "detail": "Invalid or expired password reset token."
}
```

---

### 5.7 Identity Verification

#### `POST /consents/`
Records verification/privacy consent for the authenticated user. Flutter must call this before `POST /verify/`.

- **Authentication:** Required
- **HTTP Method:** `POST`
- **Path:** `/api/users/consents/`
- **Content-Type:** `application/json`

##### Request Body

```json
{
  "consent_type": "VERIFICATION_PRIVACY",
  "version": "2026-08-15"
}
```

##### Response `201 Created`

```json
{
  "id": "0aa2a026-f5b3-4328-b962-f8f28170076f",
  "consent_type": "VERIFICATION_PRIVACY",
  "version": "2026-08-15",
  "accepted_at": "2026-08-15T10:30:00Z"
}
```

#### `GET /consents/`
Lists the authenticated user's consent records.

- **Authentication:** Required
- **HTTP Method:** `GET`
- **Path:** `/api/users/consents/`

#### `POST /verify/`
Starts identity verification by uploading a selfie and NIN. The backend does not store raw NIN. It stores a tokenized NIN fingerprint and a provider reference for the verification attempt.

Current staging note: the provider value in verification responses is expected to be `"mock"` until Smile ID enables the required Enhanced KYC / NIN_V2 sandbox product access. `POST /verify/` returns `PENDING` first, then mock mode auto-completes the attempt so the next `GET /verify/status/` can return `VERIFIED`.

- **Authentication:** Required
- **HTTP Method:** `POST`
- **Path:** `/api/users/verify/`
- **Content-Type:** `multipart/form-data`

Do not manually hard-code the multipart boundary. Let the Flutter HTTP client/Dio build the `FormData` request and set the full `Content-Type` header.

##### Multipart Fields

| Field | Type | Required | Description |
| :--- | :--- | :--- | :--- |
| `selfie` | File | Yes | Selfie image. Content type must start with `image/`. Maximum size is 5MB. |
| `nin` | String | Yes | Exactly 11 numeric digits. Example: `"12345678901"` |
| `given_names` | String | No | Required for Smile ID sandbox test identities unless already saved on the user profile. Example: `"Amina Fatou"` |
| `last_name` | String | No | Required for Smile ID sandbox test identities unless already saved on the user profile. Example: `"Clearwater"` |
| `email` | String | No | Defaults to the authenticated user's email. For sandbox cases, use the Smile ID test identity email. |

##### Smile ID Sandbox Test Identity

When staging is switched to `VERIFICATION_PROVIDER=smile_id`, Smile ID sandbox matching uses the test identity names and email. Use any 11-digit NIN that passes the NIN regex, then pair it with one of the Smile ID sandbox identities.

Successful sandbox test:

```text
country: NG
id_type: NIN_V2
nin: any 11 digits, for example 00000000000
given_names: Amina Fatou
last_name: Clearwater
email: amina.clearwater@example.com
```

High-risk failure test:

```text
given_names: Rashid Omar
last_name: Dangerfield
email: rashid.dangerfield@example.com
```

##### Response `202 Accepted`

```json
{
  "status": "PENDING",
  "badge": "PENDING",
  "attempt": {
    "id": "9b8a07be-6731-4df7-996d-036be5f9cc3d",
    "provider": "mock",
    "provider_reference": "mock_6f8a6f71c25f4e36a90df0f731ecf613",
    "status": "PENDING",
    "failure_reason": "",
    "created_at": "2026-08-10T10:00:00Z",
    "completed_at": null
  },
  "user": {
    "id": "b991873e-d49d-4c24-aa6f-d8fce80ebeee",
    "email": "tenant@example.com",
    "phone": "+2348012345678",
    "role": "TENANT",
    "verification_status": "PENDING",
    "verification_failure_reason": "",
    "verification_cooldown_until": null,
    "first_name": "",
    "last_name": "",
    "welcome_name": "tenant"
  }
}
```

Flutter should treat `POST /verify/` as the start of verification, not the final success state. The app should then call `GET /verify/status/` to check whether the user is `PENDING`, `VERIFIED`, or `FAILED`.

##### Response `429 Too Many Requests`

If the user has failed verification too many times:

```json
{
  "detail": "Verification is temporarily locked after too many failed attempts.",
  "cooldown_until": "2026-08-11T10:00:00Z"
}
```

##### Response `403 Forbidden`

If verification/privacy consent has not been accepted yet:

```json
{
  "code": "CONSENT_REQUIRED",
  "detail": "Accept verification and privacy consent before starting verification."
}
```

Flutter should route this response to the consent screen, then retry verification after `POST /consents/` succeeds.

##### Response `400 Bad Request`

Invalid NIN:

```json
{
  "nin": ["NIN must contain only numbers."]
}
```

Missing selfie:

```json
{
  "selfie": ["No file was submitted."]
}
```

Non-image selfie:

```json
{
  "selfie": ["Selfie must be an image file."]
}
```

Selfie larger than 5MB:

```json
{
  "selfie": ["Selfie image must not exceed 5MB."]
}
```

##### Response `401 Unauthorized`

```json
{
  "detail": "Authentication credentials were not provided."
}
```

---

### 5.8 Check Verification Status

#### `GET /verify/status/`
Returns the authenticated user's current verification status and latest attempt.

- **Authentication:** Required
- **HTTP Method:** `GET`
- **Path:** `/api/users/verify/status/`

##### Response `200 OK`

```json
{
  "verification_status": "PENDING",
  "verification_failure_reason": "",
  "verification_cooldown_until": null,
  "latest_attempt": {
    "id": "9b8a07be-6731-4df7-996d-036be5f9cc3d",
    "provider": "mock",
    "provider_reference": "mock_6f8a6f71c25f4e36a90df0f731ecf613",
    "status": "PENDING",
    "failure_reason": "",
    "created_at": "2026-08-10T10:00:00Z",
    "completed_at": null
  }
}
```

Flutter should use this endpoint after starting verification and whenever the app needs to decide whether to show the dashboard or the verification screen.

---

### 5.9 Smile ID Webhook

#### `POST /webhooks/smile-id/`
Receives verification results from the identity provider.

- **Authentication:** Public provider callback
- **HTTP Method:** `POST`
- **Path:** `/api/users/webhooks/smile-id/`

Flutter should not call this endpoint during normal mobile app usage. It is included here so the mobile team understands how `PENDING` becomes `VERIFIED` or `FAILED`.

---

### 5.10 Verification Gate For Product APIs

All dashboard/product APIs now require the authenticated user to have:

```text
verification_status = VERIFIED
```

If the user is logged in but not verified, Flutter should expect:

```json
{
  "detail": "Complete identity verification before accessing this feature."
}
```

with:

```text
403 Forbidden
```

This applies to property, unit, tenant assigned-unit, agreement, payment, and notification endpoints. Auth/profile/verification endpoints remain available before verification.

---

### 5.11 List Landlord Properties

#### `GET /properties/`
Returns properties owned by the authenticated landlord.

- **Authentication:** Required
- **Roles:** `OWNER`
- **HTTP Method:** `GET`
- **Path:** `/api/users/properties/`

##### Response `200 OK`

```json
[
  {
    "id": "6723b659-0834-40e9-a42a-81b355ddf969",
    "name": "Sunset House",
    "address": "123 Main Street",
    "city": "Lagos",
    "state": "Lagos",
    "latitude": "6.428055",
    "longitude": "3.421944",
    "photo_urls": [],
    "verification_method": "LIVE_VIDEO_AND_DEED",
    "verification_status": "PENDING_REVIEW",
    "verification_note": "",
    "unit_count": 2,
    "created_at": "2026-08-06T09:30:00Z"
  }
]
```

---

### 5.12 Create Property

#### `POST /properties/`
Creates a property for the authenticated landlord with verification evidence.

- **Authentication:** Required
- **Roles:** `OWNER`
- **HTTP Method:** `POST`
- **Path:** `/api/users/properties/`
- **Content-Type:** `multipart/form-data`

##### Multipart Fields

| Field | Type | Required | Notes |
| :--- | :--- | :--- | :--- |
| `name` | String | Yes | Property name |
| `address` | String | Yes | Street/address text |
| `city` | String | Yes | City |
| `state` | String | Yes | State |
| `latitude` | Decimal string | Yes | Must be between `-90` and `90`, 6 decimal places supported |
| `longitude` | Decimal string | Yes | Must be between `-180` and `180`, 6 decimal places supported |
| `verification_method` | String | Yes | Currently `LIVE_VIDEO_AND_DEED` |
| `verification_video` | File | Yes | MP4/MOV, max 100MB |
| `deed` | File | Yes | PDF/JPG/PNG, max 15MB |
| `photos` | File[] | No | Repeat the `photos` key for multiple JPG/PNG/WEBP images. Max 10 per property, max 5MB each. |
| `listing_video` | File | No | MP4/MOV property tour video. Max 50MB. One video per property. |

##### Response `201 Created`

```json
{
  "id": "6723b659-0834-40e9-a42a-81b355ddf969",
  "name": "Sunset House",
  "address": "123 Main Street",
  "city": "Lagos",
  "state": "Lagos",
  "latitude": "6.428055",
  "longitude": "3.421944",
  "photo_urls": [
    "https://landa-os-staging.onrender.com/media/property_photos/front.jpg"
  ],
  "cover_photo_url": "https://landa-os-staging.onrender.com/media/property_photos/front.jpg",
  "video_url": "https://ekdofhlayixtjmhxvlzy.supabase.co/storage/v1/object/public/landa-staging-media/properties/videos/tour.mp4",
  "verification_method": "LIVE_VIDEO_AND_DEED",
  "verification_status": "PENDING_REVIEW",
  "verification_note": "",
  "unit_count": null,
  "created_at": "2026-08-06T09:30:00Z"
}
```

##### Response `422 Unprocessable Entity`

```json
{
  "latitude": ["This field is required."],
  "verification_video": ["No file was submitted."],
  "deed": ["No file was submitted."]
}
```

##### Response `403 Forbidden`

```json
{
  "detail": "Only landlords can create properties."
}
```

---

### 5.13 Manage Property Listing Photos

#### `GET /properties/{property_id}/photos/`
Lists the landlord-owned property's uploaded listing photos.

#### `POST /properties/{property_id}/photos/`
Uploads listing photos after property creation.

- **Authentication:** Required
- **Roles:** `OWNER`
- **Content-Type:** `multipart/form-data`

##### Multipart Fields

| Field | Type | Required | Notes |
| :--- | :--- | :--- | :--- |
| `photos` | File[] | Yes | Repeat the `photos` key. JPG/PNG/WEBP only, max 10 total photos per property, max 5MB each. |

##### Response `201 Created`

```json
[
  {
    "id": "PHOTO_UUID",
    "image_url": "https://landa-os-staging.onrender.com/media/property_photos/front.jpg",
    "created_at": "2026-08-18T09:30:00Z"
  }
]
```

#### `DELETE /properties/{property_id}/photos/{photo_id}/`
Deletes one listing photo from the landlord-owned property.

Success response:

```text
204 No Content
```

Listing media now uses Supabase Storage. Flutter should render the returned URLs directly.

---

### 5.14 Manage Property Listing Video

Each property supports one listing/property-tour video.

#### `GET /properties/{property_id}/video/`

Returns:

```json
{
  "video_url": "https://ekdofhlayixtjmhxvlzy.supabase.co/storage/v1/object/public/landa-staging-media/properties/videos/tour.mp4"
}
```

If no video exists:

```json
{
  "video_url": null
}
```

#### `POST /properties/{property_id}/video/`

Uploads or replaces the listing video.

- **Authentication:** Required
- **Roles:** `OWNER`
- **Content-Type:** `multipart/form-data`

| Field | Type | Required | Notes |
| :--- | :--- | :--- | :--- |
| `video` | File | Yes | MP4/MOV, max 50MB |

#### `DELETE /properties/{property_id}/video/`

Deletes the listing video.

Success response:

```text
204 No Content
```

---

### 5.15 Get Property Detail

#### `GET /properties/{property_id}/`
Returns one landlord-owned property with property fields and a `units` array.

- **Authentication:** Required
- **Roles:** `OWNER`
- **HTTP Method:** `GET`
- **Path:** `/api/users/properties/{property_id}/`

##### Response `200 OK`

```json
{
  "id": "6723b659-0834-40e9-a42a-81b355ddf969",
  "name": "Sunset House",
  "address": "123 Main Street",
  "city": "Lagos",
  "state": "Lagos",
  "latitude": "6.428055",
  "longitude": "3.421944",
  "photo_urls": [],
  "verification_method": "LIVE_VIDEO_AND_DEED",
  "verification_status": "PENDING_REVIEW",
  "verification_note": "",
  "unit_count": 1,
  "created_at": "2026-08-06T09:30:00Z",
  "units": [
    {
      "id": "c82c03a7-1a89-41ce-aebe-bce7904f43cf",
      "unit_number": "A1",
      "bedrooms": 2,
      "bathrooms": 2,
      "rent_amount": "450000.00",
      "is_occupied": false,
      "tenant": null,
      "created_at": "2026-08-06T09:30:00Z"
    }
  ]
}
```

---

### 5.14 List Units For Property

#### `GET /properties/{property_id}/units/`
Returns units under a landlord-owned property.

- **Authentication:** Required
- **Roles:** `OWNER`
- **HTTP Method:** `GET`
- **Path:** `/api/users/properties/{property_id}/units/`

##### Path Parameters

| Parameter | Type | Required | Description |
| :--- | :--- | :--- | :--- |
| `property_id` | UUID string | Yes | Property ID |

##### Response `200 OK`

```json
[
  {
    "id": "c82c03a7-1a89-41ce-aebe-bce7904f43cf",
    "unit_number": "A1",
    "bedrooms": 2,
    "bathrooms": 2,
    "rent_amount": "450000.00",
    "is_occupied": true,
    "tenant": {
      "id": "f8c88b5d-3d87-4f86-b402-39d8e68bff88",
      "full_name": "Ada Okafor",
      "email": "ada@example.com",
      "phone_number": "+2348012345678"
    },
    "created_at": "2026-08-06T09:30:00Z"
  }
]
```

The nested `tenant` object is returned only to the property owner. Unoccupied units return `tenant: null`.

---

### 5.15 Create Unit

#### `POST /properties/{property_id}/units/`
Creates a unit under a landlord-owned property.

- **Authentication:** Required
- **Roles:** `OWNER`
- **HTTP Method:** `POST`
- **Path:** `/api/users/properties/{property_id}/units/`

##### Request Body

```json
{
  "unit_number": "A1",
  "bedrooms": 2,
  "bathrooms": 2,
  "rent_amount": "450000.00"
}
```

##### Validation Rules

- `rent_amount` must be greater than zero.

##### Response `201 Created`

```json
{
  "id": "c82c03a7-1a89-41ce-aebe-bce7904f43cf",
  "unit_number": "A1",
  "bedrooms": 2,
  "bathrooms": 2,
  "rent_amount": "450000.00",
  "is_occupied": false,
  "tenant": null,
  "created_at": "2026-08-06T09:30:00Z"
}
```

---

### 5.16 Create Units In Batch

#### `POST /properties/{property_id}/units/batch/`
Creates 1 to 100 units under a landlord-owned property in one request.

- **Authentication:** Required
- **Roles:** `OWNER`
- **HTTP Method:** `POST`
- **Path:** `/api/users/properties/{property_id}/units/batch/`

##### Request Body

```json
{
  "units": [
    {
      "unit_number": "A1",
      "bedrooms": 2,
      "bathrooms": 2,
      "rent_amount": "450000.00"
    },
    {
      "unit_number": "A2",
      "bedrooms": 2,
      "bathrooms": 2,
      "rent_amount": "450000.00"
    }
  ]
}
```

##### Response `201 Created`

```json
[
  {
    "id": "c82c03a7-1a89-41ce-aebe-bce7904f43cf",
    "unit_number": "A1",
    "bedrooms": 2,
    "bathrooms": 2,
    "rent_amount": "450000.00",
    "is_occupied": false,
    "tenant": null,
    "created_at": "2026-08-06T09:30:00Z"
  }
]
```

##### Response `422 Unprocessable Entity`

If any row is invalid, no units are created:

```json
{
  "errors": {
    "units": {
      "units.1": {
        "unit_number": ["Already exists."]
      }
    }
  }
}
```

---

### 5.17 Assign Tenant To Unit

#### `PATCH /units/{unit_id}/assign/`
Assigns a tenant account to a landlord-owned unit.

- **Authentication:** Required
- **Roles:** `OWNER`
- **HTTP Method:** `PATCH`
- **Path:** `/api/users/units/{unit_id}/assign/`

##### Request Body

```json
{
  "tenant_id": "tenant@example.com"
}
```

##### Validation Rules

- The target tenant must be a `TENANT` account.
- `tenant_id` may be the tenant UUID, email address, or phone number.
- If the unit is already assigned to a different tenant, the backend returns `400 Bad Request`.

##### Response `200 OK`

```json
{
  "id": "c82c03a7-1a89-41ce-aebe-bce7904f43cf",
  "unit_number": "A1",
  "bedrooms": 2,
  "bathrooms": 2,
  "rent_amount": "450000.00",
  "is_occupied": true,
  "tenant": {
    "id": "f8c88b5d-3d87-4f86-b402-39d8e68bff88",
    "full_name": "Ada Okafor",
    "email": "ada@example.com",
    "phone_number": "+2348012345678"
  },
  "created_at": "2026-08-06T09:30:00Z"
}
```

---

### 5.18 Get Tenant Assigned Unit

#### `GET /tenant/assigned-unit/`
Returns the first unit assigned to the authenticated tenant.

- **Authentication:** Required
- **Roles:** `TENANT`
- **HTTP Method:** `GET`
- **Path:** `/api/users/tenant/assigned-unit/`

##### Response `200 OK`

```json
{
  "id": "c82c03a7-1a89-41ce-aebe-bce7904f43cf",
  "unit_number": "A1",
  "bedrooms": 2,
  "bathrooms": 2,
  "rent_amount": "450000.00",
  "is_occupied": true,
  "property": {
    "id": "6723b659-0834-40e9-a42a-81b355ddf969",
    "name": "Sunset House",
    "address": "123 Main Street",
    "city": "Lagos",
    "state": "Lagos",
    "created_at": "2026-08-06T09:30:00Z"
  }
}
```

##### Response `404 Not Found`

```json
{
  "detail": "No assigned unit found."
}
```

---

### 5.19 List Tenancy Agreements

#### `GET /agreements/`
Returns tenancy agreements for the authenticated user.

- **Authentication:** Required
- **Roles:** `OWNER`, `TENANT`
- **HTTP Method:** `GET`
- **Path:** `/api/users/agreements/`

Owners receive agreements where they are the landlord. Tenants receive agreements where they are the tenant.

##### Response `200 OK`

```json
[
  {
    "id": "69be1df4-cbd1-47cf-b55a-0e2864ef4670",
    "unit": "c82c03a7-1a89-41ce-aebe-bce7904f43cf",
    "unit_number": "A1",
    "property": {
      "id": "6723b659-0834-40e9-a42a-81b355ddf969",
      "name": "Sunset House",
      "address": "123 Main Street",
      "city": "Lagos",
      "state": "Lagos",
      "created_at": "2026-08-06T09:30:00Z"
    },
    "landlord": "18b053b1-464c-49c8-8905-47a96809b6c0",
    "landlord_email": "owner@example.com",
    "tenant": "f8c88b5d-3d87-4f86-b402-39d8e68bff88",
    "tenant_email": "tenant@example.com",
    "rent_amount": "450000.00",
    "start_date": "2026-09-01",
    "end_date": "2027-08-31",
    "rules": "No illegal activity. Keep shared areas clean.",
    "agreement_text": "Tenancy Agreement...",
    "status": "PENDING",
    "agreement_content_hash": "0d2f4f0b7f8a9f2e...",
    "tenant_signature_hash": "",
    "landlord_signature_hash": "",
    "tenant_signed_at": null,
    "landlord_signed_at": null,
    "activated_at": null,
    "executed_at": null,
    "pay_rent_unlocked": false,
    "created_at": "2026-08-06T09:30:00Z"
  }
]
```

---

### 5.20 Create Tenancy Agreement

#### `POST /agreements/`
Creates a tenancy agreement and sends it to a tenant. This also assigns the unit to the tenant and creates an `AGREEMENT_RECEIVED` notification.

- **Authentication:** Required
- **Roles:** `OWNER`
- **HTTP Method:** `POST`
- **Path:** `/api/users/agreements/`

##### Request Body

```json
{
  "unit": "c82c03a7-1a89-41ce-aebe-bce7904f43cf",
  "tenant": "tenant@example.com",
  "rent_amount": "450000.00",
  "start_date": "2026-09-01",
  "end_date": "2027-08-31",
  "rules": "No illegal activity. Keep shared areas clean."
}
```

##### Response `201 Created`

```json
{
  "id": "69be1df4-cbd1-47cf-b55a-0e2864ef4670",
  "unit": "c82c03a7-1a89-41ce-aebe-bce7904f43cf",
  "unit_number": "A1",
  "property": {
    "id": "6723b659-0834-40e9-a42a-81b355ddf969",
    "name": "Sunset House",
    "address": "123 Main Street",
    "city": "Lagos",
    "state": "Lagos",
    "created_at": "2026-08-06T09:30:00Z"
  },
  "landlord": "18b053b1-464c-49c8-8905-47a96809b6c0",
  "landlord_email": "owner@example.com",
  "tenant": "f8c88b5d-3d87-4f86-b402-39d8e68bff88",
  "tenant_email": "tenant@example.com",
  "rent_amount": "450000.00",
  "start_date": "2026-09-01",
  "end_date": "2027-08-31",
  "rules": "No illegal activity. Keep shared areas clean.",
  "agreement_text": "Tenancy Agreement...",
    "status": "PENDING",
    "agreement_content_hash": "0d2f4f0b7f8a9f2e...",
    "tenant_signature_hash": "",
    "landlord_signature_hash": "",
    "tenant_signed_at": null,
    "landlord_signed_at": null,
    "activated_at": null,
    "executed_at": null,
    "pay_rent_unlocked": false,
  "created_at": "2026-08-06T09:30:00Z"
}
```

##### Validation Rules

- Only `OWNER` users can create agreements.
- Agreement unit must belong to the authenticated landlord.
- Agreement tenant must have role `TENANT`.
- `tenant` may be the tenant UUID, email address, or phone number.
- End date must be after start date.
- If the unit is already assigned, it must be assigned to the same tenant.
- `rent_amount` must be greater than zero.

---

### 5.21 Sign Tenancy Agreement

#### `POST /agreements/{agreement_id}/sign/`
Signs an agreement for the authenticated party.

- **Authentication:** Required
- **Roles:** `OWNER`, `TENANT`
- **HTTP Method:** `POST`
- **Path:** `/api/users/agreements/{agreement_id}/sign/`

##### Signing Flow

1. Tenant signs first while agreement status is `PENDING`.
2. Agreement remains `PENDING`, but `tenant_signed_at` and `tenant_signature_hash` are set.
3. Landlord signs after tenant.
4. Agreement status becomes `EXECUTED`.
5. `pay_rent_unlocked` becomes `true`.

##### Request Body

```json
{}
```

##### Response `200 OK` After Tenant Signs

```json
{
  "id": "69be1df4-cbd1-47cf-b55a-0e2864ef4670",
  "status": "PENDING",
  "tenant_signed_at": "2026-08-06T09:35:00Z",
  "tenant_signature_hash": "7c0c7ad8d8c9...",
  "landlord_signed_at": null,
  "activated_at": null,
  "executed_at": null,
  "pay_rent_unlocked": false
}
```

##### Response `200 OK` After Landlord Signs

```json
{
  "id": "69be1df4-cbd1-47cf-b55a-0e2864ef4670",
  "status": "EXECUTED",
  "tenant_signed_at": "2026-08-06T09:35:00Z",
  "landlord_signed_at": "2026-08-06T09:40:00Z",
  "landlord_signature_hash": "8df07a6d4b1f...",
  "activated_at": "2026-08-06T09:40:00Z",
  "executed_at": "2026-08-06T09:40:00Z",
  "pay_rent_unlocked": true
}
```

> Actual response contains the full tenancy agreement object. The examples above show the fields Flutter usually needs to update UI state after signing.

##### Common Errors

```json
{
  "detail": "Landlord can sign only after tenant signs."
}
```

```json
{
  "detail": "You are not a party to this agreement."
}
```

---

### 5.22 List Payments

#### `GET /payments/`
Returns payments visible to the authenticated user.

- **Authentication:** Required
- **Roles:** `OWNER`, `TENANT`
- **HTTP Method:** `GET`
- **Path:** `/api/users/payments/`

Owners receive payments for their agreements. Tenants receive their own payments.

##### Response `200 OK`

```json
[
  {
    "id": "39c5843f-1e32-4366-af93-275fbb0c89e2",
    "agreement": "69be1df4-cbd1-47cf-b55a-0e2864ef4670",
    "agreement_status": "EXECUTED",
    "tenant": "f8c88b5d-3d87-4f86-b402-39d8e68bff88",
    "tenant_email": "tenant@example.com",
    "amount": "450000.00",
    "reference": "LR-1A2B3C4D5E6F",
    "status": "ESCROW",
    "paid_at": "2026-08-06T09:45:00Z",
    "escrow_release_at": "2026-08-08T09:45:00Z",
    "is_ready_for_release": false,
    "released_at": null
  }
]
```

---

### 5.23 Initialize Rent Payment

#### `POST /payments/`
Initializes a rent payment through the configured backend payment provider. Payment is only allowed after the agreement is `EXECUTED` for new PRD records. Older `ACTIVATED` records remain supported for compatibility.

Current staging note: staging is now using `PAYMENT_PROVIDER=paystack` for real Paystack sandbox checkout testing. This is still test mode, so it does not move live money.

Paystack sandbox was tested successfully on 2026-08-14:

- `POST /payments/` created a Paystack checkout session and returned `authorization_url`, `access_code`, and `provider_reference`.
- The Paystack test checkout was completed.
- `POST /payments/{payment_id}/verify/` verified the payment with Paystack.
- The backend moved the payment from `PENDING` to `ESCROW`.
- The receipt endpoint returned the confirmed payment amounts and escrow timestamps.

Local/test environments can still use `PAYMENT_PROVIDER=mock`. In mock mode, this endpoint returns Paystack-style checkout fields and immediately moves the payment to `ESCROW`, so Flutter can test receipt/payment screens without using Paystack.

- **Authentication:** Required
- **Roles:** `TENANT`
- **HTTP Method:** `POST`
- **Path:** `/api/users/payments/`

##### Request Body

```json
{
  "agreement": "69be1df4-cbd1-47cf-b55a-0e2864ef4670"
}
```

##### Validation Rules

- Only `TENANT` users can create rent payments.
- `agreement` is required and must be a UUID.
- The agreement must belong to the authenticated tenant.
- The agreement must have rent payment unlocked.
- New PRD agreements use `EXECUTED`; older `ACTIVATED` records are still accepted.
- Retrying the same payment request for an agreement that already has a payment returns the existing payment with `200 OK` instead of creating a duplicate.
- A 5% platform fee is added to the rent amount. Flutter should display `amount`, `platform_fee`, and `total_amount` from the backend response instead of recalculating them.

##### Response `201 Created`

```json
{
  "id": "39c5843f-1e32-4366-af93-275fbb0c89e2",
  "agreement": "69be1df4-cbd1-47cf-b55a-0e2864ef4670",
  "agreement_status": "EXECUTED",
  "tenant": "f8c88b5d-3d87-4f86-b402-39d8e68bff88",
  "tenant_email": "tenant@example.com",
  "amount": "450000.00",
  "platform_fee": "22500.00",
  "total_amount": "472500.00",
  "reference": "LR-1A2B3C4D5E6F",
  "provider": "paystack",
  "provider_reference": "LR-1A2B3C4D5E6F",
  "authorization_url": "https://checkout.paystack.com/example",
  "access_code": "access_code_from_paystack",
  "status": "PENDING",
  "paid_at": null,
  "escrow_release_at": null,
  "is_ready_for_release": false,
  "released_at": null
}
```

##### Response `200 OK` Duplicate Retry

If Flutter retries the same payment creation after a payment already exists, the backend returns the existing payment object:

```json
{
  "id": "39c5843f-1e32-4366-af93-275fbb0c89e2",
  "agreement": "69be1df4-cbd1-47cf-b55a-0e2864ef4670",
  "agreement_status": "EXECUTED",
  "tenant": "f8c88b5d-3d87-4f86-b402-39d8e68bff88",
  "tenant_email": "tenant@example.com",
  "amount": "450000.00",
  "platform_fee": "22500.00",
  "total_amount": "472500.00",
  "reference": "LR-1A2B3C4D5E6F",
  "provider": "paystack",
  "provider_reference": "LR-1A2B3C4D5E6F",
  "authorization_url": "https://checkout.paystack.com/example",
  "access_code": "access_code_from_paystack",
  "status": "PENDING",
  "paid_at": null,
  "escrow_release_at": null,
  "is_ready_for_release": false,
  "released_at": null
}
```

##### Response `400 Bad Request`

```json
{
  "detail": "Rent payment is locked until both parties sign the agreement."
}
```

Missing `agreement`:

```json
{
  "agreement": ["This field is required."]
}
```

##### Response `403 Forbidden`

```json
{
  "detail": "Only tenants can create rent payments."
}
```

---

### 5.24 Verify Provider Payment

#### `POST /payments/{payment_id}/verify/`
Verifies a payment by provider reference and moves successful payments into escrow.

- **Authentication:** Required
- **Roles:** `TENANT`
- **HTTP Method:** `POST`
- **Path:** `/api/users/payments/{payment_id}/verify/`

##### Request Body

```json
{
  "reference": "LR-1A2B3C4D5E6F"
}
```

`reference` is optional. If omitted, the backend verifies using the payment's stored reference.

##### Response `200 OK`

Returns the payment object. Successful verification sets:

```text
status = ESCROW
paid_at = current backend time
escrow_release_at = paid_at + 48 hours
```

In real Paystack mode, Flutter should open `authorization_url`, then call this endpoint after the payment flow returns to the app. This is the primary mobile path because it gives the app an immediate answer after checkout.

The Paystack webhook is the backup path. If the user closes the app or Flutter cannot call verify because of network issues, Paystack can still notify the backend and move the payment into escrow. Both paths are idempotent: if payment is already in `ESCROW`, repeated verify/webhook success will not create duplicate payment notifications.

Paystack sandbox card for staging tests:

```text
Card: 4084 0840 8408 4081
Expiry: any future month/year, for example 07/27
CVV: 408
PIN/OTP: use the value shown by Paystack during test checkout
```

Recommended Flutter behavior:

```text
1. POST /payments/
2. Open authorization_url
3. When checkout closes or returns, call POST /payments/{payment_id}/verify/
4. If status is ESCROW, show receipt/payment status screen
5. If status is PENDING, allow retry/check again
6. If status is FAILED, show payment failed and let user start again
```

---

### 5.25 Get Escrow Status

#### `GET /payments/{payment_id}/escrow/`
Returns the escrow status, countdown, dispute availability, and payment fields for the authenticated tenant or landlord.

- **Authentication:** Required
- **Roles:** `OWNER`, `TENANT`
- **HTTP Method:** `GET`
- **Path:** `/api/users/payments/{payment_id}/escrow/`

##### Response `200 OK`

```json
{
  "id": "39c5843f-1e32-4366-af93-275fbb0c89e2",
  "agreement": "69be1df4-cbd1-47cf-b55a-0e2864ef4670",
  "agreement_status": "EXECUTED",
  "tenant": "f8c88b5d-3d87-4f86-b402-39d8e68bff88",
  "tenant_email": "tenant@example.com",
  "amount": "450000.00",
  "platform_fee": "22500.00",
  "total_amount": "472500.00",
  "reference": "LR-1A2B3C4D5E6F",
  "status": "ESCROW",
  "paid_at": "2026-08-06T09:45:00Z",
  "escrow_release_at": "2026-08-08T09:45:00Z",
  "escrow_seconds_remaining": 172800,
  "can_dispute": true,
  "disputed_at": null,
  "dispute_reason": "",
  "is_ready_for_release": false,
  "released_at": null
}
```

Flutter should use `escrow_seconds_remaining` and `can_dispute` from the backend instead of calculating dispute-window rules independently.

---

### 5.26 Dispute Escrow Payment

#### `POST /payments/{payment_id}/dispute/`
Lets the tenant dispute an escrow payment during the active 48-hour escrow window.

- **Authentication:** Required
- **Roles:** `TENANT`
- **HTTP Method:** `POST`
- **Path:** `/api/users/payments/{payment_id}/dispute/`

##### Request Body

```json
{
  "reason": "The unit was not handed over as agreed."
}
```

`reason` is optional, but Flutter should collect a short reason when possible.

##### Response `200 OK`

Returns the payment object with:

```text
status = DISPUTED
can_dispute = false
disputed_at = backend timestamp
dispute_reason = provided reason
```

When a dispute is created, the backend also creates an `ESCROW_DISPUTED` notification for the landlord and an audit log record.

##### Response `400 Bad Request`

```json
{
  "detail": "The dispute window has closed.",
  "escrow_release_at": "2026-08-08T09:45:00Z"
}
```

---

### 5.27 Release Escrow Payment

#### `POST /payments/{payment_id}/release/`
Releases escrow payment to landlord after the escrow release time. Disputed payments cannot be released. For demos, landlord can pass `demo_override: true`.

- **Authentication:** Required
- **Roles:** `OWNER`
- **HTTP Method:** `POST`
- **Path:** `/api/users/payments/{payment_id}/release/`

##### Request Body

```json
{
  "demo_override": true
}
```

##### Response `200 OK`

```json
{
  "id": "39c5843f-1e32-4366-af93-275fbb0c89e2",
  "agreement": "69be1df4-cbd1-47cf-b55a-0e2864ef4670",
  "agreement_status": "EXECUTED",
  "tenant": "f8c88b5d-3d87-4f86-b402-39d8e68bff88",
  "tenant_email": "tenant@example.com",
  "amount": "450000.00",
  "platform_fee": "22500.00",
  "total_amount": "472500.00",
  "reference": "LR-1A2B3C4D5E6F",
  "status": "RELEASED",
  "paid_at": "2026-08-06T09:45:00Z",
  "escrow_release_at": "2026-08-08T09:45:00Z",
  "escrow_seconds_remaining": 0,
  "can_dispute": false,
  "disputed_at": null,
  "dispute_reason": "",
  "is_ready_for_release": false,
  "released_at": "2026-08-06T10:00:00Z"
}
```

##### Response `400 Bad Request`

```json
{
  "detail": "Escrow is not ready for release yet.",
  "escrow_release_at": "2026-08-08T09:45:00Z"
}
```

---

### 5.28 Get Payment Receipt

#### `GET /payments/{payment_id}/`
Returns a payment receipt/detail object for the authenticated tenant or landlord.

- **Authentication:** Required
- **Roles:** `OWNER`, `TENANT`
- **HTTP Method:** `GET`
- **Path:** `/api/users/payments/{payment_id}/`

Tenants can view their own payment receipts. Landlords can view receipts for payments attached to their tenancy agreements.

##### Response `200 OK`

```json
{
  "id": "39c5843f-1e32-4366-af93-275fbb0c89e2",
  "reference": "LR-1A2B3C4D5E6F",
  "amount": "450000.00",
  "platform_fee": "22500.00",
  "total_amount": "472500.00",
  "status": "ESCROW",
  "agreement": "69be1df4-cbd1-47cf-b55a-0e2864ef4670",
  "agreement_status": "EXECUTED",
  "tenant": "f8c88b5d-3d87-4f86-b402-39d8e68bff88",
  "tenant_email": "tenant@example.com",
  "landlord_email": "owner@example.com",
  "property": {
    "id": "6723b659-0834-40e9-a42a-81b355ddf969",
    "name": "Sunset House",
    "address": "123 Main Street",
    "city": "Lagos",
    "state": "Lagos",
    "created_at": "2026-08-06T09:30:00Z"
  },
  "unit": {
    "id": "c82c03a7-1a89-41ce-aebe-bce7904f43cf",
    "unit_number": "A1",
    "bedrooms": 2,
    "bathrooms": 2,
    "rent_amount": "450000.00",
    "is_occupied": true,
    "tenant": "f8c88b5d-3d87-4f86-b402-39d8e68bff88",
    "created_at": "2026-08-06T09:30:00Z"
  },
  "paid_at": "2026-08-06T09:45:00Z",
  "escrow_release_at": "2026-08-08T09:45:00Z",
  "escrow_seconds_remaining": 172800,
  "can_dispute": true,
  "disputed_at": null,
  "dispute_reason": "",
  "is_ready_for_release": false,
  "released_at": null
}
```

##### Response `404 Not Found`

```json
{
  "detail": "No Payment matches the given query."
}
```

---

### 5.29 List Notifications

#### `GET /notifications/`
Returns notifications for the authenticated user.

- **Authentication:** Required
- **Roles:** `OWNER`, `TENANT`
- **HTTP Method:** `GET`
- **Path:** `/api/users/notifications/`

Optional query parameters:

| Parameter | Example | Description |
| :--- | :--- | :--- |
| `type` | `PAYMENT_RECORDED` | Returns only notifications with this type |
| `is_read` | `false` | Returns only read or unread notifications |

##### Response `200 OK`

```json
[
  {
    "id": "d4067ff3-5468-4282-805f-d297248183f7",
    "notification_type": "AGREEMENT_RECEIVED",
    "message": "New tenancy agreement received for Sunset House - A1.",
    "is_read": false,
    "created_at": "2026-08-06T09:30:00Z"
  }
]
```

---

### 5.30 Mark Notification As Read

#### `PATCH /notifications/{notification_id}/read/`
Marks a notification as read for the authenticated user.

- **Authentication:** Required
- **Roles:** `OWNER`, `TENANT`
- **HTTP Method:** `PATCH`
- **Path:** `/api/users/notifications/{notification_id}/read/`

##### Response `200 OK`

```json
{
  "id": "d4067ff3-5468-4282-805f-d297248183f7",
  "notification_type": "AGREEMENT_RECEIVED",
  "message": "New tenancy agreement received for Sunset House - A1.",
  "is_read": true,
  "created_at": "2026-08-06T09:30:00Z"
}
```

---

### 5.31 Export User Data

#### `GET /data-export/`
Returns a basic export of the authenticated user's profile, consent records, verification attempts, agreements, payments, notifications, and deletion requests.

- **Authentication:** Required
- **Roles:** `OWNER`, `TENANT`
- **HTTP Method:** `GET`
- **Path:** `/api/users/data-export/`

Flutter does not need this in the core rental flow. It is available for account/privacy screens or admin-assisted support.

---

### 5.32 Request Account Deletion

#### `POST /deletion-requests/`
Creates a deletion request for review. This does not immediately delete financial, agreement, payment, or audit records.

- **Authentication:** Required
- **Roles:** `OWNER`, `TENANT`
- **HTTP Method:** `POST`
- **Path:** `/api/users/deletion-requests/`

##### Request Body

```json
{
  "reason": "I want to close my account."
}
```

##### Response `201 Created`

```json
{
  "id": "1fdaeb11-e3bd-4590-9172-88e68f66116f",
  "reason": "I want to close my account.",
  "status": "PENDING",
  "requested_at": "2026-08-15T10:45:00Z",
  "reviewed_at": null
}
```

#### `GET /deletion-requests/`
Lists the authenticated user's deletion requests.

- **Authentication:** Required
- **Path:** `/api/users/deletion-requests/`

---

## 6. Current Implementation Notes For Flutter

### No Global Response Wrapper Yet

The sample template recommends:

```json
{
  "status": "success",
  "message": "Message",
  "data": {}
}
```

The current backend does not use that pattern yet. Flutter should currently parse:
- Object responses directly as model JSON.
- List responses directly as `List<dynamic>`.
- Error responses as either `{"detail": "..."}` or field validation maps.

### No Pagination Yet

List endpoints currently return full arrays. Flutter repositories should still be designed so pagination can be added later without changing UI code heavily.

### Monetary Amounts Are Decimal Values

The template recommends amounts in kobo as integers. Current models use `DecimalField` and return values like `"450000.00"`. Flutter should parse them as decimal-safe strings or use a money/decimal helper instead of `double` for business logic.

### Only Two Roles Exist In Code

The developer notes mention artisans as secondary, but the current backend supports only:
- `OWNER`
- `TENANT`

Do not build live artisan API flows until backend support exists.

### Staging Smoke Test Before Flutter Handoff

Before telling Flutter that staging is ready, the backend team should run:

```powershell
.\venv\Scripts\python.exe scripts\staging_smoke_test.py
```

This verifies the main mobile API flow and catches staging-only issues such as database connectivity, missing migrations, or HTML `500` pages.

Latest staging result: passed on 2026-08-17.

Current Block 8/9 smoke coverage includes:
- Register/login
- Consent before verification
- Mock verification and verification status polling
- Dashboard gate before verification
- Property, unit, batch unit, and tenant assignment
- Tenant marketplace browse/apply and landlord application list
- Agreement creation, tenant signing, and landlord signing
- Payment initialization/list/receipt
- Escrow status fields
- Notification list, filters, and mark-read
- Data export
- Deletion request creation/list

Note for Paystack staging: when `PAYMENT_PROVIDER=paystack`, payment initialization creates a Paystack checkout and the payment can remain `PENDING` until Paystack confirms it through verification/webhook. Flutter should show the checkout/status screen and poll or refresh payment status instead of assuming payment is immediately final.

---

### Tenant Marketplace And Applications

The tenant marketplace lets verified tenants browse available units grouped by property.

A unit is available when `is_occupied=false` and no active agreement has started for that unit. Active agreement statuses are treated as unavailable: `DRAFT`, `PENDING`, `SENT`, `TENANT_SIGNED`, `EXECUTED`, and `ACTIVATED`.

#### `GET /tenant/marketplace/`

Lists properties with available units for tenants.

Optional filters: `city`, `state`, `min_rent`, `max_rent`, `bedrooms`, `bathrooms`.

```text
GET /api/users/tenant/marketplace/?city=Lagos&max_rent=300000&bedrooms=2
```

Response shape:

```json
[
  {
    "id": "PROPERTY_UUID",
    "name": "Sunset House",
    "address": "12 Listing Road",
    "city": "Lagos",
    "state": "Lagos",
    "photo_urls": [
      "https://landa-os-staging.onrender.com/media/property_photos/front.jpg"
    ],
    "cover_photo_url": "https://landa-os-staging.onrender.com/media/property_photos/front.jpg",
    "video_url": "https://ekdofhlayixtjmhxvlzy.supabase.co/storage/v1/object/public/landa-staging-media/properties/videos/tour.mp4",
    "available_units": [
      {
        "id": "UNIT_UUID",
        "unit_number": "A1",
        "bedrooms": 2,
        "bathrooms": 2,
        "rent_amount": "300000.00",
        "created_at": "2026-08-18T09:00:00Z"
      }
    ]
  }
]
```

#### `POST /tenant/applications/`

Tenant applies for an available unit with one button.

```json
{
  "unit": "UNIT_UUID",
  "message": "I am interested in this unit and can move in soon."
}
```

`message` is optional and can be blank. Maximum length: 1000 characters.

If the same tenant applies again for the same unit while the first application is still pending, backend returns the existing application instead of creating a duplicate.

Tenant-facing application responses do not include applicant contact details.

#### `GET /tenant/applications/`

Lists the tenant's own applications.

#### `GET /landlord/applications/`

Lists applications received by the landlord. Optional filter: `?status=PENDING`.

Landlord-facing application responses include applicant identity:

```json
[
  {
    "id": "APPLICATION_UUID",
    "property": {
      "id": "PROPERTY_UUID",
      "name": "Sunset House",
      "address": "12 Listing Road",
      "city": "Lagos",
      "state": "Lagos"
    },
    "unit": {
      "id": "UNIT_UUID",
      "unit_number": "A1",
      "bedrooms": 2,
      "bathrooms": 2,
      "rent_amount": "300000.00"
    },
    "tenant": {
      "id": "TENANT_UUID",
      "full_name": "Ada Okafor",
      "email": "ada@example.com",
      "phone_number": "+2348012345678"
    },
    "tenant_name": "Ada Okafor",
    "tenant_email": "ada@example.com",
    "tenant_phone": "+2348012345678",
    "tenant_verification_status": "VERIFIED",
    "unit_number": "A1",
    "rent_amount": "300000.00",
    "message": "I am interested in this unit and can move in soon.",
    "status": "PENDING",
    "agreement_id": null,
    "applied_at": "2026-08-18T09:00:00Z",
    "created_at": "2026-08-18T09:00:00Z",
    "decided_at": null
  }
]
```

#### `POST /landlord/applications/{application_id}/approve/`

Landlord approves an application and backend creates a pending tenancy agreement.

```json
{
  "start_date": "2026-09-01",
  "end_date": "2027-08-31",
  "rules": "Standard tenancy rules apply."
}
```

After approval, the application becomes `APPROVED`, the agreement becomes `PENDING`, the unit becomes occupied, other pending applications for that unit are rejected, and the tenant receives approval/agreement notifications.

#### `POST /landlord/applications/{application_id}/reject/`

Landlord rejects a pending application.

---

## 7. Suggested Flutter Models

Recommended model names:
- `AuthTokens`
- `UserProfile`
- `Property`
- `Unit`
- `TenantAssignedUnit`
- `TenancyAgreement`
- `Payment`
- `NotificationItem`
- `MarketplaceProperty`
- `AvailableUnit`
- `RentalApplication`

Each model should support nullable timestamps and unknown enum values gracefully.

---

## 8. Endpoint Checklist

| Feature | Method | Path | Auth | Roles |
| :--- | :--- | :--- | :--- | :--- |
| Register | `POST` | `/api/users/register/` | No | Public |
| Login | `POST` | `/api/users/login/` | No | Public |
| Request password reset | `POST` | `/api/users/password/reset/request/` | No | Public |
| Confirm password reset | `POST` | `/api/users/password/reset/confirm/` | No | Public |
| Refresh token | `POST` | `/api/users/token/refresh/` | No | Public |
| Profile | `GET` | `/api/users/profile/` | Yes | `OWNER`, `TENANT` |
| Accept consent | `POST` | `/api/users/consents/` | Yes | `OWNER`, `TENANT` |
| List consents | `GET` | `/api/users/consents/` | Yes | `OWNER`, `TENANT` |
| Verify identity | `POST` | `/api/users/verify/` | Yes | `OWNER`, `TENANT` |
| Check verification status | `GET` | `/api/users/verify/status/` | Yes | `OWNER`, `TENANT` |
| Smile ID webhook | `POST` | `/api/users/webhooks/smile-id/` | No | Provider callback |
| List properties | `GET` | `/api/users/properties/` | Yes + verified | `OWNER` |
| Create property | `POST` | `/api/users/properties/` | Yes + verified | `OWNER` |
| Get property detail | `GET` | `/api/users/properties/{property_id}/` | Yes + verified | `OWNER` |
| List property photos | `GET` | `/api/users/properties/{property_id}/photos/` | Yes + verified | `OWNER` |
| Upload property photos | `POST` | `/api/users/properties/{property_id}/photos/` | Yes + verified | `OWNER` |
| Delete property photo | `DELETE` | `/api/users/properties/{property_id}/photos/{photo_id}/` | Yes + verified | `OWNER` |
| Get property video | `GET` | `/api/users/properties/{property_id}/video/` | Yes + verified | `OWNER` |
| Upload/replace property video | `POST` | `/api/users/properties/{property_id}/video/` | Yes + verified | `OWNER` |
| Delete property video | `DELETE` | `/api/users/properties/{property_id}/video/` | Yes + verified | `OWNER` |
| List units | `GET` | `/api/users/properties/{property_id}/units/` | Yes + verified | `OWNER` |
| Create unit | `POST` | `/api/users/properties/{property_id}/units/` | Yes + verified | `OWNER` |
| Create units in batch | `POST` | `/api/users/properties/{property_id}/units/batch/` | Yes + verified | `OWNER` |
| Assign tenant | `PATCH` | `/api/users/units/{unit_id}/assign/` | Yes + verified | `OWNER` |
| Tenant assigned unit | `GET` | `/api/users/tenant/assigned-unit/` | Yes + verified | `TENANT` |
| Tenant marketplace | `GET` | `/api/users/tenant/marketplace/` | Yes + verified | `TENANT` |
| Tenant applications | `GET` | `/api/users/tenant/applications/` | Yes + verified | `TENANT` |
| Apply for unit | `POST` | `/api/users/tenant/applications/` | Yes + verified | `TENANT` |
| Landlord applications | `GET` | `/api/users/landlord/applications/` | Yes + verified | `OWNER` |
| Approve application | `POST` | `/api/users/landlord/applications/{application_id}/approve/` | Yes + verified | `OWNER` |
| Reject application | `POST` | `/api/users/landlord/applications/{application_id}/reject/` | Yes + verified | `OWNER` |
| List agreements | `GET` | `/api/users/agreements/` | Yes + verified | `OWNER`, `TENANT` |
| Create agreement | `POST` | `/api/users/agreements/` | Yes + verified | `OWNER` |
| Sign agreement | `POST` | `/api/users/agreements/{agreement_id}/sign/` | Yes + verified | `OWNER`, `TENANT` |
| List payments | `GET` | `/api/users/payments/` | Yes + verified | `OWNER`, `TENANT` |
| Initialize payment | `POST` | `/api/users/payments/` | Yes + verified | `TENANT` |
| Get payment receipt | `GET` | `/api/users/payments/{payment_id}/` | Yes + verified | `OWNER`, `TENANT` |
| Verify payment | `POST` | `/api/users/payments/{payment_id}/verify/` | Yes + verified | `TENANT` |
| Get escrow status | `GET` | `/api/users/payments/{payment_id}/escrow/` | Yes + verified | `OWNER`, `TENANT` |
| Dispute escrow | `POST` | `/api/users/payments/{payment_id}/dispute/` | Yes + verified | `TENANT` |
| Release escrow | `POST` | `/api/users/payments/{payment_id}/release/` | Yes + verified | `OWNER` |
| Paystack webhook | `POST` | `/api/users/webhooks/paystack/` | No | Provider callback |
| List notifications | `GET` | `/api/users/notifications/` | Yes + verified | `OWNER`, `TENANT` |
| Mark notification read | `PATCH` | `/api/users/notifications/{notification_id}/read/` | Yes + verified | `OWNER`, `TENANT` |
| Export user data | `GET` | `/api/users/data-export/` | Yes | `OWNER`, `TENANT` |
| Create deletion request | `POST` | `/api/users/deletion-requests/` | Yes | `OWNER`, `TENANT` |
| List deletion requests | `GET` | `/api/users/deletion-requests/` | Yes | `OWNER`, `TENANT` |



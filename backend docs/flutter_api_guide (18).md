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

Latest full successful staging smoke: 2026-08-24.

Current staging status on 2026-08-24:

- `/health/` returned OK.
- `/health/db/` returned OK.
- Full staging smoke passed with real Paystack bank-account verification.
- The smoke test covered the updated landlord payout flow: landlord can create a property, create an agreement, and execute the agreement before payout setup; payout account setup is tested separately through the resolve-confirm flow.
- Flutter must not ask the landlord to type an account name. The backend resolves the account name through Paystack and Flutter only asks the landlord to confirm the returned name.

For private staging smoke checks with real payout details, run:

```powershell
$env:STAGING_PAYOUT_BANK_NAME='<BANK NAME>'
$env:STAGING_PAYOUT_ACCOUNT_NUMBER='<10 DIGIT ACCOUNT NUMBER>'
.\venv\Scripts\python.exe scripts\staging_smoke_test.py
Remove-Item Env:\STAGING_PAYOUT_BANK_NAME
Remove-Item Env:\STAGING_PAYOUT_ACCOUNT_NUMBER
```

Historical staging checks on 2026-08-15:

- `/health/` returned OK.
- `/health/db/` returned OK.
- The stale agreement `7057c951-503c-4b51-b16e-2495ce905697` and its linked payment were cleared from staging through Supabase SQL Editor.
- New escrow routes are available in the backend code and are covered locally by tests.
- Earlier remote smoke attempts were interrupted by SSL/network transport errors before completion. That issue has since been superseded by the successful 2026-08-21 staging smoke result above.

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
| User `role` | `OWNER`, `TENANT`, `ARTISAN` |
| User `verification_status` | `UNVERIFIED`, `PENDING`, `VERIFIED`, `FAILED` |
| Property `verification_method` | `LIVE_VIDEO`, `LIVE_VIDEO_AND_DEED` |
| Property `verification_status` | `PENDING_REVIEW`, `VERIFIED`, `REJECTED`, `NEEDS_MORE_EVIDENCE` |
| Tenancy agreement `status` | `DRAFT`, `PENDING`, `EXECUTED`, `EXPIRED`, `VOIDED` |
| Legacy tenancy agreement `status` | `SENT`, `TENANT_SIGNED`, `ACTIVATED` may still appear for older staging records |
| Tenancy agreement `rent_plan` | `ANNUAL`, `SIX_MONTHLY`, `QUARTERLY`, `MONTHLY`, `WEEKLY` |
| Payment `status` | `PENDING`, `ESCROW`, `DISPUTED`, `FAILED`, `RELEASED`, `REFUNDED` |
| Payment `source` | `CARD`, `VAULT` |
| Vault top-up `status` | `PENDING`, `SUCCEEDED`, `FAILED`, `ABANDONED` |
| Notification `notification_type` | `AGREEMENT_RECEIVED`, `AGREEMENT_SIGNED`, `AGREEMENT_EXECUTED`, `PAYMENT_INITIATED`, `PAYMENT_RECORDED`, `ESCROW_DISPUTED`, `ESCROW_RELEASED`, `VAULT_CREDITED`, `WITHDRAWAL_REQUESTED`, `WITHDRAWAL_PAID`, `WITHDRAWAL_FAILED`, `VAULT_TOPUP_SUCCEEDED`, `VAULT_TOPUP_FAILED`, `TENANT_INVITED` |

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
  "verification_status": "UNVERIFIED",
  "payout_account_required": false,
  "payout_account_status": "NOT_REQUIRED",
  "can_create_properties": false,
  "can_execute_agreements": false,
  "payout_account_required_for": null
}
```

For verified landlords, profile tells Flutter whether payout setup is still missing for withdrawal/release flows:

```json
{
  "role": "OWNER",
  "verification_status": "VERIFIED",
  "payout_account_required": false,
  "payout_account_status": "MISSING",
  "can_create_properties": true,
  "can_execute_agreements": true,
  "payout_account_required_for": "WITHDRAWAL"
}
```

Flutter should not force payout setup immediately after owner verification. A verified landlord can create properties, units, applications, and agreements first. Prompt for payout setup from Settings or before a withdrawal/release action requires a verified payout destination.

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
| `verification_method` | String | No | `LIVE_VIDEO_AND_DEED` for yearly-rent/deed flow, `LIVE_VIDEO` for short-let/live-video-only flow. If omitted, backend treats it as `LIVE_VIDEO_AND_DEED` for older clients. |
| `verification_video` | File | Yes | MP4/MOV, max 100MB |
| `deed` | File | Conditional | Required for `LIVE_VIDEO_AND_DEED` or omitted `verification_method`; optional for `LIVE_VIDEO`. PDF/JPG/PNG, max 15MB when sent. |
| `photos` | File[] | Yes | Repeat the `photos` key for multiple JPG/PNG/WEBP images. Minimum 2 photos, max 10 per property, max 5MB each. |
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
    "https://landa-os-staging.onrender.com/media/property_photos/front.jpg",
    "https://landa-os-staging.onrender.com/media/property_photos/living-room.jpg"
  ],
  "cover_photo_url": "https://landa-os-staging.onrender.com/media/property_photos/front.jpg",
  "photo_count": 2,
  "needs_photos": false,
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
  "code": "VALIDATION_ERROR",
  "detail": "Add at least 2 photos of the property.",
  "errors": {
    "photos": ["At least 2 property photos are required."]
  }
}
```

Flutter should keep the property-create submit button disabled until at least 2 listing photos are attached. The backend still enforces the rule, so `0` or `1` photo returns `422 VALIDATION_ERROR`. More than 10 total photos also returns `422 VALIDATION_ERROR`.

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

If deleting a photo would leave the property with fewer than 2 photos, the backend blocks the delete:

```json
{
  "code": "MINIMUM_PHOTOS_REQUIRED",
  "detail": "A listed property must keep at least 2 photos."
}
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

### 5.19 Payout Account

Landlords and tenants can add payout details from Settings. Payout setup is not required for property creation or agreement execution. It is required only when a user wants to withdraw money from their vault.

Flutter must use the two-step resolve-confirm flow:

1. User selects a bank and enters account number.
2. Backend resolves the account through Paystack and returns the account name.
3. Flutter shows the returned account name for confirmation.
4. Flutter saves the account by sending only the `resolution_token`.

Flutter must not let the user type `account_name`.

#### `GET /banks/`
Returns supported banks for payout setup.

- **Authentication:** Required
- **Roles:** `OWNER`, `TENANT`
- **HTTP Method:** `GET`
- **Path:** `/api/users/banks/`

Flutter should show these banks in a picker. Flutter may send either `bank_name` or `bank_code` to the resolve endpoint; if both are sent, `bank_code` wins.

##### Response `200 OK`

```json
[
  {"name": "Access Bank", "code": "044", "slug": "access-bank"},
  {"name": "Stanbic IBTC Bank", "code": "221", "slug": "stanbic-ibtc-bank"},
  {"name": "Zenith Bank", "code": "057", "slug": "zenith-bank"}
]
```

#### `GET /payout-account/`
Returns the authenticated user's payout-account status.

- **Authentication:** Required
- **Roles:** `OWNER`, `TENANT`
- **HTTP Method:** `GET`
- **Path:** `/api/users/payout-account/`

##### Missing Account Response `200 OK`

```json
{
  "status": "MISSING",
  "payout_account_required": false,
  "payout_account_required_for": "WITHDRAWAL",
  "detail": "Add and verify payout account details before withdrawing."
}
```

##### Verified Account Response `200 OK`

```json
{
  "id": "PAYOUT_ACCOUNT_UUID",
  "bank_name": "STANBIC IBTC BANK",
  "account_number": "******6034",
  "account_name": "AYOMIDE AKINDAMOLA AKINTAN",
  "status": "VERIFIED",
  "provider": "paystack",
  "verified_at": "2026-08-21T14:00:00Z",
  "last_verified_at": "2026-08-21T14:00:00Z"
}
```

Account numbers are masked in responses.

#### `POST /payout-account/resolve/`
Resolves bank details and returns the provider-confirmed account name.

- **Authentication:** Required
- **Roles:** `OWNER`, `TENANT`
- **HTTP Method:** `POST`
- **Path:** `/api/users/payout-account/resolve/`
- **Content-Type:** `application/json`

##### Request Body

```json
{
  "bank_name": "STANBIC IBTC BANK",
  "account_number": "0023966034"
}
```

`bank_code` may be sent instead of `bank_name`.

##### Response `200 OK`

```json
{
  "bank_name": "Stanbic IBTC Bank",
  "bank_code": "221",
  "account_number": "0023966034",
  "account_number_masked": "******6034",
  "account_name": "AKINTAN AYOMIDE AKINDAMOLA",
  "resolution_token": "rsl_EXAMPLE_TOKEN",
  "expires_at": "2026-08-24T17:30:00Z",
  "request_id": "req_EXAMPLE"
}
```

Flutter should show `account_name` and ask the user to confirm that it is correct.

#### `POST /payout-account/`
Creates the authenticated user's payout account from a resolved account token.

- **Authentication:** Required
- **Roles:** `OWNER`, `TENANT`
- **HTTP Method:** `POST`
- **Path:** `/api/users/payout-account/`
- **Content-Type:** `application/json`

##### Request Body

```json
{
  "resolution_token": "rsl_EXAMPLE_TOKEN"
}
```

The backend uses the earlier Paystack resolution, creates the transfer recipient, and saves the payout account. If Flutter sends `account_name`, the backend rejects the request.

##### Response `201 Created`

Returns the verified payout account with masked account number.

##### Common Errors

```json
{
  "code": "ACCOUNT_NAME_NOT_ACCEPTED",
  "detail": "Account name must come from bank verification. Resolve the account first, then confirm it."
}
```

```json
{
  "code": "PAYOUT_ACCOUNT_EXISTS",
  "detail": "You already have a payout account. Update it instead."
}
```

```json
{
  "code": "RESOLUTION_TOKEN_EXPIRED",
  "detail": "Resolve the bank account again before saving it."
}
```

#### `PATCH /payout-account/`
Creates or updates payout details from a fresh `resolution_token`.

Flutter should call `POST /payout-account/resolve/` first, then send the returned `resolution_token` to `PATCH /payout-account/`. This revalidates updates without letting the user type an account name.

---

### 5.20 List Tenancy Agreements

#### `GET /agreements/`
Returns tenancy agreements for the authenticated user.

- **Authentication:** Required
- **Roles:** `OWNER`, `TENANT`
- **HTTP Method:** `GET`
- **Path:** `/api/users/agreements/`

Owners receive agreements where they are the landlord. Tenants receive agreements where they are the tenant.

Optional filters:

| Query Param | Values | Purpose |
| :--- | :--- | :--- |
| `bucket` | `ACTION_REQUIRED`, `COMPLETED` | Use `ACTION_REQUIRED` for dashboard agreements and `COMPLETED` for Profile / My Agreements. |
| `status` | Comma-separated statuses, for example `EXECUTED,VOIDED` | Use only when the app needs exact status filtering. |

Bucket rules are the same for landlords and tenants:

- `ACTION_REQUIRED`: `DRAFT`, `PENDING`, legacy `SENT`, legacy `TENANT_SIGNED`.
- `COMPLETED`: `EXECUTED`, `EXPIRED`, `VOIDED`, legacy `ACTIVATED`.

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
    "rent_plan": "ANNUAL",
    "start_date": "2026-09-01",
    "end_date": "2027-08-31",
    "rules": "No illegal activity. Keep shared areas clean.",
    "agreement_text": "Tenancy Agreement...",
    "status": "PENDING",
    "agreement_content_hash": "0d2f4f0b7f8a9f2e...",
    "tenant_signature_hash": "",
    "landlord_signature_hash": "",
    "bucket": "ACTION_REQUIRED",
    "is_fully_signed": false,
    "awaiting_signature_from": "TENANT",
    "signed_at": null,
    "tenant_signed_at": null,
    "landlord_signed_at": null,
    "activated_at": null,
    "executed_at": null,
    "pay_rent_unlocked": false,
    "rent_payment": {
      "status": "NOT_DUE",
      "amount": "450000.00",
      "platform_fee": "22500.00",
      "total_amount": "472500.00",
      "payment_id": null
    },
    "rent_schedule": null,
    "created_at": "2026-08-06T09:30:00Z"
  }
]
```

`awaiting_signature_from` is `TENANT`, `LANDLORD`, or `null`. After execution, `rent_payment.status` becomes `DUE` until a payment exists. Existing payment states map to `IN_ESCROW`, `PAID`, `FAILED`, or the raw backend payment status when needed.

`rent_schedule` is `null` until the agreement is executable/payable. For executed agreements, Flutter receives:

```json
{
  "plan": "MONTHLY",
  "next_due_date": "2026-09-01",
  "next_amount_due": "105000.00",
  "days_until_due": 2,
  "is_overdue": false,
  "instalments_paid": 0,
  "instalments_total": 12
}
```

Rent schedule rules:

- `rent_plan` defaults to `ANNUAL`.
- Supported plans are `ANNUAL`, `SIX_MONTHLY`, `QUARTERLY`, `MONTHLY`, and `WEEKLY`.
- Agreement creation also accepts `YEARLY`, `BIANNUAL`, and `THREE_MONTHLY` as aliases.
- Non-annual plans split the annual rent across instalments.
- `next_amount_due` includes the platform fee.
- `days_until_due` and `is_overdue` are computed by the backend.
- Once the current agreement's instalments are paid, `next_due_date` shows the agreement `end_date` as the renewal due date.

Invalid bucket values return:

```json
{
  "code": "VALIDATION_ERROR",
  "detail": "Agreement bucket must be ACTION_REQUIRED or COMPLETED.",
  "errors": {
    "bucket": ["Agreement bucket must be ACTION_REQUIRED or COMPLETED."]
  }
}
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
    "bucket": "ACTION_REQUIRED",
    "is_fully_signed": false,
    "awaiting_signature_from": "TENANT",
    "signed_at": null,
    "tenant_signed_at": null,
    "landlord_signed_at": null,
    "activated_at": null,
    "executed_at": null,
    "pay_rent_unlocked": false,
    "rent_payment": {
      "status": "NOT_DUE",
      "amount": "450000.00",
      "platform_fee": "22500.00",
      "total_amount": "472500.00",
      "payment_id": null
    },
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

Important landlord payout rule:

- The tenant can sign without the landlord having payout details.
- The landlord can final-sign/execute the agreement without payout details.
- Payout setup should be handled from Settings, or when a later withdrawal/release flow needs a verified bank destination.

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
  "bucket": "ACTION_REQUIRED",
  "is_fully_signed": false,
  "awaiting_signature_from": "LANDLORD",
  "signed_at": null,
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
  "bucket": "COMPLETED",
  "is_fully_signed": true,
  "awaiting_signature_from": null,
  "signed_at": "2026-08-06T09:40:00Z",
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
Initializes a rent payment through the configured backend payment provider, or pays directly from the tenant's vault. Payment is only allowed after the agreement is `EXECUTED` for new PRD records. Older `ACTIVATED` records remain supported for compatibility.

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
  "agreement": "69be1df4-cbd1-47cf-b55a-0e2864ef4670",
  "source": "CARD"
}
```

For vault payment:

```json
{
  "agreement": "69be1df4-cbd1-47cf-b55a-0e2864ef4670",
  "source": "VAULT",
  "vault_pin": "1234"
}
```

`source` is optional. If it is missing, the backend treats the request as `CARD`.

##### Validation Rules

- Only `TENANT` users can create rent payments.
- `agreement` is required and must be a UUID.
- The agreement must belong to the authenticated tenant.
- The agreement must have rent payment unlocked.
- New PRD agreements use `EXECUTED`; older `ACTIVATED` records are still accepted.
- Retrying the same payment request for an agreement that already has a payment returns the existing payment with `200 OK` instead of creating a duplicate.
- A 5% platform fee is added to the rent amount. Flutter should display `amount`, `platform_fee`, and `total_amount` from the backend response instead of recalculating them.
- Card payments keep the existing Paystack checkout behavior.
- Vault payments require the `Idempotency-Key` header.
- Vault payments require a previously created 4-digit vault PIN.
- Vault payments immediately create an `ESCROW` payment when the tenant has enough vault balance.
- Vault payments return `authorization_url: null` and `access_code: null`.
- If a pending card payment already exists for the same agreement, a successful vault payment closes that card payment as failed/replaced.
- Retrying the same vault payment with the same `Idempotency-Key` returns the same payment and does not debit twice.

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

The landlord does not need a payout account for escrow release. Release marks the payment as `RELEASED` and credits the landlord's in-app vault balance. Bank transfer happens later through the withdrawal flow.

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

### 5.28 Vault, Top-Ups, And Withdrawals

#### `GET /vault/`
Returns the authenticated user's current vault balance. This works for verified landlords and verified tenants. If the user has never had vault activity, the backend creates a zero-balance vault and still returns `200 OK`.

- **Authentication:** Required
- **Roles:** `OWNER`, `TENANT`
- **HTTP Method:** `GET`
- **Path:** `/api/users/vault/`

##### Response `200 OK`

```json
{
  "id": "VAULT_UUID",
  "available_balance": "450000.00",
  "pending_withdrawal_balance": "100000.00",
  "total_credited": "450000.00",
  "total_withdrawn": "0.00",
  "total_spent": "0.00",
  "currency": "NGN",
  "created_at": "2026-08-24T17:00:00Z",
  "updated_at": "2026-08-24T17:05:00Z"
}
```

#### `GET /vault/pin/`
Returns whether the authenticated user has created a vault PIN and whether PIN use is currently locked.

- **Authentication:** Required
- **Roles:** `OWNER`, `TENANT`
- **HTTP Method:** `GET`
- **Path:** `/api/users/vault/pin/`

##### Response `200 OK`

```json
{
  "is_set": true,
  "locked_until": null,
  "failed_attempts_remaining": 5
}
```

#### `POST /vault/pin/`
Creates a 4-digit vault PIN. This requires the user's account password.

- **Authentication:** Required
- **Roles:** `OWNER`, `TENANT`
- **HTTP Method:** `POST`
- **Path:** `/api/users/vault/pin/`
- **Content-Type:** `application/json`

##### Request Body

```json
{
  "password": "Strongpass123!",
  "vault_pin": "1234"
}
```

##### Response `201 Created`

Returns the same status object as `GET /vault/pin/`.

#### `PATCH /vault/pin/`
Changes the vault PIN. This requires the account password and the current vault PIN.

- **Authentication:** Required
- **Roles:** `OWNER`, `TENANT`
- **HTTP Method:** `PATCH`
- **Path:** `/api/users/vault/pin/`
- **Content-Type:** `application/json`

##### Request Body

```json
{
  "password": "Strongpass123!",
  "current_vault_pin": "1234",
  "new_vault_pin": "5678"
}
```

PIN rules:

- PIN must be exactly 4 digits.
- Money cannot leave the vault until a PIN is set.
- Withdrawals and vault rent payments require the PIN.
- After 5 wrong PIN attempts, PIN actions are locked for 15 minutes.
- Forgotten PIN reset is deferred for a later recovery/support flow.

#### `GET /vault/transactions/`
Returns paginated vault ledger entries.

- **Authentication:** Required
- **Roles:** `OWNER`, `TENANT`
- **HTTP Method:** `GET`
- **Path:** `/api/users/vault/transactions/?limit=25&cursor=...`

##### Response `200 OK`

```json
{
  "results": [
    {
      "id": "TRANSACTION_UUID",
      "transaction_type": "CREDIT",
      "amount": "450000.00",
      "currency": "NGN",
      "source_reference": "escrow_release:LR-1A2B3C4D5E6F",
      "balance_after": "450000.00",
      "description": "Escrow release for LR-1A2B3C4D5E6F",
      "payment": "PAYMENT_UUID",
      "payment_reference": "LR-1A2B3C4D5E6F",
      "withdrawal_id": null,
      "created_at": "2026-08-24T17:05:00Z"
    }
  ],
  "next_cursor": null,
  "has_more": false
}
```

Top-up ledger entries use:

```text
transaction_type = CREDIT
source_reference = topup:TU-...
description = Vault top-up TU-...
```

#### `POST /vault/topups/`
Starts a tenant vault top-up and returns Paystack-style checkout fields. The vault is not credited when this endpoint is called. The vault is credited only after provider confirmation through verify or webhook.

- **Authentication:** Required
- **Roles:** `TENANT`
- **HTTP Method:** `POST`
- **Path:** `/api/users/vault/topups/`
- **Content-Type:** `application/json`
- **Required header:** `Idempotency-Key`

##### Request Body

```json
{
  "amount": "150000.00"
}
```

##### Response `201 Created`

```json
{
  "id": "TOPUP_UUID",
  "amount": "150000.00",
  "currency": "NGN",
  "status": "PENDING",
  "reference": "TU-1A2B3C4D9E0F",
  "authorization_url": "https://checkout.paystack.com/abc123",
  "access_code": "abc123",
  "provider_reference": "TU-1A2B3C4D9E0F",
  "failure_reason": "",
  "created_at": "2026-08-30T12:00:00Z",
  "completed_at": null
}
```

Rules for Flutter:

- Generate one `Idempotency-Key` per top-up attempt and reuse it if retrying the same attempt.
- Open `authorization_url` for checkout.
- After the user returns from checkout, call `POST /vault/topups/{topup_id}/verify/`.
- In local/mock mode, the top-up stays `PENDING` until verify is called.
- If a top-up becomes `ABANDONED`, the user should start a fresh top-up.

##### Common Errors

```json
{
  "code": "AMOUNT_TOO_SMALL",
  "detail": "Enter at least NGN 1,000 to top up your vault.",
  "field": "amount"
}
```

```json
{
  "code": "AMOUNT_TOO_LARGE",
  "detail": "The most you can add at once is NGN 5,000,000.",
  "field": "amount"
}
```

```json
{
  "code": "IDEMPOTENCY_KEY_REQUIRED",
  "detail": "Idempotency-Key header is required."
}
```

#### `POST /vault/topups/{topup_id}/verify/`
Verifies a tenant vault top-up after checkout closes. This call is safe to repeat. If the top-up already succeeded, failed, or was abandoned, the backend returns the current top-up unchanged.

- **Authentication:** Required
- **Roles:** `TENANT`
- **HTTP Method:** `POST`
- **Path:** `/api/users/vault/topups/{topup_id}/verify/`
- **Content-Type:** `application/json`

##### Request Body

The body may be empty. If provided, the reference must match the top-up.

```json
{
  "reference": "TU-1A2B3C4D9E0F"
}
```

##### Response `200 OK`

Returns the same top-up object with the latest status.

#### `GET /vault/topups/`
Returns paginated tenant top-up records.

- **Authentication:** Required
- **Roles:** `TENANT`
- **HTTP Method:** `GET`
- **Path:** `/api/users/vault/topups/?limit=25&cursor=...`

##### Response `200 OK`

```json
{
  "results": [
    {
      "id": "TOPUP_UUID",
      "amount": "150000.00",
      "currency": "NGN",
      "status": "SUCCEEDED",
      "reference": "TU-1A2B3C4D9E0F",
      "authorization_url": "https://checkout.paystack.com/abc123",
      "access_code": "abc123",
      "provider_reference": "TU-1A2B3C4D9E0F",
      "failure_reason": "",
      "created_at": "2026-08-30T12:00:00Z",
      "completed_at": "2026-08-30T12:04:00Z"
    }
  ],
  "next_cursor": null,
  "has_more": false
}
```

#### `GET /vault/withdrawals/`
Returns paginated withdrawal requests.

- **Authentication:** Required
- **Roles:** `OWNER`, `TENANT`
- **HTTP Method:** `GET`
- **Path:** `/api/users/vault/withdrawals/?limit=25&cursor=...`

#### `POST /vault/withdrawals/`
Requests a withdrawal from the authenticated user's vault to their verified payout account.

- **Authentication:** Required
- **Roles:** `OWNER`, `TENANT`
- **HTTP Method:** `POST`
- **Path:** `/api/users/vault/withdrawals/`
- **Content-Type:** `application/json`

##### Request Body

```json
{
  "amount": "100000.00",
  "vault_pin": "1234"
}
```

##### Response `201 Created`

```json
{
  "id": "WITHDRAWAL_UUID",
  "amount": "100000.00",
  "currency": "NGN",
  "status": "PENDING_REVIEW",
  "bank_name_snapshot": "Stanbic IBTC Bank",
  "account_number": "******6034",
  "account_name_snapshot": "AKINTAN AYOMIDE AKINDAMOLA",
  "provider": "",
  "provider_reference": "",
  "failure_reason": "",
  "requested_at": "2026-08-24T17:10:00Z",
  "processed_at": null,
  "updated_at": "2026-08-24T17:10:00Z"
}
```

Withdrawal behavior depends on backend configuration:

- If `AUTO_PROCESS_WITHDRAWALS=false`, the withdrawal is saved as `PENDING_REVIEW`.
- If `AUTO_PROCESS_WITHDRAWALS=true`, the backend immediately asks Paystack to start the transfer. The withdrawal may return `PENDING_TRANSFER` or `PAID`.
- If Paystack rejects the transfer before accepting it, the withdrawal is rolled back and the vault balance stays available.
- Paystack transfer webhooks later move withdrawals to `PAID` or `FAILED`; failed/reversed transfers return the held amount to the vault.

##### Common Errors

```json
{
  "code": "PAYOUT_ACCOUNT_REQUIRED",
  "detail": "Add a bank account before withdrawing.",
  "payout_account_required_for": "WITHDRAWAL"
}
```

```json
{
  "code": "INSUFFICIENT_VAULT_BALANCE",
  "detail": "Withdrawal amount is higher than your available vault balance.",
  "field": "amount"
}
```

```json
{
  "code": "PROVIDER_UNAVAILABLE",
  "detail": "Paystack could not be reached."
}
```

---

### 5.29 Get Payment Receipt

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

### Current Roles In Code

The backend currently supports:
- `OWNER`
- `TENANT`
- `ARTISAN`

For now, artisan accounts are separate accounts. A landlord or tenant upgrading the same account into an artisan account is deferred for a later account-role upgrade.

### Staging Smoke Test Before Flutter Handoff

Before telling Flutter that staging is ready, the backend team should run the smoke test with valid Paystack-resolvable payout details supplied through environment variables:

```powershell
$env:STAGING_PAYOUT_BANK_NAME='<BANK NAME>'
$env:STAGING_PAYOUT_ACCOUNT_NUMBER='<10 DIGIT ACCOUNT NUMBER>'
.\venv\Scripts\python.exe scripts\staging_smoke_test.py
Remove-Item Env:\STAGING_PAYOUT_BANK_NAME
Remove-Item Env:\STAGING_PAYOUT_ACCOUNT_NUMBER
```

This verifies the main mobile API flow and catches staging-only issues such as database connectivity, missing migrations, or HTML `500` pages.

Latest staging result on 2026-08-25:

- `/health/` passed.
- `/health/db/` passed.
- Property creation now requires at least 2 listing photos. The local smoke helper has been updated to send repeated `photos` fields for this contract.
- Agreement bucket fields and filters are live on staging. The staged smoke reached and passed agreement create/list/signing bucket checks before the Paystack payout step.
- Approved-relationship messaging endpoints are live on staging. The staged smoke passed pending-application blocking, conversation creation, duplicate conversation reuse, message retry idempotency, unread/read state, and conversation reporting before the Paystack payout step.
- Landlord broadcast endpoints are live on staging. The staged smoke passed broadcast creation, tenant notification delivery, landlord history, notification read-count update, and notification reporting before the Paystack payout step.
- Full smoke previously passed after the vault deployment.
- The latest repeat smoke reached payout account resolution and was blocked by Paystack test-mode's daily live-bank-resolve quota: Paystack returned `429` after the daily limit of 3 resolves. This is an external sandbox quota, not a backend regression.

Current Block 8/9 smoke coverage includes:
- Register/login
- Consent before verification
- Mock verification and verification status polling
- Dashboard gate before verification
- Property, unit, batch unit, and tenant assignment
- Tenant marketplace browse/apply and landlord application list
- Agreement creation, tenant signing, landlord execution without payout setup, dashboard/profile bucket filters, approved-relationship messaging, landlord broadcasts, and payout verification through the resolve-confirm flow
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

Units with an active short-let listing are also excluded from the yearly rental marketplace. If the short-let listing is inactive, the unit can appear for yearly rent again.

#### `GET /tenant/marketplace/`

Lists properties with available units for tenants.

Optional filters: `city`, `state`, `min_rent`, `max_rent`, `bedrooms`, `bathrooms`.

```text
GET /api/users/tenant/marketplace/?city=Lagos&max_rent=300000&bedrooms=2
```

Current-location search:

```text
GET /api/users/tenant/marketplace/?latitude=6.4450&longitude=3.4720
```

Optional radius:

```text
GET /api/users/tenant/marketplace/?latitude=6.4450&longitude=3.4720&radius_km=10
```

If Flutter sends coordinates, the backend uses those instead of typed `location`, sorts matching properties by nearest first, and adds `distance_km` to each property when the property has a map pin. If `radius_km` is not sent, the backend uses 10km. Older properties without coordinates can still appear after pinned nearby properties with `distance_km: null`.

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
    "distance_km": 2.41,
    "available_units": [
      {
        "id": "UNIT_UUID",
        "unit_number": "A1",
        "bedrooms": 2,
        "bathrooms": 2,
        "rent_amount": "300000.00",
        "photo_count": 0,
        "needs_photos": true,
        "created_at": "2026-08-18T09:00:00Z"
      }
    ]
  }
]
```

#### `POST /landlord/tenancies/import/`

Landlord imports existing tenants in batches, for example when they already have tenants before moving the property into Landa OS.

- **Authentication:** Landlord/owner only, verified users only.
- **Maximum batch size:** 50 tenancies per request.
- **Important:** This does not create old Paystack payments, vault movements, receipts, or fake escrow records. It only records the tenant's current agreement and how far rent has already been paid outside Landa OS.

Request:

```json
{
  "tenancies": [
    {
      "unit": "UNIT_UUID",
      "tenant": "tenant@example.com",
      "rent_amount": "450000.00",
      "start_date": "2026-01-01",
      "end_date": "2026-12-31",
      "rent_plan": "QUARTERLY",
      "is_existing_tenancy": true,
      "rent_paid_until": "2026-09-30",
      "rules": "Existing tenant imported into Landa OS."
    }
  ]
}
```

`tenant` can be an existing tenant email, phone number, or tenant UUID. If the email does not belong to an account yet, the backend creates a placeholder tenant and sends an invite email. Phone-only imports are not allowed for unknown tenants because there is nowhere to send the invite.

Response uses `207 Multi-Status` because each row can succeed or fail independently:

```json
{
  "results": [
    {
      "unit": "UNIT_UUID",
      "status": "CREATED",
      "tenant_status": "INVITED",
      "agreement": {
        "id": "AGREEMENT_UUID",
        "is_existing_tenancy": true,
        "rent_paid_until": "2026-09-30",
        "status": "PENDING"
      }
    },
    {
      "unit": "OTHER_UNIT_UUID",
      "status": "FAILED",
      "error": "Unit already has an active tenant."
    }
  ]
}
```

Flutter should show a row-by-row result screen after import. Successful invited tenants can later complete signup from the invitation link. The signup call uses the normal registration endpoint with:

```json
{
  "email": "tenant@example.com",
  "password": "Strongpass123!",
  "phone": "08000000000",
  "role": "TENANT",
  "invitation_token": "TOKEN_FROM_INVITE_LINK"
}
```

Imported active tenancies still require both tenant and landlord signatures inside Landa OS. Expired imported tenancies are saved as historical `EXPIRED` agreements.

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

### Conversations And Messaging

Messaging is available when the rental application is `PENDING` or `APPROVED`, or when an active agreement exists. `REJECTED` and `CANCELLED` applications cannot open chat.

Rules:

- Both landlord and tenant can start the conversation once eligible.
- Tenants can start a pending-application conversation using either `application` or `unit`.
- Landlords should start a pending-application conversation using `application`.
- One conversation exists per tenant/unit. Repeating start-chat returns the existing conversation.
- Messages are plain text only.
- Flutter should use polling for now.
- `client_message_id` prevents duplicate messages when the app retries after a network issue.

#### `GET /conversations/`

Returns the authenticated user's conversations.

Optional query params: `status=OPEN` or `status=CLOSED`.

#### `POST /conversations/`

Start or fetch a conversation.

Tenant may send one of:

```json
{ "unit": "UNIT_UUID" }
```

```json
{ "application": "APPLICATION_UUID" }
```

```json
{ "agreement": "AGREEMENT_UUID" }
```

Landlord should send `application` or `agreement`, because a unit can have multiple applicants.

Response `201 Created`, or `200 OK` if the conversation already exists:

```json
{
  "id": "CONVERSATION_UUID",
  "status": "OPEN",
  "context_type": "APPLICATION",
  "context_id": "APPLICATION_UUID",
  "property": { "id": "PROPERTY_UUID", "name": "Sunset House" },
  "unit": { "id": "UNIT_UUID", "unit_number": "A1" },
  "counterparty": {
    "id": "USER_UUID",
    "full_name": "Ada Okafor",
    "role": "TENANT",
    "verification_status": "VERIFIED"
  },
  "last_message": null,
  "unread_count": 0,
  "last_message_at": null,
  "last_message_preview": "",
  "created_at": "2026-08-25T09:00:00Z"
}
```

Common errors:

```json
{
  "code": "NO_RELATIONSHIP",
  "detail": "Messaging is available only while an application is pending or approved."
}
```

```json
{
  "code": "TENANT_NOT_IDENTIFIED",
  "detail": "Choose which approved tenant you want to message."
}
```

#### `GET /conversations/{conversation_id}/messages/`

Returns paginated messages:

```json
{
  "results": [
    {
      "id": "MESSAGE_UUID",
      "conversation": "CONVERSATION_UUID",
      "body": "Good afternoon, I am ready for the next step.",
      "sender_role": "TENANT",
      "sender_name": "Ada Okafor",
      "is_system": false,
      "client_message_id": "CLIENT_GENERATED_ID",
      "read_at": null,
      "created_at": "2026-08-25T09:05:00Z"
    }
  ],
  "next_cursor": null,
  "has_more": false,
  "latest_message_id": "MESSAGE_UUID"
}
```

#### `POST /conversations/{conversation_id}/messages/`

```json
{
  "body": "Good afternoon, I am ready for the next step.",
  "client_message_id": "CLIENT_GENERATED_ID"
}
```

The receiver gets a `MESSAGE_RECEIVED` notification.

#### `POST /conversations/{conversation_id}/read/`

Marks counterparty messages as read.

```json
{ "unread_count": 0 }
```

#### `GET /conversations/unread-count/`

```json
{
  "unread_count": 3,
  "conversations_with_unread": 2
}
```

#### `POST /conversations/{conversation_id}/report/`

Creates a safety report for admin/support review.

```json
{
  "reason": "Testing report capture.",
  "message_id": "MESSAGE_UUID"
}
```

---

### Landlord Broadcasts

Broadcasts are one-way landlord announcements delivered as tenant notifications. They are not chat messages.

Rules:

- Only verified landlords can send broadcasts.
- Recipients must be actual tenants with `EXECUTED` or legacy `ACTIVATED` agreements.
- Applicants and pending agreements do not receive broadcasts.
- Audience can be all tenants, tenants in one property, or tenants in selected units.
- Title max: 80 characters.
- Body max: 1000 characters.
- A landlord can send up to 5 broadcasts per day.
- Tenants can report a broadcast notification.

#### `POST /landlord/broadcasts/`

Create and deliver a broadcast.

```json
{
  "audience": "PROPERTY",
  "property": "PROPERTY_UUID",
  "title": "Water supply maintenance",
  "body": "The borehole pump will be serviced on Saturday between 9am and 2pm."
}
```

For all current tenants:

```json
{
  "audience": "ALL_TENANTS",
  "title": "Gate access update",
  "body": "The gate access code will change tonight."
}
```

For selected units:

```json
{
  "audience": "UNITS",
  "units": ["UNIT_UUID"],
  "title": "Inspection notice",
  "body": "Maintenance inspection is scheduled for Saturday."
}
```

Response `201 Created`:

```json
{
  "id": "BROADCAST_UUID",
  "audience": "PROPERTY",
  "property": { "id": "PROPERTY_UUID", "name": "Sunset House" },
  "units": [],
  "title": "Water supply maintenance",
  "body": "The borehole pump will be serviced on Saturday between 9am and 2pm.",
  "recipient_count": 12,
  "read_count": 0,
  "created_at": "2026-08-25T09:00:00Z"
}
```

Common errors:

```json
{
  "code": "NO_RECIPIENTS",
  "detail": "You don't have any tenants to send this to yet."
}
```

```json
{
  "code": "BROADCAST_LIMIT_REACHED",
  "detail": "You've sent 5 broadcasts today. Try again tomorrow."
}
```

```json
{
  "code": "PROPERTY_NOT_OWNED",
  "detail": "You can only message tenants in your own properties."
}
```

#### `GET /landlord/broadcasts/`

Returns landlord broadcast history:

```json
{
  "results": [
    {
      "id": "BROADCAST_UUID",
      "audience": "ALL_TENANTS",
      "property": null,
      "units": [],
      "title": "Gate access update",
      "body": "The gate access code will change tonight.",
      "recipient_count": 12,
      "read_count": 7,
      "created_at": "2026-08-25T09:00:00Z"
    }
  ],
  "next_cursor": null,
  "has_more": false
}
```

#### `GET /landlord/broadcasts/{broadcast_id}/`

Adds recipient delivery details:

```json
{
  "id": "BROADCAST_UUID",
  "recipient_count": 1,
  "read_count": 1,
  "recipients": [
    {
      "tenant_name": "Ada Okafor",
      "unit_number": "A1",
      "read_at": "2026-08-25T09:05:00Z"
    }
  ]
}
```

#### Broadcast Notification Shape

Tenants receive a normal notification:

```json
{
  "id": "NOTIFICATION_UUID",
  "notification_type": "LANDLORD_BROADCAST",
  "title": "Gate access update",
  "message": "The gate access code will change tonight.",
  "actor_name": "owner@example.com",
  "data": {
    "broadcast_id": "BROADCAST_UUID",
    "property_id": "PROPERTY_UUID",
    "property_name": "Sunset House",
    "unit_id": "UNIT_UUID",
    "unit_number": "A1"
  },
  "is_read": false,
  "created_at": "2026-08-25T09:00:00Z"
}
```

When Flutter marks the notification read, the broadcast `read_count` updates.

#### Rent Reminder Notifications

The backend can now send tenant rent reminders through the existing notification list. There is no new Flutter endpoint for this first release.

Notification types:

- `RENT_DUE_SOON`
- `RENT_DUE`
- `RENT_OVERDUE`

Example:

```json
{
  "id": "NOTIFICATION_UUID",
  "notification_type": "RENT_DUE_SOON",
  "title": "Rent due in 3 months",
  "message": "Here is where you are on your rent schedule. 472500.00 is due on 2027-08-31 for A1.",
  "data": {
    "agreement_id": "AGREEMENT_UUID",
    "unit_id": "UNIT_UUID",
    "due_date": "2027-08-31",
    "amount_due": "472500.00",
    "days_until_due": 90
  },
  "is_read": false,
  "created_at": "2026-08-30T09:00:00Z"
}
```

Deep link format:

```text
landa://agreements/{agreement_id}/rent
```

Recommended Flutter behavior:

- Show these notifications in the normal notification list.
- Open the agreement rent/payment screen when the user taps the reminder.
- Treat positive `days_until_due` as upcoming, `0` as due today, and negative values as overdue.
- Add a notification preferences toggle for optional early rent reminder emails.

#### Notification Preferences

`GET /api/users/notification-preferences/`

```json
{
  "early_rent_reminder_emails_enabled": true
}
```

`PATCH /api/users/notification-preferences/`

```json
{
  "early_rent_reminder_emails_enabled": false
}
```

This setting only controls the optional 180, 90, and 30-day rent reminder emails. The backend still sends in-app reminders, 7-day emails, due-today emails, and overdue emails.

Backend naming cleanup note:

- Public Flutter paths did not change.
- Keep using `/api/users/vault/` and `/api/users/payout-account/`.
- Internal backend names were cleaned up from landlord-only wording to neutral user-owned vault/payout naming.

#### `POST /notifications/{notification_id}/report/`

Tenant reports a notification, usually a broadcast:

```json
{
  "reason": "This announcement is inaccurate."
}
```

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
- `Conversation`
- `ConversationMessage`
- `LandlordBroadcast`
- `ShortLetListing`
- `ShortLetBooking`
- `ShortLetPayment`

Each model should support nullable timestamps and unknown enum values gracefully.

---

## Short Let API

Short Let V1 lets landlords list units for daily bookings and lets verified tenants request, get approval, and pay from vault or Paystack.

### 2026-09-03 Stays v7 Update

The backend now supports the Flutter Stays v7 contract:

- `available_from` and `available_to` are optional and may be sent as `null`.
- `null` means no date limit. Both fields as `null` means the listing is open for future bookings unless blocked by existing bookings or `blocked_dates`.
- Sending `null` is how Flutter clears an old booking window.
- Short-let listings accept and return `caution_fee`.
- Short-let bookings return `caution_fee`, `caution_fee_refunded_at`, `has_review`, and `conversation_id`.
- `total_amount` includes the caution fee, while `caution_fee` remains separate for UI breakdowns.
- Caution fees refund to the tenant vault during normal short-let escrow release when the stay is not disputed.
- Units now return `photo_urls`, `cover_photo_url`, and `video_url`.
- Short-let media should be read from the nested `unit`, not the parent `property`.
- Unit tour video is optional on the backend, even if Flutter requires it before saving the current unit flow.
- Short-let reviews and paid short-let conversations are now available.

### Unit Media

All unit media endpoints require an authenticated verified `OWNER`. The unit must belong to a property owned by that user.

```text
GET    /api/users/units/{unit_id}/photos/
POST   /api/users/units/{unit_id}/photos/
DELETE /api/users/units/{unit_id}/photos/{photo_id}/
POST   /api/users/units/{unit_id}/video/
DELETE /api/users/units/{unit_id}/video/
```

Photo upload uses `multipart/form-data` with repeated `photos` fields. Limits: 12 photos per unit, 5MB each, JPG/JPEG/PNG/WEBP.

Video upload uses `multipart/form-data` with a `video` field. Limits: one video per unit, 50MB, MP4/MOV. Uploading a new video replaces the previous one.

Photo response:

```json
[
  {
    "id": "PHOTO_UUID",
    "image_url": "https://example.supabase.co/storage/v1/object/public/...",
    "created_at": "2026-09-03T10:00:00Z"
  }
]
```

Video response:

```json
{
  "video_url": "https://example.supabase.co/storage/v1/object/public/..."
}
```

### Short-Let Reviews

Reviews are currently implemented for `SHORT_LET` only.

```text
GET  /api/users/reviews/?subject_type=SHORT_LET&subject_id={listing_id}&limit=20
POST /api/users/reviews/
GET  /api/users/reviews/summary/?subject_type=SHORT_LET&subject_id={listing_id}
POST /api/users/reviews/{review_id}/respond/
```

Create review request:

```json
{
  "subject_type": "SHORT_LET",
  "subject_id": "LISTING_UUID",
  "transaction_id": "BOOKING_UUID",
  "rating": 5,
  "comment": "Exactly as described."
}
```

Rules:

- Only the tenant who booked the stay can review it.
- The stay must be paid and checkout must be in the past.
- One review is allowed per tenant per booking.
- Public review payloads expose `author_name`, never author email.
- Duplicate review returns `409`.
- Trying to review someone else's booking returns `403`.

Summary response:

```json
{
  "average_rating": 4.8,
  "review_count": 12,
  "distribution": { "5": 9, "4": 2, "3": 1, "2": 0, "1": 0 }
}
```

`average_rating` is `null` when there are no reviews.

### Short-Let Conversations

`POST /api/users/conversations/` now accepts:

```json
{
  "short_let_booking": "BOOKING_UUID"
}
```

Rules:

- The caller must be the booking tenant or host.
- The booking must already be paid. In this backend, successful short-let payment usually moves the booking to `IN_ESCROW`, then later `RELEASED`.
- Unpaid bookings return `403` with `You can message the host once your stay is paid for.`
- Repeating the same request returns the existing conversation.
- Conversation payloads use `context_type: SHORT_LET` and `context_id: BOOKING_UUID`.
- Short-let messages create `SHORT_LET_MESSAGE_RECEIVED` notifications.
- Short-let conversations close when the stay is released.

### Landlord Listing

`POST /api/users/landlord/short-lets/`

```json
{
  "unit": "UNIT_UUID",
  "nightly_price": "50000.00",
  "minimum_nights": 2,
  "maximum_guests": 3,
  "caution_fee": "25000.00",
  "available_from": "2026-09-01",
  "available_to": "2026-12-31",
  "blocked_dates": ["2026-10-10"],
  "house_rules": "No parties.",
  "check_in_notes": "Code shared after payment.",
  "is_active": true
}
```

Response includes `rental_plan: "DAILY"`.

Duplicate listing response:

```json
{
  "code": "LISTING_EXISTS",
  "detail": "This unit is already listed for short stays.",
  "listing_id": "LISTING_UUID"
}
```

This response uses `409 Conflict`. Flutter should branch on `code` and may use `listing_id` to open the existing listing.

`available_from` and `available_to` may be `null`:

```json
{
  "available_from": null,
  "available_to": null
}
```

This means the listing has no fixed booking window.

`GET /api/users/landlord/short-lets/` lists landlord short-let listings.

### Tenant Browsing And Booking

`GET /api/users/tenant/short-lets/` lists active short-let listings for verified tenants.

`POST /api/users/tenant/short-let-bookings/`

```json
{
  "listing": "LISTING_UUID",
  "check_in": "2026-10-01",
  "check_out": "2026-10-03",
  "guest_count": 2,
  "message": "Weekend stay."
}
```

The backend checks minimum nights, maximum guests, listing availability, blocked dates, and already-approved booking conflicts.

Date clash response:

```json
{
  "code": "DATES_UNAVAILABLE",
  "detail": "Those nights are already booked.",
  "check_in": ["These dates are already booked."],
  "conflicting_dates": ["2026-10-02"]
}
```

This response uses `409 Conflict`. The same response shape is used if a landlord tries to approve a short-let booking whose dates now clash with an already approved or paid booking.

### Landlord Booking Decisions

`GET /api/users/landlord/short-let-bookings/`

`POST /api/users/landlord/short-let-bookings/{booking_id}/approve/`

Approval gives the tenant 24 hours to pay.

`POST /api/users/landlord/short-let-bookings/{booking_id}/reject/`

### Tenant Cancellation

`POST /api/users/tenant/short-let-bookings/{booking_id}/cancel/`

Only pending or approved unpaid bookings can be cancelled by the tenant in V1. Paid booking cancellation is support/admin handled for now.

### Tenant Payment

`POST /api/users/tenant/short-let-bookings/{booking_id}/pay/`

Headers:

```text
Idempotency-Key: unique-client-key
```

Paystack/card:

```json
{
  "source": "CARD"
}
```

Vault:

```json
{
  "source": "VAULT",
  "vault_pin": "1234"
}
```

`POST /api/users/tenant/short-let-payments/{payment_id}/verify/`

```json
{
  "reference": "SL-REFERENCE"
}
```

Short-let payments move into escrow after payment. The planned release time is checkout date.

`POST /api/users/tenant/short-let-payments/{payment_id}/dispute/`

```json
{
  "reason": "The unit was not accessible."
}
```

Tenants can dispute while the payment is still in escrow and before the release time. The booking and payment become `DISPUTED`, and automatic release will skip them.

Short-let escrow release now happens through the backend command:

```text
python manage.py release_ready_shortlet_escrows
```

This should run daily in production. It releases eligible non-disputed short-let escrow payments 24 hours after checkout. The landlord vault receives the stay amount. If the booking included a caution fee, the tenant vault receives the refundable caution fee and the booking gets `caution_fee_refunded_at`.

Production scheduler:

```text
python manage.py run_daily_jobs
```

Render is configured to run this once daily at `07:00 UTC`, which is `08:00 AM Africa/Lagos`. It runs rent reminders, normal rent escrow release, and short-let escrow release. Flutter does not need to call this command.

Staging smoke coverage now includes:

- Notification preferences `GET/PATCH`.
- Landlord Short Let listing creation.
- Tenant Short Let listing browse.
- Tenant Short Let booking request.
- Landlord Short Let approval.
- Tenant Short Let card payment initialization with `Idempotency-Key`.

New notification types:

- `SHORT_LET_BOOKING_REQUESTED`
- `SHORT_LET_BOOKING_APPROVED`
- `SHORT_LET_BOOKING_REJECTED`
- `SHORT_LET_BOOKING_CANCELLED`
- `SHORT_LET_PAYMENT_INITIATED`
- `SHORT_LET_PAYMENT_RECORDED`

---

## 7B. Artisan Fix V1

**2026-09-06 simplification:** the in-app job request/accept/quote/pay/vault-release workflow described below has been **removed entirely**. Landa no longer brokers artisan jobs or artisan payments. Artisan Fix is now a directory: a landlord or tenant can find a verified artisan's full details, including phone number, and contact them directly outside the app. All endpoints, models, and notification types under "Tenant Creates Artisan Request", "Artisan Request Dashboard", and "Tenant Cancels, Pays, And Confirms Completion" below **no longer exist** — remove any Flutter screens built against them.

Simple product rules (current):

- Artisans register as separate `ARTISAN` accounts for now.
- Artisans use the same consent and NIN verification flow as landlords and tenants.
- Registration itself creates the artisan profile immediately; there is no separate approval step.
- Tenants and landlords can only browse verified, active artisans.
- Both tenant and landlord browse views show the artisan's full name, category, location, bio, experience, verification status, recently-online status, **and phone number** — the phone number is no longer hidden or gated behind any workflow.
- Landlord can recommend one artisan per category for each unit.
- Both the tenant Fix page and a new landlord artisan browse page can show all artisans in a category and highlight the landlord-recommended artisan for a given unit.
- Contact between a landlord/tenant and an artisan happens outside the app (call/message using the phone number shown), not through Landa.

### Artisan Registration

`POST /api/users/register/`

```json
{
  "email": "artisan@example.com",
  "password": "Strongpass123!",
  "phone": "08000000000",
  "role": "ARTISAN",
  "category": "PLUMBING",
  "location": "Lekki Phase 1",
  "bio": "Reliable plumber for home repairs.",
  "years_of_experience": 5
}
```

Allowed category values:

- `PLUMBING`
- `ELECTRICIAN`
- `GENERATOR_REPAIR`
- `CLEANER`

After registration, call the same consent and NIN verification endpoints:

- `POST /api/users/consents/`
- `POST /api/users/verify/`
- `GET /api/users/verify/status/`

### Artisan Profile

`GET /api/users/artisans/me/`

For the logged-in artisan. Returns their artisan profile and phone number.

`PATCH /api/users/artisans/me/`

```json
{
  "category": "PLUMBING",
  "location": "Yaba",
  "bio": "Available for plumbing repairs.",
  "years_of_experience": 6
}
```

Category change review is deferred. For now, category can be updated directly.

### Categories

`GET /api/users/artisans/categories/`

Returns:

```json
[
  {"value": "PLUMBING", "label": "Plumbing"},
  {"value": "ELECTRICIAN", "label": "Electrician"},
  {"value": "GENERATOR_REPAIR", "label": "Generator Repair"},
  {"value": "CLEANER", "label": "Cleaner"}
]
```

### Landlord Unit Recommendations

`GET /api/users/units/{unit_id}/artisan-recommendations/`

Returns the recommended artisans already selected for that unit.

`POST /api/users/units/{unit_id}/artisan-recommendations/`

```json
{
  "category": "PLUMBING",
  "artisan_id": "artisan-profile-uuid"
}
```

This creates or replaces the recommendation for that category. Only the unit landlord can do this. The selected artisan must be verified, active, and in the same category.

`DELETE /api/users/units/{unit_id}/artisan-recommendations/`

```json
{
  "category": "PLUMBING"
}
```

### Tenant Fix Artisan List

`GET /api/users/tenant/fix/artisans/?category=PLUMBING&unit={unit_id}`

Returns verified, active artisans in that category. If `unit` belongs to the tenant, each artisan includes `is_recommended`.

Important response fields:

```json
{
  "id": "artisan-profile-uuid",
  "full_name": "Ada Fixer",
  "email": "artisan@example.com",
  "phone": "08000000000",
  "category": "PLUMBING",
  "category_label": "Plumbing",
  "location": "Lekki Phase 1",
  "bio": "Reliable plumber.",
  "years_of_experience": 5,
  "verification_status": "VERIFIED",
  "is_active": true,
  "recently_online": true,
  "is_recommended": true
}
```

`phone` is now always populated (no more `null`) — show a call/message action directly from this list. `recently_online` means the artisan used the app within the last hour.

### Landlord Artisan Browse List

`GET /api/users/landlord/artisans/?category=PLUMBING&unit={unit_id}`

New endpoint, added 2026-09-06. Same shape and fields as the Tenant Fix Artisan List above, but for landlords. Use this to build the artisan picker for the unit-recommendation flow — previously there was no way for a landlord to browse or search artisans at all; recommending one required already knowing its internal ID. `unit` is optional and, when it belongs to the landlord, marks the landlord's existing per-category recommendation with `is_recommended`.

Staging smoke coverage now includes artisan registration, NIN verification, landlord recommendation, tenant Fix browsing (phone visible), and landlord artisan browsing (phone visible).

---

## 7C. Tenant Search And Location Suggestions

The backend now supports simple location search for Marketplace, Stays, and Fix. Marketplace and Stays can also use the tenant's current location when Flutter sends coordinates.

### Marketplace Search

`GET /api/users/tenant/marketplace/?location=Lekki`

Flutter can also use:

- `search=Lekki`
- `q=Lekki`

The backend checks property name, address, city, and state. Existing filters still work:

```text
GET /api/users/tenant/marketplace/?location=Lekki&bedrooms=2&min_rent=200000&max_rent=800000
```

Current location:

```text
GET /api/users/tenant/marketplace/?latitude=6.4450&longitude=3.4720
```

Optional radius:

```text
GET /api/users/tenant/marketplace/?latitude=6.4450&longitude=3.4720&radius_km=10
```

If Flutter sends coordinates, the backend ignores typed `location`, uses 10km by default, puts nearest pinned properties first, and includes `distance_km` when available.

### Stays Search

Typed search:

```text
GET /api/users/tenant/short-lets/?location=Lekki
```

Current location:

```text
GET /api/users/tenant/short-lets/?latitude=6.4450&longitude=3.4720
```

Optional radius:

```text
GET /api/users/tenant/short-lets/?latitude=6.4450&longitude=3.4720&radius_km=10
```

If Flutter does not send `radius_km`, the backend uses 10km. When coordinates are sent, results can include:

```json
{
  "distance_km": 2.41
}
```

Flutter should ask for location permission on the Stays page. If the user allows it, send latitude/longitude. If the user denies it, show the search bar and use typed location search.

Date availability search:

```text
GET /api/users/tenant/short-lets/?location=Lekki&check_in=2026-10-10&check_out=2026-10-12
```

When `check_in` and `check_out` are sent, the backend still returns matching stays even if they are unavailable for that period. Flutter should display the listing but show the availability state:

```json
{
  "is_available_for_period": false,
  "unavailable_reason": "One or more selected dates are blocked."
}
```

Possible availability values:

- `true`: available for the selected dates.
- `false`: not available for the selected dates; show `unavailable_reason`.
- `null`: no dates were sent, so no date availability check was done.

Do not hide unavailable searched stays on Flutter. Show them with the reason so the tenant understands why they cannot book that period.

### Fix Search

```text
GET /api/users/tenant/fix/artisans/?category=PLUMBING&unit={unit_id}&location=Lekki
```

Flutter can also use `search` or `q` instead of `location`.

The backend filters artisans by typed location for now. If `unit` belongs to the tenant, landlord-recommended artisans still come first.

For current GPS location on Fix, Flutter should ask permission once. In this backend version, Flutter should either:

- use a readable area name in the `location` search box, or
- show landlord recommendations and category results without GPS sorting.

True distance sorting for artisans is deferred until artisan profiles store map coordinates.

Staging smoke coverage now includes:

- Marketplace typed location search.
- Marketplace current-location search with `distance_km`.
- Stays typed location search.
- Stays current-location search with `distance_km`.
- Fix artisan location search with landlord recommendation first.

---

## 8. Endpoint Checklist

| Feature | Method | Path | Auth | Roles |
| :--- | :--- | :--- | :--- | :--- |
| Register | `POST` | `/api/users/register/` | No | Public |
| Login | `POST` | `/api/users/login/` | No | Public |
| Request password reset | `POST` | `/api/users/password/reset/request/` | No | Public |
| Confirm password reset | `POST` | `/api/users/password/reset/confirm/` | No | Public |
| Refresh token | `POST` | `/api/users/token/refresh/` | No | Public |
| Profile | `GET` | `/api/users/profile/` | Yes | `OWNER`, `TENANT`, `ARTISAN` |
| Accept consent | `POST` | `/api/users/consents/` | Yes | `OWNER`, `TENANT`, `ARTISAN` |
| List consents | `GET` | `/api/users/consents/` | Yes | `OWNER`, `TENANT`, `ARTISAN` |
| Verify identity | `POST` | `/api/users/verify/` | Yes | `OWNER`, `TENANT`, `ARTISAN` |
| Check verification status | `GET` | `/api/users/verify/status/` | Yes | `OWNER`, `TENANT`, `ARTISAN` |
| Smile ID webhook | `POST` | `/api/users/webhooks/smile-id/` | No | Provider callback |
| List payout banks | `GET` | `/api/users/banks/` | Yes | `OWNER`, `TENANT`, `ARTISAN` |
| Resolve payout account | `POST` | `/api/users/payout-account/resolve/` | Yes + verified | `OWNER`, `TENANT`, `ARTISAN` |
| Get payout account | `GET` | `/api/users/payout-account/` | Yes + verified | `OWNER`, `TENANT`, `ARTISAN` |
| Create payout account | `POST` | `/api/users/payout-account/` | Yes + verified | `OWNER`, `TENANT`, `ARTISAN` |
| Update payout account | `PATCH` | `/api/users/payout-account/` | Yes + verified | `OWNER`, `TENANT`, `ARTISAN` |
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
| Change unit rent | `PATCH` | `/api/users/units/{unit_id}/` | Yes + verified | `OWNER` |
| List unit artisan recommendations | `GET` | `/api/users/units/{unit_id}/artisan-recommendations/` | Yes + verified | `OWNER` |
| Create/update unit artisan recommendation | `POST` | `/api/users/units/{unit_id}/artisan-recommendations/` | Yes + verified | `OWNER` |
| Remove unit artisan recommendation | `DELETE` | `/api/users/units/{unit_id}/artisan-recommendations/` | Yes + verified | `OWNER` |
| Tenant assigned unit | `GET` | `/api/users/tenant/assigned-unit/` | Yes + verified | `TENANT` |
| Artisan categories | `GET` | `/api/users/artisans/categories/` | Yes + verified | `OWNER`, `TENANT`, `ARTISAN` |
| Artisan profile | `GET/PATCH` | `/api/users/artisans/me/` | Yes | `ARTISAN` |
| Tenant Fix artisan list | `GET` | `/api/users/tenant/fix/artisans/` | Yes + verified | `TENANT` |
| Landlord artisan browse list | `GET` | `/api/users/landlord/artisans/` | Yes + verified | `OWNER` |
| Tenant marketplace | `GET` | `/api/users/tenant/marketplace/` | Yes + verified | `TENANT` |
| Tenant applications | `GET` | `/api/users/tenant/applications/` | Yes + verified | `TENANT` |
| Apply for unit | `POST` | `/api/users/tenant/applications/` | Yes + verified | `TENANT` |
| Landlord applications | `GET` | `/api/users/landlord/applications/` | Yes + verified | `OWNER` |
| Approve application | `POST` | `/api/users/landlord/applications/{application_id}/approve/` | Yes + verified | `OWNER` |
| Reject application | `POST` | `/api/users/landlord/applications/{application_id}/reject/` | Yes + verified | `OWNER` |
| List agreements | `GET` | `/api/users/agreements/` | Yes + verified | `OWNER`, `TENANT` |
| Create agreement | `POST` | `/api/users/agreements/` | Yes + verified | `OWNER` |
| Sign agreement | `POST` | `/api/users/agreements/{agreement_id}/sign/` | Yes + verified | `OWNER`, `TENANT` |
| List conversations | `GET` | `/api/users/conversations/` | Yes + verified | `OWNER`, `TENANT` |
| Start conversation | `POST` | `/api/users/conversations/` | Yes + verified | `OWNER`, `TENANT` |
| Conversation detail | `GET` | `/api/users/conversations/{conversation_id}/` | Yes + verified | `OWNER`, `TENANT` |
| List messages | `GET` | `/api/users/conversations/{conversation_id}/messages/` | Yes + verified | `OWNER`, `TENANT` |
| Send message | `POST` | `/api/users/conversations/{conversation_id}/messages/` | Yes + verified | `OWNER`, `TENANT` |
| Mark conversation read | `POST` | `/api/users/conversations/{conversation_id}/read/` | Yes + verified | `OWNER`, `TENANT` |
| Conversation unread count | `GET` | `/api/users/conversations/unread-count/` | Yes + verified | `OWNER`, `TENANT` |
| Report conversation | `POST` | `/api/users/conversations/{conversation_id}/report/` | Yes + verified | `OWNER`, `TENANT` |
| Send broadcast | `POST` | `/api/users/landlord/broadcasts/` | Yes + verified | `OWNER` |
| List broadcasts | `GET` | `/api/users/landlord/broadcasts/` | Yes + verified | `OWNER` |
| Broadcast detail | `GET` | `/api/users/landlord/broadcasts/{broadcast_id}/` | Yes + verified | `OWNER` |
| Realtime WebSockets | `WS` | `/ws/realtime/` | Yes | `OWNER`, `TENANT` |
| List landlord short lets | `GET` | `/api/users/landlord/short-lets/` | Yes + verified | `OWNER` |
| Create short let listing | `POST` | `/api/users/landlord/short-lets/` | Yes + verified | `OWNER` |
| Edit short let listing | `PUT/PATCH` | `/api/users/landlord/short-lets/{listing_id}/` | Yes + verified | `OWNER` |
| List landlord short-let bookings | `GET` | `/api/users/landlord/short-let-bookings/` | Yes + verified | `OWNER` |
| Approve short-let booking | `POST` | `/api/users/landlord/short-let-bookings/{booking_id}/approve/` | Yes + verified | `OWNER` |
| Reject short-let booking | `POST` | `/api/users/landlord/short-let-bookings/{booking_id}/reject/` | Yes + verified | `OWNER` |
| Browse tenant short lets | `GET` | `/api/users/tenant/short-lets/` | Yes + verified | `TENANT` |
| List/create tenant short-let bookings | `GET/POST` | `/api/users/tenant/short-let-bookings/` | Yes + verified | `TENANT` |
| Cancel short-let booking | `POST` | `/api/users/tenant/short-let-bookings/{booking_id}/cancel/` | Yes + verified | `TENANT` |
| Pay short-let booking | `POST` | `/api/users/tenant/short-let-bookings/{booking_id}/pay/` | Yes + verified | `TENANT` |
| Verify short-let payment | `POST` | `/api/users/tenant/short-let-payments/{payment_id}/verify/` | Yes + verified | `TENANT` |
| Run daily jobs webhook | `POST` | `/api/users/webhooks/cron/run-daily-jobs/` | Secret header | `SYSTEM` |
| Dispute short-let payment | `POST` | `/api/users/tenant/short-let-payments/{payment_id}/dispute/` | Yes + verified | `TENANT` |
| List payments | `GET` | `/api/users/payments/` | Yes + verified | `OWNER`, `TENANT` |
| Initialize payment | `POST` | `/api/users/payments/` | Yes + verified | `TENANT` |
| Get payment receipt | `GET` | `/api/users/payments/{payment_id}/` | Yes + verified | `OWNER`, `TENANT` |
| Verify payment | `POST` | `/api/users/payments/{payment_id}/verify/` | Yes + verified | `TENANT` |
| Get escrow status | `GET` | `/api/users/payments/{payment_id}/escrow/` | Yes + verified | `OWNER`, `TENANT` |
| Dispute escrow | `POST` | `/api/users/payments/{payment_id}/dispute/` | Yes + verified | `TENANT` |
| Release escrow | `POST` | `/api/users/payments/{payment_id}/release/` | Yes + verified | `OWNER` |
| Get vault | `GET` | `/api/users/vault/` | Yes + verified | `OWNER`, `TENANT`, `ARTISAN` |
| List vault top-ups | `GET` | `/api/users/vault/topups/` | Yes + verified | `TENANT` |
| Start vault top-up | `POST` | `/api/users/vault/topups/` | Yes + verified | `TENANT` |
| Verify vault top-up | `POST` | `/api/users/vault/topups/{topup_id}/verify/` | Yes + verified | `TENANT` |
| List vault transactions | `GET` | `/api/users/vault/transactions/` | Yes + verified | `OWNER`, `TENANT`, `ARTISAN` |
| List withdrawals | `GET` | `/api/users/vault/withdrawals/` | Yes + verified | `OWNER`, `TENANT`, `ARTISAN` |
| Request withdrawal | `POST` | `/api/users/vault/withdrawals/` | Yes + verified | `OWNER`, `TENANT`, `ARTISAN` |
| Paystack webhook | `POST` | `/api/users/webhooks/paystack/` | No | Provider callback |
| List notifications | `GET` | `/api/users/notifications/` | Yes + verified | `OWNER`, `TENANT`, `ARTISAN` |
| Notification preferences | `GET/PATCH` | `/api/users/notification-preferences/` | Yes + verified | `OWNER`, `TENANT`, `ARTISAN` |
| Mark notification read | `PATCH` | `/api/users/notifications/{notification_id}/read/` | Yes + verified | `OWNER`, `TENANT`, `ARTISAN` |
| Report notification | `POST` | `/api/users/notifications/{notification_id}/report/` | Yes + verified | `OWNER`, `TENANT`, `ARTISAN` |
| Export user data | `GET` | `/api/users/data-export/` | Yes | `OWNER`, `TENANT`, `ARTISAN` |
| Create deletion request | `POST` | `/api/users/deletion-requests/` | Yes | `OWNER`, `TENANT`, `ARTISAN` |
| List deletion requests | `GET` | `/api/users/deletion-requests/` | Yes | `OWNER`, `TENANT`, `ARTISAN` |

---

## 9. Short Let Payout, Cancellation, And Dispute Update - 2026-09-03

This section supersedes older Short Let wording that said the whole short-let payment is released to the landlord after checkout.

### Booking And Money Meaning

Short-let booking `status` describes the booking journey only.

Current booking statuses Flutter should handle:

- `REQUESTED`
- `APPROVED`
- `PAID`
- `CHECKED_IN`
- `CHECKED_OUT`
- `COMPLETED`
- `DISPUTED`
- `REJECTED`
- `CANCELLED`
- `EXPIRED`

Money states are separate fields.

Host payout statuses:

- `NOT_FUNDED` -> `Not paid yet`
- `HELD` -> `Scheduled for payout`
- `RELEASED` -> `Paid to host`
- `BLOCKED` -> `Payout paused`
- `REFUNDED` -> `Refunded to tenant`

Short-let payment success now means:

- Guest payment succeeded.
- Booking becomes `PAID`.
- Host payout is held until check-in release time.
- Default release time is 12:00 PM Africa/Lagos on the check-in date.
- Caution fee is held separately.
- Platform fee is not refundable for guest-initiated cancellation.

### Important Response Fields

Booking/payment responses can include:

```json
{
  "status": "PAID",
  "amount": "100000.00",
  "platform_fee": "5000.00",
  "host_payout": "95000.00",
  "landlord_payout": "95000.00",
  "caution_fee": "25000.00",
  "total_amount": "130000.00",
  "host_payout_status": "HELD",
  "host_payout_status_label": "Scheduled for payout",
  "host_payout_status_description": "Payment received. Host payout will be released on the check-in date if no issue is reported.",
  "host_payout_release_at": "2026-10-01T11:00:00Z",
  "host_paid_at": null,
  "landlord_payout_status": "HELD",
  "landlord_paid_at": null,
  "caution_fee_escrow_status": "IN_ESCROW",
  "caution_fee_release_ready_at": "2026-10-04T23:00:00Z",
  "caution_fee_refunded_at": null,
  "cancellation_policy": "FLEXIBLE",
  "cancellation_policy_summary": "Free cancellation until 24 hours before check-in."
}
```

Flutter should prefer `host_*` fields. `landlord_*` fields are temporary compatibility aliases.

### Cancellation Endpoints

Tenant preview:

```text
GET /api/users/tenant/short-let-bookings/{booking_id}/cancel-preview/
```

Tenant cancel:

```text
POST /api/users/tenant/short-let-bookings/{booking_id}/cancel/
```

Optional request:

```json
{
  "reason": "Plans changed."
}
```

Host cancel:

```text
POST /api/users/landlord/short-let-bookings/{booking_id}/cancel/
```

Required request:

```json
{
  "reason": "Emergency maintenance."
}
```

Rules:

- Tenant cancellation before payment has no penalty.
- Paid tenant cancellation before check-in follows the listing policy.
- Platform fee is never refunded for tenant cancellation.
- Caution fee is fully refunded before check-in.
- Host cancellation before check-in refunds the guest's full paid amount.
- After check-in, cancellation should go through support/dispute instead of normal cancellation.

### Tenant Payout-Blocking Dispute

Open dispute before host payout:

```text
POST /api/users/tenant/short-let-payments/{payment_id}/dispute/
```

Request:

```json
{
  "reason": "The property was not accessible."
}
```

This sets the host payout to `BLOCKED`.

Tenant marks issue resolved:

```text
POST /api/users/tenant/short-let-payments/{payment_id}/resolve-dispute/
```

Optional request:

```json
{
  "note": "I got access now."
}
```

If the payout release time has already passed, the backend can release the host payout immediately after the guest marks the issue resolved.

### Host Caution-Fee Claim

Host opens claim after checkout:

```text
POST /api/users/landlord/short-let-bookings/{booking_id}/caution-claims/
```

Request:

```json
{
  "claimed_amount": "10000.00",
  "reason": "Broken lamp.",
  "evidence": ["https://example.com/photo.jpg"]
}
```

If `claimed_amount` is omitted, the backend treats the claim as a claim against the full caution fee.

Tenant responds:

```text
POST /api/users/tenant/short-let-caution-claims/{claim_id}/respond/
```

Accept:

```json
{
  "response": "ACCEPT",
  "note": "Agreed."
}
```

Reject:

```json
{
  "response": "REJECT",
  "note": "I disagree."
}
```

Counter:

```json
{
  "response": "COUNTER",
  "counter_amount": "5000.00",
  "note": "I agree to a smaller cleaning fee."
}
```

Rules:

- Host can claim only after checkout and within the 24-hour claim window.
- If host claims only part of the caution fee, the unclaimed part returns to the guest wallet immediately.
- If guest accepts, the claimed amount goes to host wallet.
- If guest rejects or counters, the claim stays paused for support/admin review.

### New Notification Type

Flutter should handle:

```text
SHORT_LET_CAUTION_FEE_CLAIM
```

Use it for host claim opened and tenant claim response events.

---

## 10. Rental And Short Let Search Update - 2026-09-03

Tenants can filter rentals and short lets by location, price range, or both.

Flutter should use these query parameters for both rentals and short lets:

```text
location
min_price
max_price
```

The backend still accepts older rental aliases:

```text
min_rent
max_rent
```

### Rental Search

Rental Marketplace filters by unit rent amount.

Location only:

```text
GET /api/users/tenant/marketplace/?location=Lekki
```

Price only:

```text
GET /api/users/tenant/marketplace/?min_price=200000&max_price=800000
```

Location and price together:

```text
GET /api/users/tenant/marketplace/?location=Lekki&min_price=200000&max_price=800000
```

Minimum only:

```text
GET /api/users/tenant/marketplace/?min_price=300000
```

Maximum only:

```text
GET /api/users/tenant/marketplace/?max_price=800000
```

### Short Let Search

Short lets filter by nightly price when no dates are selected.

```text
GET /api/users/tenant/short-lets/?location=Lekki&min_price=30000&max_price=100000
```

When `check_in` and `check_out` are selected, short lets filter by total stay price for the selected dates.

```text
GET /api/users/tenant/short-lets/?location=Lekki&check_in=2026-10-10&check_out=2026-10-12&min_price=60000&max_price=200000
```

### Flutter UI Guidance

Use numeric-only fields, price sliders, steppers, or min/max selectors so users cannot easily enter wrong values.

Recommended UI rules:

- Do not allow text in price fields.
- Do not allow negative prices.
- Do not allow max price to be lower than min price.
- For rentals, label the filter as rent amount.
- For short lets without dates, label the filter as nightly price.
- For short lets with dates, label the filter as total stay price.

The backend still validates these values because API requests can come from outside the app.

Invalid examples return `400 Bad Request`:

```text
?min_price=cheap
?max_price=-1
?min_price=900000&max_price=100000
```

---

## Realtime WebSocket API (`wss://<host>/ws/realtime/`)

### Connection & Authentication

- Handshake URL: `wss://<host>/ws/realtime/`
- Send header: `Authorization: Bearer <access_token>` in the initial HTTP upgrade handshake.
- Each WebSocket connection is associated with the authenticated user for its lifetime.

### Event Types Delivered

1. `message.created`: New chat message sent in a conversation. Payload contains `{ "conversation_id": "<uuid>", "message": { ... } }`.
2. `notification.created`: New system notification. Payload contains `{ "notification": { ... } }`.
3. `conversation.updated`: Conversation metadata or unread count changed. Payload contains `{ "conversation": { ... } }`.
4. `unread.counts`: Overall unread count refresh signal sent immediately after connection acceptance and reconnects.

### Heartbeat & Reconnection Fallback

- The server sends `{"type": "ping"}` every 25 seconds. Flutter clients should reply with `{"type": "pong"}`.
- If the WebSocket connection drops, Flutter should immediately fallback to REST message polling using `since_message_id` and retry socket connection.

---

## Message Polling Incremental Cursors (`GET /api/users/conversations/{conversation_id}/messages/`)

Query Parameters:

- `since_message_id` (UUID, optional): Returns messages created after the specified message ID.
- `before_message_id` (UUID, optional): Returns messages created before the specified message ID (useful for pagination/scroll up).

Example request:

```text
GET /api/users/conversations/{conversation_id}/messages/?since_message_id=8a7b6c5d-4e3f-2a1b-0c9d-8e7f6a5b4c3d
```

---

## Short-Let Bedroom Filter & Room Counts

### Search Query Filters (`GET /api/users/tenant/short-lets/`)

- `min_bedrooms` (Integer, optional): Filters listings by minimum room count (`bedrooms >= min_bedrooms`).

Example:

```text
GET /api/users/tenant/short-lets/?location=Lekki&min_bedrooms=2&min_price=30000&max_price=100000
```

### Listing Fields Exposed

Short-let listing responses include `bedrooms`, `bathrooms`, and `description`:

```json
{
  "id": "123e4567-e89b-12d3-a456-426614174000",
  "name": "Luxury Oceanview Apartment",
  "description": "Spacious 2-bedroom short-let with fast Wi-Fi and 24/7 power.",
  "bedrooms": 2,
  "bathrooms": 2,
  "nightly_rate": "45000.00"
}
```

---

## Daily Jobs Webhook (`POST /api/users/webhooks/cron/run-daily-jobs/`)

- Method: `POST`
- Header: `X-Cron-Secret: <CRON_SECRET>`
- Executes daily background tasks (rent reminders, escrow releases, host payouts).
- Returns `200 OK` on success or `403 Forbidden` if missing/invalid secret.

---

## 11. Rent & Price Change Update - 2026-09-06

**Status:** Implemented, tested (249/249 backend tests passing), and pushed to GitHub for Render redeploy.

### `PATCH /units/{unit_id}/` - Change A Unit's Rent

The endpoint requested in `backend_change_spec_v12.md` §1. Lets a landlord reprice a unit without deleting and recreating it.

- **Authentication:** Required
- **Roles:** `OWNER`, and only the owner of the property the unit belongs to (a landlord patching someone else's unit gets `403`, not `404`)
- **HTTP Method:** `PATCH`
- **Path:** `/api/users/units/{unit_id}/`

##### Request Body

```json
{ "rent_amount": "3000000.00" }
```

`rent_amount` only — this endpoint deliberately rejects any other field. It is a **year's** rent as a decimal string, same convention as unit creation.

##### Response `200 OK`

Full unit object, same shape as `GET /properties/{id}/units/` returns (includes `photo_urls`, `cover_photo_url`, `video_url`).

##### Response `400 Bad Request`

```json
{ "errors": { "rent_amount": ["This field is required."] } }
```

Returned for a blank, zero, or negative rent.

##### Until this ships on a given deployment

A deployment without this route answers `404`; one with the route but the wrong verb answers `405`. Both should be treated by Flutter as "the update didn't happen, nothing was lost" rather than shown as raw errors.

### Short-Let Re-Pricing Is Confirmed Safe, With One New Behavior

Per `backend_change_spec_v12.md` §2:

- A **paid** short-let booking keeps the price it was paid at — confirmed, no change needed.
- An **approved, awaiting-payment** booking keeps the price it was approved at — confirmed, no change needed.
- A booking still **pending a decision** now **reprices to the listing's current nightly price at the moment it is approved**, and the guest receives a `SHORT_LET_BOOKING_REPRICED` notification explaining the new total. This is new behavior as of today — previously a pending booking's price was frozen at request time and never updated.

Nothing new to call from Flutter for this — it's server-side behavior on the existing approve endpoint (`POST /landlord/short-let-bookings/{booking_id}/approve/`). Just be aware the approved booking's `nightly_price`/`total_amount` in the response may differ from what the guest originally saw if the landlord changed the price in between.

### Rental Applications Now Freeze The Rent At Apply-Time

Per `backend_change_spec_v12.md` §3. Previously, if a landlord raised a unit's rent between a tenant applying and the landlord approving, the tenant could be handed a signed agreement at the higher, never-agreed-to price. Fixed: the rent is now snapshotted onto the application the moment a tenant applies (`applied_rent_amount`, internal field), and approving an application drafts the agreement from that snapshot, not the unit's live rent. No API shape change — `POST /tenant/applications/` and `POST /landlord/applications/{id}/approve/` are called exactly as before; the fix is purely in what number ends up on the resulting agreement.

An **executed** (signed) agreement was already fully protected — any attempt to change its rent is rejected outright.

### Price-Drop Notifications

New notification types. The app already renders unknown notification types with sensible defaults, so these need no app release to start showing up.

- `UNIT_PRICE_CHANGED` — sent to every tenant with a **pending or approved** application on a unit when its rent drops. Never sent on a price rise.
- `SHORT_LET_PRICE_CHANGED` — sent to every guest with a **live (requested/pending/approved)** booking on a short-let listing when its nightly price drops. Never sent on a price rise.
- `SHORT_LET_BOOKING_REPRICED` — sent specifically when a pending booking's price changes as part of approval (see above).

### Price-Change Audit Trail (Backend-Only, No API)

Every unit rent change and every short-let nightly-price change is now logged internally (who changed it, old price, new price, when) for dispute resolution. This is not exposed through any endpoint and needs no Flutter work — mentioned here only so the capability is documented somewhere.

### Verification

- [x] `python manage.py check`
- [x] Full backend test suite: 249/249 passing.
- [x] Staging smoke test updated and covers: unit rent PATCH (permission + validation), rent-drop notification to a pending applicant, application rent-freeze through approval, short-let price-drop notification, pending-booking reprice-on-approval with notice, and an already-approved booking's price staying untouched by a later reprice.

---

## 12. Verification Outcome Notifications Update - 2026-09-06

**Status:** Implemented, tested, and pushed to GitHub for Render redeploy.

Previously, when a user's identity verification finished (via the Smile ID webhook), the backend updated `verification_status` silently — nothing told the user it had happened. Flutter had to keep polling `GET /verify/status/` to find out.

Now, the moment verification finishes, the user gets a notification:

- **Success** — notification type `VERIFICATION_SUCCEEDED`. For an `ARTISAN` role specifically, the message reads: *"You're verified! Your Landa artisan registration is complete and landlords and tenants can now find and contact you."* For other roles: *"Your identity verification was successful."*
- **Failure** — notification type `VERIFICATION_FAILED`, with the failure reason inline if one is available.

This is the hook for the "registered successfully" screen requested for artisans: show that screen only once this notification (or a `GET /verify/status/` check showing `VERIFIED`) arrives — not immediately after `POST /register/` returns `201`. Before verification completes, the app should make clear that registration is not yet finished.

### Verification

- [x] `python manage.py check`
- [x] Full backend test suite: 249/249 passing.
- [x] Staging smoke test updated: checks a `VERIFICATION_SUCCEEDED` notification for both a regular role and specifically for an artisan (with the artisan-specific wording), and a `VERIFICATION_FAILED` notification for a rejected verification attempt.

---

## 13. Bug Fixes - 2026-09-06

Two pre-existing bugs, unrelated to the features above, were found while running the full test suite and fixed:

- **`PATCH /units/{unit_id}/assign/` was crashing with a `500 Internal Server Error`** on every call. Root cause was a missing import in the backend file (the serializer it needed existed but was never imported) — not anything Flutter was doing wrong. Fixed.
- **The rent-due-date shown for annual-plan agreements was wrong**, which silently broke the whole rent-reminder notification system (`RENT_DUE_SOON`, `RENT_DUE`, `RENT_OVERDUE` almost never fired, because they only trigger on exact day-count matches and the date was off). Fixed. No API shape changed — `rent_schedule.next_due_date` on `GET /agreements/` now returns the correct date, and rent reminders now actually send.




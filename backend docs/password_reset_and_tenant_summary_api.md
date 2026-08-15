# Password reset and tenant-summary API contract

This document covers the mobile password-reset screen and the tenant name shown in a landlord's unit details page.

## Password reset

### Request reset instructions

`POST /api/users/password/reset/request/`

This endpoint is public and accepts JSON:

```json
{ "email": "owner@example.com" }
```

Always return `202 Accepted` with the same body whether or not the address belongs to an account. This prevents email enumeration.

```json
{
  "message": "If an account exists for this email address, password-reset instructions have been sent."
}
```

Generate a single-use, short-lived token (maximum 30 minutes), invalidate older unconsumed tokens for the user, and email a universal/app link containing that token. Rate limit by IP and email address. Never return the token in the API response or log it.

### Set a new password

`POST /api/users/password/reset/confirm/`

```json
{
  "token": "opaque-single-use-token",
  "new_password": "A-long-unique-password"
}
```

Return `204 No Content` on success. A missing, expired, or used token returns `400` with a generic `INVALID_OR_EXPIRED_TOKEN` error. On success, revoke all existing refresh tokens/sessions for the account and send a security notification email.

## Tenant summary on a unit

`GET /api/users/properties/{property_id}/units/` and any property-detail endpoint must return an authorized landlord/manager a tenant object, not only the tenant UUID.

```json
{
  "id": "unit_01J...",
  "unit_number": "A1",
  "bedrooms": 2,
  "bathrooms": 2,
  "rent_amount": "450000.00",
  "is_occupied": true,
  "tenant": {
    "id": "91164db4-f048-4353-8e67-063c2520b052",
    "full_name": "Ada Okafor",
    "email": "ada@example.com",
    "phone_number": "+2348012345678"
  }
}
```

The Flutter app supports this nested `tenant` shape and treats a legacy UUID string in `tenant` as an identifier, not a display name. As a transitional alternative, the API may return `tenant_name`, `tenant_email`, and `tenant_phone_number` at the unit level.

Only the property owner and explicitly authorized managers may receive the tenant name, email, or phone number. Other roles must receive `tenant: null` (or omit it), even if `is_occupied` is true.

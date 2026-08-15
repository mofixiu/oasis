# Landa OS — Backend API Resolution & Feature Fix Guide

This document is for the **Backend Developer**. It details API issue resolutions, backend fixes, and serializer adjustments needed for staging API endpoints at `https://landa-os-staging.onrender.com/api/users/`.

---

## 1. Issue Overview

While authentication (`POST /login/`) and payments (`GET /payments/`) return `200 OK`, **core endpoints require serializer and database adjustments**:

| Endpoint | HTTP Method | Status | Required Adjustment |
| :--- | :--- | :--- | :--- |
| `/api/users/agreements/` | `POST` | ❌ **400 Bad Request** | `tenant` field expects UUID string instead of Email/Phone |
| `/api/users/verify/` | `POST` | ✅ **Resolved** | Requires `Content-Type: image/jpeg` header on selfie file |

---

## 2. Fix Required for `POST /api/users/agreements/` (Tenant Email / Phone Lookup)

### The Issue
When a landlord invites a tenant in the mobile app, the landlord enters the tenant's **Email** (`mofiyinebo@gmail.com`) or **Phone Number** (`07054315799`).

However, Django's `TenancyAgreementSerializer` defines `"tenant"` as a strict `PrimaryKeyRelatedField` expecting a **UUID string**. When the app posts `{"tenant": "mofiyinebo@gmail.com"}`, Django rejects it with:
```json
{
  "tenant": ["“mofiyinebo@gmail.com” is not a valid UUID."]
}
```

### 🛠️ Required Backend Fix
In your `TenancyAgreementSerializer` (or `AgreementsView.create()`), update the `tenant` field handling so it resolves the user by **Email**, **Phone**, OR **UUID**:

```python
# In serializers.py or views.py for POST /agreements/
from django.db.models import Q
from rest_framework import serializers
from django.contrib.auth import get_user_model

User = get_user_model()

class TenancyAgreementSerializer(serializers.ModelSerializer):
    # Accept string for tenant input (email, phone, or UUID)
    tenant = serializers.CharField(write_only=True)

    def validate_tenant(self, value):
        user = User.objects.filter(
            Q(email__iexact=value) | Q(phone=value) | Q(id=value if is_valid_uuid(value) else None),
            role='TENANT'
        ).first()

        if not user:
            raise serializers.ValidationError("No tenant account found matching this email or phone number.")
        return user

    def create(self, validated_data):
        # validated_data['tenant'] is now the resolved User model instance
        return TenancyAgreement.objects.create(**validated_data)
```

---

## 3. Live Request & Log Reproduction

### Failing `POST /api/users/agreements/`
```bash
curl -X POST "https://landa-os-staging.onrender.com/api/users/agreements/" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer <LANDLORD_ACCESS_TOKEN>" \
  -d '{
    "unit": "44e8786b-53fd-4991-ad33-810e62310012",
    "tenant": "mofiyinebo@gmail.com",
    "rent_amount": "450000.00",
    "start_date": "2026-08-08",
    "end_date": "2027-08-08",
    "rules": "No noise after 10 PM."
  }'
```
**Staging Response:**
```json
{
  "tenant": ["“mofiyinebo@gmail.com” is not a valid UUID."]
}
```

Once `validate_tenant` is updated to look up tenants by Email, Phone, or UUID, `POST /agreements/` will return `201 Created`!

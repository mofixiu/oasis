# Backend API Documentation & Integration Specification (Sample Guide)

> **Instructions for Backend Engineers:**  
> Use this document as the gold-standard template when writing API documentation for our backend endpoints. The Flutter team will use your documentation to build data models, repositories, and UI integrations. Please adhere strictly to the conventions and endpoint structure below.

---

## 1. General API Conventions

### Base URLs
- **Staging:** `https://staging-api.oasisapp.com/api/v1`
- **Production:** `https://api.oasisapp.com/api/v1`

### Request & Response Format
- All request and response bodies MUST be formatted in standard JSON (`application/json`).
- All JSON property names MUST use **`snake_case`** (e.g., `user_id`, `created_at`, `payment_status`).
- Character Encoding: **UTF-8**.

### HTTP Headers
Every request from Flutter will include standard headers:

| Header Name | Value / Format | Requirement | Description |
| :--- | :--- | :--- | :--- |
| `Content-Type` | `application/json` | Required for POST/PUT/PATCH | Specifies payload format |
| `Accept` | `application/json` | Required | Specifies expected response format |
| `Authorization` | `Bearer <JWT_ACCESS_TOKEN>` | Required for Protected Endpoints | User authentication token |
| `X-App-Version` | `1.0.0` | Optional | Flutter app version tracking |
| `X-Device-Platform` | `android` \| `ios` \| `web` | Optional | Client platform identification |

---

## 2. Data Handling & Type Standards

To prevent integration bugs and serialization errors in Flutter (Dart type system), backend APIs must conform to the following data handling rules:

### Data Type Mapping Table
| Data Concept | JSON Format | Example Value | Notes for Backend |
| :--- | :--- | :--- | :--- |
| **Identifiers** | `String` (UUID v4) | `"e3b0c442-98fc-11ee-b9d1-0242ac120002"` | Do not use auto-incrementing integers for public IDs. |
| **Dates & Timestamps** | `String` (ISO 8601) | `"2026-08-05T13:30:00Z"` | Always send UTC format with timezone offsets. |
| **Monetary Amounts** | `Integer` (Subunits) | `25000000` (Kobo/Cents) | Express NGN/USD in smallest currency subunit (e.g. 250,000 NGN = 25,000,000 Kobo) to eliminate floating-point rounding errors. |
| **Booleans** | `Boolean` | `true` or `false` | Do not send `1`/`0` or `"true"`/`"false"` strings. |
| **Enums / Statuses** | `String` (UPPERCASE) | `"PENDING"`, `"PAID"`, `"FAILED"` | Use explicit uppercase snake_case string literals. |
| **Nullable Fields** | Key present with `null` or omitted | `"middle_name": null` | If a field is null, explicitly pass `null` or document if it's omitted. |
| **Lists / Arrays** | Array `[]` | `["photo1.jpg", "photo2.jpg"]` | If empty, send an empty array `[]`. Never send `null` when a list is expected. |

---

## 3. Standard Response Formats

### 3.1 Success Response Wrapper
All `2xx` HTTP responses must follow a unified structure:

```json
{
  "status": "success",
  "message": "Property listed successfully.",
  "data": {
    // Primary response object or array goes here
  },
  "meta": {
    // Optional metadata (e.g., pagination)
  }
}
```

### 3.2 Standard Paginated Response
For list endpoints (`GET` requests returning collections):

```json
{
  "status": "success",
  "message": "Listings retrieved successfully",
  "data": [
    {
      "id": "prop_991823",
      "title": "Luxury 3-Bed Apartment",
      "rent_amount": 350000000,
      "currency": "NGN"
    }
  ],
  "meta": {
    "pagination": {
      "current_page": 1,
      "per_page": 20,
      "total_items": 142,
      "total_pages": 8,
      "has_more": true
    }
  }
}
```

### 3.3 Unified Error Response Format
When any error occurs (`4xx` or `5xx`), the backend MUST return this structured payload so Flutter can catch and display errors gracefully:

```json
{
  "status": "error",
  "code": "VALIDATION_ERROR",
  "message": "The request payload contains invalid fields.",
  "errors": {
    "email": ["The email address format is invalid."],
    "rent_amount": ["Rent amount must be greater than 0."]
  },
  "timestamp": "2026-08-05T13:30:00Z"
}
```

#### Standard Error Codes:
- `UNAUTHENTICATED`: Missing or invalid JWT token (HTTP 401).
- `PERMISSION_DENIED`: User lacks required role/access (HTTP 403).
- `RESOURCE_NOT_FOUND`: Specified resource does not exist (HTTP 404).
- `VALIDATION_ERROR`: Request payload validation failed (HTTP 422).
- `PAYMENT_REQUIRED`: Insufficient balance or escrow requirement (HTTP 402).
- `SERVER_ERROR`: Internal system crash or database error (HTTP 500).

---

## 4. How Flutter Connects & Consumes These Endpoints

Here is how the Flutter architecture (MVCS + Provider + Repository Pattern) consumes backend documentation:

```
[Flutter UI Widget] ──(User Action)──> [Controller / Provider]
                                            │
                                  (Calls Interface Method)
                                            ▼
                                   [IPropertyRepository]
                                            │
                                  (Implements REST Calls)
                                            ▼
                                    [ApiHttpClient]
                                            │ (JSON / HTTP)
                                            ▼
                                   [Backend REST API]
```

### Flutter Developer Implementation Requirements:
1. **Dart Model Mapping:** Each endpoint response `data` JSON object maps 1:1 to a Dart Data Model using `fromJson` factory constructors.
2. **Repository Abstraction:** Endpoints are wrapped behind abstract interfaces (e.g. `IAuthRepository`, `IRentRepository`).
3. **HTTP Interceptor:** Flutter uses an `http`/`dio` client that automatically attaches the `Authorization: Bearer <token>` header to all requests.
4. **Token Expiration Handling:** If HTTP status is `401 (UNAUTHENTICATED)`, Flutter handles token refresh or redirects the user to the login screen.

---

## 5. Sample Endpoint Documentation Blueprints

> **Note for Backend Engineers:**  
> Use the exact Markdown structure shown below for documenting every endpoint in your backend service modules.

---

### Endpoint Blueprint 1: Authentication & User Verification

#### `POST /auth/login`
Authenticates a user with email and password, returning JWT access tokens and user profile details.

- **Authentication:** None (Public Endpoint)
- **HTTP Method:** `POST`
- **Path:** `/api/v1/auth/login`

##### Request Headers:
```http
Content-Type: application/json
Accept: application/json
```

##### Request Body:
```json
{
  "email": "chidi.okonkwo@example.com",
  "password": "SecurePassword123!"
}
```

##### Response `200 OK`:
```json
{
  "status": "success",
  "message": "Login successful",
  "data": {
    "access_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
    "refresh_token": "d9b23e81-7c4a-4b92-8012-3211516e9112",
    "token_type": "Bearer",
    "expires_in": 3600,
    "user": {
      "id": "usr_7712390a-412b-4e12-8812-99011a012389",
      "first_name": "Chidi",
      "last_name": "Okonkwo",
      "email": "chidi.okonkwo@example.com",
      "phone_number": "+2348012345678",
      "role": "TENANT",
      "is_kyc_verified": true,
      "created_at": "2026-01-15T09:00:00Z"
    }
  }
}
```

##### Response `401 Unauthorized` (Invalid Credentials):
```json
{
  "status": "error",
  "code": "INVALID_CREDENTIALS",
  "message": "Invalid email or password.",
  "errors": null,
  "timestamp": "2026-08-05T13:30:00Z"
}
```

---

### Endpoint Blueprint 2: Real Estate Listings (Paginated GET)

#### `GET /properties`
Retrieves a paginated list of verified property listings with optional search filters.

- **Authentication:** Optional / Public
- **HTTP Method:** `GET`
- **Path:** `/api/v1/properties`

##### Query Parameters:
| Parameter | Type | Required | Default | Description |
| :--- | :--- | :--- | :--- | :--- |
| `page` | `Integer` | No | `1` | Page number |
| `per_page` | `Integer` | No | `20` | Items per page (max: 50) |
| `city` | `String` | No | `null` | Filter by city (e.g. `"Lagos"`) |
| `state` | `String` | No | `null` | Filter by state (e.g. `"Lagos"`, `"Abuja"`) |
| `max_rent` | `Integer` | No | `null` | Maximum annual rent in Kobo |
| `property_type` | `String` | No | `null` | `"APARTMENT"`, `"HOUSE"`, `"COMMERCIAL"` |

##### Request Example:
```http
GET /api/v1/properties?city=Lagos&max_rent=500000000&page=1&per_page=10 HTTP/1.1
Host: api.oasisapp.com
Authorization: Bearer eyJhbGciOiJIUzI1Ni...
```

##### Response `200 OK`:
```json
{
  "status": "success",
  "message": "Properties fetched successfully",
  "data": [
    {
      "id": "prop_a1b2c3d4",
      "title": "Modern 2-Bedroom Serviced Apartment",
      "address": "15 Admiralty Way, Lekki Phase 1",
      "city": "Lagos",
      "state": "Lagos State",
      "annual_rent_kobo": 450000000,
      "service_charge_kobo": 50000000,
      "currency": "NGN",
      "bedrooms": 2,
      "bathrooms": 2,
      "is_verified": true,
      "primary_image_url": "https://cdn.oasisapp.com/properties/prop_a1b2c3d4/main.jpg",
      "landlord": {
        "id": "usr_99812",
        "full_name": "Adebayo Properties Ltd",
        "rating": 4.8
      },
      "created_at": "2026-07-20T11:20:00Z"
    }
  ],
  "meta": {
    "pagination": {
      "current_page": 1,
      "per_page": 10,
      "total_items": 45,
      "total_pages": 5,
      "has_more": true
    }
  }
}
```

---

### Endpoint Blueprint 3: Escrow Payment Initiation

#### `POST /payments/escrow/initiate`
Initializes a fraud-free escrow payment session for rent or security deposit via payment provider (e.g., Paystack/Flutterwave).

- **Authentication:** Required (`Bearer Token`)
- **HTTP Method:** `POST`
- **Path:** `/api/v1/payments/escrow/initiate`

##### Request Body:
```json
{
  "property_id": "prop_a1b2c3d4",
  "lease_agreement_id": "agr_887123",
  "amount_kobo": 450000000,
  "payment_purpose": "ANNUAL_RENT",
  "callback_url": "oasisapp://payments/callback"
}
```

##### Response `201 Created`:
```json
{
  "status": "success",
  "message": "Escrow payment session initialized",
  "data": {
    "escrow_transaction_id": "esc_99812371",
    "reference": "LNDA-ESC-20260805-9921",
    "amount_kobo": 450000000,
    "currency": "NGN",
    "payment_gateway_url": "https://checkout.paystack.com/39a102931bc",
    "status": "PENDING_PAYMENT",
    "escrow_hold_hours": 48,
    "expires_at": "2026-08-05T14:30:00Z"
  }
}
```

---

## 6. Blank Endpoint Template for Backend Developers

> Backend Engineers: Copy & paste this template block when documenting new endpoints for the team.

```markdown
### Endpoint Title

Short description of what this endpoint does.

- **Authentication:** [Required / Optional / Public]
- **HTTP Method:** [GET / POST / PUT / PATCH / DELETE]
- **Path:** `/api/v1/your-endpoint-path`

#### Headers
```http
Authorization: Bearer <TOKEN>
Content-Type: application/json
```

#### Query Parameters / Path Parameters
| Parameter | Type | Required | Description |
| :--- | :--- | :--- | :--- |
| `id` | `String` | Yes | Resource ID |

#### Request Body
```json
{
  "example_key": "example_value"
}
```

#### Response `200 OK`
```json
{
  "status": "success",
  "message": "Success message",
  "data": {}
}
```

#### Error Responses
- `400 Bad Request`: `INVALID_PAYLOAD`
- `401 Unauthorized`: `UNAUTHENTICATED`
- `404 Not Found`: `RESOURCE_NOT_FOUND`
```

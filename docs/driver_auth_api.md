# Authentication & Ambulance Management API

Google sign-in is shared by the **driver app**, the **user app** and the **hospital dashboard**. Every request names a `role` (`driver` | `user` | `hospital`); accounts are looked up per role by the email in the verified Google token.

---

## 1. Authentication Endpoints

### 1.1 `POST /auth/google`

Signs in with a Google OAuth 2.0 ID token (verified on the server using `google-auth`).

* **Access**: Public
* **Request Body**:
  ```json
  { "id_token": "<google_id_token_string>", "role": "driver" }
  ```
  `role` defaults to `driver`.
* **Success Response (200 OK) — existing account**:
  ```json
  {
    "registration_required": false,
    "role": "driver",
    "access_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
    "token_type": "bearer",
    "account": {
      "id": 1, "name": "Arun Kumar", "email": "driver1@example.com",
      "photo_url": "https://lh3.googleusercontent.com/...",
      "phone": "9876543210", "hospital_id": null
    }
  }
  ```
  `phone` is set for drivers and users, `hospital_id` for hospital accounts.
* **Success Response (200 OK) — first sign-in, no account yet**:
  ```json
  {
    "registration_required": true,
    "role": "driver",
    "registration_token": "eyJ...",
    "google_profile": { "email": "new@gmail.com", "name": "Asha Nair", "photo_url": null }
  }
  ```
  The app shows its registration screen (prefilled from `google_profile`) and then calls `POST /auth/register/{role}`. The registration token expires after 15 minutes and cannot be used to call any other endpoint.
* **Error Responses**:
  * `401 Unauthorized`: Google ID token is invalid, expired, or has unverified email.
  * `403 Forbidden`: the driver account has been deactivated (`is_active` is `false`).
  * `503 Service Unavailable`: `GOOGLE_CLIENT_ID` is not configured.

---

### 1.2 `POST /auth/register/driver` · `POST /auth/register/user`

Creates the account for a Google identity that got `registration_required`.

* **Request Body**:
  ```json
  { "registration_token": "eyJ...", "name": "Asha Nair", "phone": "+91 98765 43210" }
  ```
  The phone is normalised exactly as in `POST /users` (10 digits, `+91`/`0` prefix and spaces/dashes stripped).
* **Success Response (201 Created)**: same shape as the signed-in response of `/auth/google`.
* **Error Responses**: `401` bad/expired/wrong-role registration token · `409` account already exists, or the phone belongs to another Google account · `422` blank name or invalid phone.

A user created earlier through `POST /users` (phone only, no email) is adopted when someone registers with the same phone, so their incident history is kept.

### 1.3 `POST /auth/register/hospital`

Creates a hospital and the dashboard account that manages it, in one step.

* **Request Body**:
  ```json
  {
    "registration_token": "eyJ...",
    "hospital": { "name": "City Hospital", "location": { "lat": 9.939, "lng": 76.27 }, "departments": ["Trauma", "Cardiology"] }
  }
  ```
* **Success Response (201 Created)**: signed-in response with `account.hospital_id` set.

### 1.4 `GET /auth/me`

Returns the account behind the `Authorization: Bearer <JWT>` header (any role) — used to restore a saved session. `401` if the token is missing, invalid, expired or a registration token.

---

### 1.5 `POST /auth/dev-login` *(Development Only)*

Bypasses Google token exchange for local offline development.
**Disabled by default.** Only active when `ALLOW_DEV_LOGIN=true` is set in `.env`; otherwise it returns `404`.

* **Request Body**:
  ```json
  { "email": "driver1@example.com", "role": "driver", "name": "Optional display name" }
  ```
* **Success Response (200 OK)**: Same shape as `POST /auth/google` — an unknown email gets `registration_required`, so the registration screens can be tried without a Google account.

---

## 2. Driver Profile & Ambulances

### 2.1 `GET /drivers/me/ambulances`

Fetches all ambulances linked to the authenticated driver via the `ambulance_driver` junction table.

* **Access**: Protected (Requires `Authorization: Bearer <JWT>`)
* **Headers**:
  ```http
  Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
  ```
* **Success Response (200 OK)**:
  ```json
  [
    {
      "id": 1,
      "registration_number": "KL-01-AB-1234",
      "vehicle_type": "ALS",
      "is_available": true
    },
    {
      "id": 2,
      "registration_number": "KL-07-CD-5678",
      "vehicle_type": "BLS",
      "is_available": false
    }
  ]
  ```
* **Error Responses**:
  * `401 Unauthorized`: Missing, invalid, or expired JWT token, or a token issued for another role (a user or hospital token cannot call driver endpoints).

---

## 3. Database Schema Overview

```mermaid
erDiagram
    HOSPITALS ||--o{ HOSPITAL_ACCOUNTS : managed_by
    DRIVERS ||--o{ AMBULANCE_DRIVER : links
    AMBULANCES ||--o{ AMBULANCE_DRIVER : links
    AMBULANCES ||--o{ INCIDENTS : assigned_to

    HOSPITAL_ACCOUNTS {
        int id PK
        string email UK
        string name
        string photo_url
        int hospital_id FK
        timestamp created_at
    }

    DRIVERS {
        int id PK
        string name
        string email UK
        string phone
        string photo_url
        boolean is_active
        timestamp created_at
    }

    AMBULANCE_DRIVER {
        int driver_id PK,FK
        int ambulance_id PK,FK
        timestamp created_at
    }

    AMBULANCES {
        int id PK
        string registration_number UK
        string vehicle_type
        geography location
        boolean is_available
    }
```

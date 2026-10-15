# Driver Authentication & Ambulance Management API

This document describes the backend endpoints introduced for driver authentication, session management, and ambulance assignment.

---

## 1. Authentication Endpoints

### 1.1 `POST /auth/google`

Authenticates a driver using a Google OAuth 2.0 ID token (verified on the server using `google-auth`).

* **Access**: Public
* **Request Body**:
  ```json
  {
    "id_token": "<google_id_token_string>"
  }
  ```
* **Success Response (200 OK)**:
  ```json
  {
    "access_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
    "token_type": "bearer",
    "driver": {
      "id": 1,
      "name": "Arun Kumar",
      "email": "driver1@example.com",
      "photo_url": "https://lh3.googleusercontent.com/..."
    }
  }
  ```
* **Error Responses**:
  * `401 Unauthorized`: Google ID token is invalid, expired, or has unverified email.
    ```json
    { "detail": "Invalid or expired Google token." }
    ```
  * `403 Forbidden`: Google account email is not registered in the `drivers` database or `is_active` is `false`.
    ```json
    { "detail": "This Google account is not registered as a driver." }
    ```

---

### 1.2 `POST /auth/dev-login` *(Development Only)*

Bypasses Google token exchange for local offline development.
**Disabled by default.** Only active when `ALLOW_DEV_LOGIN=true` is set in `.env`.

* **Access**: Public (Dev environments only)
* **Request Body**:
  ```json
  {
    "email": "driver1@example.com"
  }
  ```
* **Success Response (200 OK)**: Same shape as `POST /auth/google`.
* **Error Responses**:
  * `403 Forbidden`: Feature disabled or driver email not found/inactive.

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
  * `401 Unauthorized`: Missing, invalid, or expired JWT token.

---

## 3. Database Schema Overview

```mermaid
erDiagram
    DRIVERS ||--o{ AMBULANCE_DRIVER : links
    AMBULANCES ||--o{ AMBULANCE_DRIVER : links
    AMBULANCES ||--o{ INCIDENTS : assigned_to

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

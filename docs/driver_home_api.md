# Driver Home & Ambulance Dispatch API

This document describes the driver-facing endpoints for online status toggling, live GPS sharing, incident polling, atomic incident acceptance, and candidate fan-out dispatch behavior.

All driver-facing endpoints require a valid Bearer JWT (`Authorization: Bearer <token>`) issued by `/auth/google` (or `/auth/dev-login`) for a driver account linked to the target ambulance in the `ambulance_driver` table. If the driver is not linked to that ambulance, the server returns `403 Forbidden`.

---

## 1. Endpoints

### 1.1 `PATCH /ambulances/{ambulance_id}/online`

Toggles the driver's active online/offline status and optionally sets the starting GPS location.

* **Access**: Authenticated Driver (linked to `ambulance_id`)
* **Request Body**:
  ```json
  {
    "is_online": true,
    "lat": 9.9312,
    "lng": 76.2673
  }
  ```
  `lat` and `lng` are optional (ignored when going offline).
* **Behavior**:
  * **Going Online (`is_online: true`)**:
    * Sets `ambulances.is_online = true`.
    * If `lat`/`lng` are provided, sets `ambulances.location` and `ambulances.location_updated_at = NOW()`.
    * **Backfill**: Automatically finds recent unassigned incidents (`assigned_ambulance_id IS NULL`, created within the last 30 minutes, within `CANDIDATE_RADIUS_KM` = 15 km) and creates `inci_ambu` candidate rows so the driver sees them immediately.
  * **Going Offline (`is_online: false`)**:
    * If the ambulance is currently holding an active incident (`assigned_ambulance_id == ambulance_id` with status in `hospital_assigned` or `ambulance_assigned`), the request is rejected with `409 Conflict`.
    * Otherwise, sets `ambulances.is_online = false`.
* **Success Response (200 OK)**:
  ```json
  {
    "id": 1,
    "registration_number": "KL-07-AE-1234",
    "vehicle_type": "ALS",
    "location": { "lat": 9.9312, "lng": 76.2673 },
    "is_available": true,
    "is_online": true,
    "location_updated_at": "2026-10-19T10:45:00Z"
  }
  ```
* **Error Responses**:
  * `401 Unauthorized`: Missing or expired JWT.
  * `403 Forbidden`: Authenticated driver is not linked to this ambulance.
  * `409 Conflict`: Cannot go offline while holding an active incident.

---

### 1.2 `PATCH /ambulances/{ambulance_id}/location`

Pushes live GPS coordinates from the driver's phone every 5–10 seconds while online.

* **Access**: Authenticated Driver (linked to `ambulance_id`)
* **Request Body**:
  ```json
  {
    "location": {
      "lat": 9.9314,
      "lng": 76.2678
    }
  }
  ```
* **Behavior**:
  * Updates `ambulances.location` and `ambulances.location_updated_at = NOW()`.
* **Success Response (200 OK)**:
  ```json
  {
    "id": 1,
    "registration_number": "KL-07-AE-1234",
    "vehicle_type": "ALS",
    "location": { "lat": 9.9314, "lng": 76.2678 },
    "is_available": true,
    "is_online": true,
    "location_updated_at": "2026-10-19T10:45:05Z"
  }
  ```

---

### 1.3 `GET /ambulances/{ambulance_id}/incidents`

Lists all incoming emergency incident requests dispatched to this ambulance.

* **Access**: Authenticated Driver (linked to `ambulance_id`)
* **Behavior**:
  * If the ambulance is currently offline (`is_online: false`), returns an empty list `[]`.
  * Returns unassigned incidents (`assigned_ambulance_id IS NULL` and `status != 'completed'`) that were requested to this ambulance via `inci_ambu`.
  * Ordered by severity: `critical` first, then `high`, `medium`, `low`, followed by newest incident first.
* **Success Response (200 OK)**:
  ```json
  [
    {
      "id": 42,
      "severity": "critical",
      "emergency_type": "Cardiac Arrest",
      "symptoms": ["chest pain", "loss of consciousness"],
      "victims": 1,
      "department_needed": "Cardiology",
      "transcript": "Caller reports 55 year old male collapsed with chest pain...",
      "location": { "lat": 9.9350, "lng": 76.2690 },
      "distance_km": 1.42,
      "created_at": "2026-10-19T10:44:30Z"
    }
  ]
  ```

---

### 1.4 `POST /ambulances/{ambulance_id}/incidents/{incident_id}/accept`

Claims an incident request for this ambulance.

* **Access**: Authenticated Driver (linked to `ambulance_id`)
* **Race Safety**:
  * Uses a row-level transaction lock (`SELECT ... FOR UPDATE`).
  * If another ambulance already claimed the case (`assigned_ambulance_id IS NOT NULL`), the transaction aborts and returns `409 Conflict`.
  * On success:
    * Sets `incidents.assigned_ambulance_id = ambulance_id`.
    * Sets `incidents.status = 'ambulance_assigned'`.
    * Sets `ambulances.is_available = false`.
    * Deletes all candidate requests for this incident from `inci_ambu`.
* **Success Response (200 OK)**:
  Full `IncidentOut` object with assigned ambulance details and hospital broadcasts.
* **Error Responses**:
  * `400 Bad Request`: Incident was not requested to this ambulance.
  * `404 Not Found`: Incident not found.
  * `409 Conflict`: "Another ambulance has already accepted incident {id}." or "Ambulance is currently busy with another incident."

---

## 2. Dispatch Configuration Constants

Configured in `app/core/config.py`:

| Constant | Default | Purpose |
|---|---|---|
| `CANDIDATE_RADIUS_KM` | `15.0` | Maximum distance (km) for candidate ambulance fan-out and backfill. |
| `MAX_AMBULANCES_PER_INCIDENT` | `5` | Maximum number of candidate ambulances requested per incident. |
| `LOCATION_FRESHNESS_SECONDS` | `120` | Max age (seconds) of ambulance GPS position to qualify as a candidate. |
| `BACKFILL_WINDOW_MINUTES` | `30` | Time window (minutes) to search for unassigned incidents when an ambulance goes online. |

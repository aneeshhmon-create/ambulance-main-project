# Driver Navigation & Incident Details API

This document describes the driver-facing endpoint used by the driver app's Navigation screen to fetch and poll incident details, patient location, and assigned hospital destination.

All driver-facing endpoints require a valid Bearer JWT (`Authorization: Bearer <token>`) issued for a driver account linked to the target ambulance in the `ambulance_driver` table. If the driver is not linked to that ambulance, the server returns `403 Forbidden`.

---

## 1. Endpoints

### 1.1 `GET /ambulances/{ambulance_id}/incidents/{incident_id}`

Fetches complete incident information for the ambulance holding the assignment, including the incident's GPS coordinates and the assigned hospital (null until accepted by a hospital).

* **Access**: Authenticated Driver (linked to `ambulance_id`)
* **Headers**:
  `Authorization: Bearer <jwt_token>`
* **Path Parameters**:
  * `ambulance_id` (integer): ID of the ambulance operating the assignment.
  * `incident_id` (integer): ID of the accepted incident.
* **Access Rules & Validations**:
  * If the caller provides no token or an invalid token: returns `401 Unauthorized`.
  * If the authenticated driver is not linked to `ambulance_id`: returns `403 Forbidden`.
  * If `incident_id` does not exist: returns `404 Not Found`.
  * If the incident is NOT assigned to `ambulance_id` (`incident.assigned_ambulance_id != ambulance_id`): returns `403 Forbidden`.
* **Success Response (200 OK) — Before Hospital Acceptance**:
  ```json
  {
    "id": 42,
    "status": "ambulance_assigned",
    "severity": "critical",
    "emergency_type": "Cardiac Arrest",
    "symptoms": ["severe chest pain", "loss of consciousness"],
    "victims": 1,
    "department_needed": "Cardiology",
    "transcript": "Caller reported patient collapsed and is unresponsive.",
    "location": {
      "lat": 9.9312,
      "lng": 76.2673
    },
    "created_at": "2026-10-19T11:45:00Z",
    "assigned_hospital": null
  }
  ```
* **Success Response (200 OK) — After Hospital Acceptance**:
  ```json
  {
    "id": 42,
    "status": "ambulance_assigned",
    "severity": "critical",
    "emergency_type": "Cardiac Arrest",
    "symptoms": ["severe chest pain", "loss of consciousness"],
    "victims": 1,
    "department_needed": "Cardiology",
    "transcript": "Caller reported patient collapsed and is unresponsive.",
    "location": {
      "lat": 9.9312,
      "lng": 76.2673
    },
    "created_at": "2026-10-19T11:45:00Z",
    "assigned_hospital": {
      "id": 3,
      "name": "Aster Medcity Kochi",
      "location": {
        "lat": 10.0461,
        "lng": 76.2758
      }
    }
  }
  ```
* **Error Responses**:
  * `401 Unauthorized`: Missing or expired Bearer token.
  * `403 Forbidden`: Driver not linked to `ambulance_id`, or incident is not assigned to this ambulance.
  * `404 Not Found`: Incident ID not found.

---

## 2. Dev & Simulation Utilities

### `accept_as_hospital.py`

A command-line script to simulate hospital acceptance without opening the hospital web dashboard.

* **Location**: `accept_as_hospital.py` (mounted at `/app/accept_as_hospital.py` in the container)
* **Usage**:
  ```bash
  # Inside Docker container
  docker compose exec app python accept_as_hospital.py <incident_id> <hospital_id>

  # Example
  docker compose exec app python accept_as_hospital.py 42 1
  ```
* **Behavior**:
  1. Verifies the incident and hospital exist in PostgreSQL.
  2. Queries `incident_broadcasts` for the matching pending broadcast (`incident_id`, `target_type='hospital'`, `target_id=hospital_id`, `status='pending'`).
  3. Calls the real atomic accept endpoint `POST /incidents/{incident_id}/broadcasts/{broadcast_id}/accept`.
  4. Returns `0` on success and prints the updated status and assigned hospital.

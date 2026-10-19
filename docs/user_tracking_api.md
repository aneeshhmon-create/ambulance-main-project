# User live tracking API

Data behind the user app's **Live Tracking** map.

## `GET /incidents/{incident_id}/tracking`

* **Access**: signed-in user (`Authorization: Bearer <user jwt>`).
  * `401` missing/invalid token.
  * `404` incident not found.
  * `403` the incident belongs to another user. Incidents with no owner
    (e.g. created by `create_demo_incidents.py` or curl) are visible to any
    signed-in user, so they can be tested.
* **Response (200)**:
  ```json
  {
    "id": 42, "status": "ambulance_assigned", "severity": "critical",
    "emergency_type": "Cardiac Arrest", "symptoms": ["chest pain"],
    "victims": 1, "department_needed": "Cardiology",
    "transcript": "Patient collapsed.",
    "location": {"lat": 8.52, "lng": 76.943},
    "created_at": "2026-10-19T11:45:00Z",
    "assigned_hospital": {"id": 3, "name": "City General",
                          "location": {"lat": 8.5241, "lng": 76.9366}},
    "ambulance": {"id": 7, "registration_number": "KL-07-AE-1234",
                  "vehicle_type": "ALS",
                  "location": {"lat": 8.5164, "lng": 76.9491},
                  "location_updated_at": "2026-10-19T11:46:00Z"}
  }
  ```
  `assigned_hospital` is `null` until a hospital accepts. `ambulance` is `null`
  while no ambulance is assigned (including after the driver cancels), and its
  `location` is `null` until it has reported a position.

The existing `GET /incidents/{id}` (used by the text status screen) is unchanged.

## Map behaviour (user app)

* Polls every 4 s; stops when the incident is `completed`; pauses when the app
  is paused (not on web focus loss).
* Ambulance → you route from OSRM when the ambulance appears and after ~60 m of
  movement; you → hospital once per assigned hospital. Falls back to a dashed
  straight line if OSRM fails.
* Camera fits everything when the ambulance first appears and when a hospital
  is assigned; the Recenter button fits again.

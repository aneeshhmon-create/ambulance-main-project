# Driver Navigation Feature - Progress Checklist

Branch: `feature/driver-navigation`
Last updated: 2026-10-19 (session 1 starting)

## Legend
- Done - implemented and matches the spec
- Partial - exists but has gaps noted below
- Missing - not started yet

---

## 1. INSPECTION & PLAN (STEP 1)

| Item | Status | Notes |
|------|--------|-------|
| Git branch creation | Done | Created `feature/driver-navigation` from `feature/driver-home` |
| Driver app codebase inspection | Done | Reviewed HomeScreen, storage (driver_jwt, selected_ambulance_id), location sharing, accept flow |
| Backend inspection | Done | Checked Incident model, hospital accept endpoint, no driver incident detail endpoint currently exists |
| Step 1 inspection report to user | Done | Reporting findings and plan before Step 2 |

---

## 2. BACKEND (STEP 2)

| Item | Status | Notes |
|------|--------|-------|
| Pydantic schema for incident detail | Done | `DriverIncidentDetailOut` and `DriverIncidentHospitalOut` in `app/schemas/ambulance.py` |
| `GET /ambulances/{ambulance_id}/incidents/{incident_id}` | Done | In `app/routers/ambulances.py`, auth + link check (403) + assignment check (403/404) |
| PostGIS geography to lat/lng conversion | Done | Helper functions `_incident_location` and `_hospital_location` |
| `accept_as_hospital.py` dev script | Done | Standalone CLI at repo root, queries pending broadcast and calls `/accept` |
| Docker-compose mount for `accept_as_hospital.py` | Done | Mounted in `docker-compose.yml` |
| Backend tests in `app/tests/test_driver_navigation.py` | Done | 6 test cases covering 401, 403 unlinked, 404 missing, 403 wrong amb, hospital null -> assigned |
| API docs in `docs/driver_navigation_api.md` | Done | Complete endpoint specification, JSON shapes, and dev script docs |

---

## 3. FLUTTER NAVIGATION PAGE (STEP 3)

| Item | Status | Notes |
|------|--------|-------|
| Add `flutter_map` and `latlong2` to `pubspec.yaml` | Missing | Run `flutter pub get` |
| Verify Android internet permission | Done | Present in `flutter_app/android/app/src/driver/AndroidManifest.xml` |
| Incident detail model & API service method | Missing | Fetch incident detail with JWT auth |
| OSRM routing service | Missing | Fetch route from OSRM demo server, distance & ETA, fallback straight line |
| Compact top strip widget | Missing | Incident number, severity badge, type, victims, dept; expands on tap for symptoms & transcript; small cancel button |
| Status chip widget | Missing | "Looking for a hospital..." / "Hospital assigned: <name>" + distance & ETA |
| Navigation screen (`navigation_screen.dart`) | Missing | Map filling remaining space, OSM raster tiles + userAgent + attribution |
| Map markers | Missing | Red incident marker, hospital marker (when assigned), blue dot for driver GPS |
| Map camera control | Missing | Initial center on incident; fit bounds when hospital assigned; recenter/fit button; pan/zoom preserved across polls |
| Polling lifecycle | Missing | Poll every 3-5s, stop on dispose / app paused, resume on resume |
| Location sharing continuity | Missing | Kept alive from HomeScreen underneath; reuse Geolocator for driver blue dot |
| Replace placeholder in `home_screen.dart` | Missing | Navigate to `NavigationScreen(incidentId: incident.id, ambulanceId: widget.ambulance.id)` |
| Cancel & system back | Missing | Pop back to Home with TODO comments; TODO hook for arrival/completed page |
| Error handling | Missing | Non-blocking retry banner, 401 redirect to auth, 403/404 back home, permission denied fallback, OSRM fallback |

---

## 4. VERIFICATION & DOCUMENTATION (STEP 4)

| Item | Status | Notes |
|------|--------|-------|
| Docker container tests pass | Missing | Run pytest in `ambulance_app` container |
| `flutter analyze` clean | Missing | 0 errors |
| Manual testing instructions | Missing | Demo commands and checklist |
| Known limitations & notes | Missing | Cancellation lifecycle, resumption after restart, etc. |

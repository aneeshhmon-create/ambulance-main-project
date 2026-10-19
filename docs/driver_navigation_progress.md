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
| Add `flutter_map` and `latlong2` to `pubspec.yaml` | Done | Added `flutter_map: ^8.3.2` and `latlong2: ^0.10.1` |
| Verify Android internet permission | Done | Present in `flutter_app/android/app/src/driver/AndroidManifest.xml` |
| Incident detail model & API service method | Done | `DriverIncidentDetail` in `incident_detail.dart`, `fetchIncidentDetail` in `driver_api_service.dart` |
| OSRM routing service | Done | `RoutingService` in `routing_service.dart` with OSRM demo server and straight line fallback |
| Compact top strip widget | Done | `IncidentTopStrip` in `incident_top_strip.dart` with severity badge, expand/collapse, and small cancel button |
| Status chip widget | Done | `NavigationStatusChip` in `navigation_status_chip.dart` showing searching or hospital name + km + ETA |
| Navigation screen (`navigation_screen.dart`) | Done | Full map page with OSM raster tiles, user agent, OSM attribution, markers, and polyline |
| Map markers | Done | Red incident marker, teal hospital marker (when assigned), blue pulsing dot for driver GPS |
| Map camera control | Done | Initial center on incident; fit bounds when hospital assigned; recenter/fit button; pan/zoom preserved across polls |
| Polling lifecycle | Done | Polls `GET /ambulances/{id}/incidents/{id}` every 4s, pauses on app pause, resumes on resume |
| Location sharing continuity | Done | Kept running in `HomeScreen` underneath; independent position stream in `NavigationScreen` for blue dot |
| Replace placeholder in `home_screen.dart` | Done | Accept flow pushes `NavigationScreen(incidentId, ambulanceId)` |
| Cancel & system back | Done | PopScope + Cancel button pop back to Home with TODO comments for cancellation and arrival |
| Error handling | Done | Non-blocking retry banner, 401 redirect to auth, 403/404 back home, permission denied fallback, OSRM fallback |

---

## 4. VERIFICATION & DOCUMENTATION (STEP 4)

| Item | Status | Notes |
|------|--------|-------|
| Docker container tests pass | Done | 47/47 pytest tests pass inside `ambulance_app` container |
| `flutter analyze` clean | Done | 0 issues found across all user and driver app code |
| Manual testing instructions | Done | Documented in `docs/driver_navigation_progress.md` and report |
| Known limitations & notes | Done | Cancellation lifecycle, resumption after restart, etc. |

---

## 5. BUG FIXES (POST-DELIVERY)

| Item | Status | Notes |
|------|--------|-------|
| Logout-and-return loses active navigation | Done | `_resumeNavigationIfNeeded()` in `home_screen.dart` calls `GET /ambulances/{id}/assignment` on init and on app-resume; navigates to `NavigationScreen` automatically if `assigned=true`. Guard flag `_checkingAssignment` prevents duplicate pushes. Committed `90f673f`. |
| Cancel returns to Home but does not release incident to other drivers | Done | New `POST /ambulances/{id}/incidents/{id}/cancel` backend endpoint: clears assignment, resets incident to `pending`, re-inserts `inci_ambu` rows for all other online+available ambulances. Flutter: `_handleCancel` now shows a confirmation dialog, calls `cancelIncident()`, then pops. Committed `aa3dba5`. |

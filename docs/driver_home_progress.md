# Driver Home Feature - Progress Checklist

Branch: `feature/driver-home`
Last updated: 2026-10-19 (session 2 complete)

## Legend
- Done - implemented and matches the spec
- Partial - exists but has gaps noted below

---

## DATABASE

| Item | Status | Notes |
|------|--------|-------|
| inci_ambu table (migration) | Done | e5f6a7b8c9d0_inci_ambu_and_ambulance_online.py |
| ambulances.is_online column | Done | bool, default false, indexed |
| ambulances.location_updated_at column | Done | timestamptz, nullable |
| IncidentAmbulance ORM model | Done | app/models/incident_ambulance.py |
| Ambulance model updated | Done | is_online, location_updated_at, requested_incidents rel |

---

## BACKEND SCHEMAS

| Item | Status | Notes |
|------|--------|-------|
| AmbulanceOnlineUpdate | Done | app/schemas/ambulance.py |
| AmbulanceIncidentOut | Done | All required fields present |
| AmbulanceOut updated | Done | is_online, location_updated_at added |
| AmbulanceAssignmentOut | Done | Full assignment shape |

---

## BACKEND CONFIG / CONSTANTS

| Item | Status | Notes |
|------|--------|-------|
| CANDIDATE_RADIUS_KM | Done | app/core/config.py, default 15 |
| MAX_AMBULANCES_PER_INCIDENT | Done | default 5 |
| LOCATION_FRESHNESS_SECONDS | Done | default 120 |
| BACKFILL_WINDOW_MINUTES | Done | default 30 |

---

## BACKEND ENDPOINTS

| Item | Status | Notes |
|------|--------|-------|
| PATCH /ambulances/{id}/online | Done | Auth + link check, 409 on active incident, backfill |
| PATCH /ambulances/{id}/location | Done | Auth + link check, updates location_updated_at |
| GET /ambulances/{id}/incidents | Done | Auth + link check, offline returns [], ordered severity |
| POST /ambulances/{id}/incidents/{id}/accept | Done | Atomic (FOR UPDATE), 409 on race, removes inci_ambu rows |
| POST /incidents fan-out instead of auto-assign | Done | _create_incident_core does fan-out |
| POST /incidents/manual fan-out | Done | Same helper _create_incident_core |
| Backfill when going online | Done | PostGIS ST_MakePoint/joined query with nested savepoint |

---

## BACKEND TESTS (app/tests/test_driver_home.py)

| Test | Status |
|------|--------|
| Driver cannot access unlinked ambulance (403) | Done |
| Online toggle works | Done |
| Offline blocked during active incident (409) | Done |
| Incident list empty when offline | Done |
| Incident list ordered by severity online | Done |
| Atomic accept -- two ambulances -> one 200, one 409 | Done |
| inci_ambu rows deleted after accept | Done |
| Backfill on going online | Done |
| Fan-out picks online+available ambulances | Done |
| Fan-out ignores offline/busy ambulances | Done |

---

## DEMO SCRIPT

| Item | Status | Notes |
|------|--------|-------|
| create_demo_incidents.py at repo root | Done | Posts 4 incidents via --lat/--lng/--url args |

---

## API DOCUMENTATION

| Item | Status | Notes |
|------|--------|-------|
| docs/driver_home_api.md | Done | All 4 endpoints, JSON shapes, constants table |
| docs/driver_home_progress.md | Done | This file |

---

## DOCKER / DEPENDENCY HYGIENE

| Item | Status | Notes |
|------|--------|-------|
| requirements.txt complete | Done | fastapi, sqlalchemy, geoalchemy2, pyjwt, google-auth, etc. |
| Dockerfile system deps | Done | gcc, libpq-dev |
| docker-compose.yml mounts ./app | Done | Live-reload volume present |
| docker-compose.yml mounts alembic/ and tests/ | Done | Added in session 2: alembic/, alembic.ini, tests/, root scripts all volume-mounted |

---

## FLUTTER - HOME SCREEN (session 2 completions)

| Item | Status | Notes |
|------|--------|-------|
| home_screen.dart exists | Done | lib/driver_app/screens/home_screen.dart |
| Header: Hello name, reg number, vehicle type | Done | |
| Header: Online/Offline toggle | Done | With loading state |
| Header: GPS permission + first fix on going online | Done | Geolocator.requestPermission + getCurrentPosition; snaps back + message if denied |
| Header: Sign out / change ambulance | Done | IconButton with confirmation dialog; sets offline first |
| Incident list: scrollable, severity badge, type, distance | Done | _IncidentTile widget |
| Incident list: Details button + bottom sheet | Done | _IncidentDetailSheet (severity, type, symptoms, victims, dept, transcript, time since) |
| Incident list: pull-to-refresh | Done | RefreshIndicator |
| Incident list: polling every 8s while online | Done | Timer.periodic |
| Incident list: stop polling when offline / disposed | Done | |
| Incident list: empty state (offline) | Done | Clear message: Toggle Online to receive requests |
| Incident list: empty state (online, no incidents) | Done | No incoming requests message |
| Incident list: error state with Retry | Done | Cloud_off icon + error message + Retry button |
| Accept navigates to IncidentAcceptedScreen | Done | lib/driver_app/screens/incident_accepted_screen.dart |
| Accept: loading state + double-tap block | Done | _acceptingIds set guards double-tap |
| Accept: 409 shows clear message | Done | snackbar with detail message |
| HomeFooter as own reusable widget | Done | lib/driver_app/widgets/home_footer.dart |
| Live GPS sharing every 7s while online | Done | Timer + PATCH /ambulances/{id}/location |
| 401 handling (redirect to AuthPage) | Done | fetchIncidents 401 -> clearSession -> AuthPage |

---

## FLUTTER - SERVICES / MODELS

| Item | Status | Notes |
|------|--------|-------|
| services/driver_api_service.dart | Done | setOnline, fetchIncidents, acceptIncident, fetchAssignment, updateLocation |
| models/driver.dart | Done | DriverModel, AmbulanceModel |
| Location sharing via DriverApiService.updateLocation | Done | Called every 7s from home_screen.dart timer |

---

## flutter analyze

No issues found. (confirmed 2026-10-19)

---

## EVERYTHING IS DONE - No remaining items

"""
app/routers/ambulances.py
──────────────────────────
CRUD + geo-search endpoints for the Ambulance resource.

Endpoints
─────────
POST   /ambulances                        – register an ambulance
GET    /ambulances                        – list all ambulances
GET    /ambulances/nearest                – find nearest available ambulance
PATCH  /ambulances/{id}/location          – update GPS position
GET    /ambulances/{id}/assignment        – active incident + patient/hospital locations

Notes on geography
──────────────────
• Same geography conventions as hospitals.py.
• ST_Distance on GEOGRAPHY returns metres.
• /nearest uses ORDER BY distance ASC LIMIT 1 (no radius filter).
"""

from datetime import datetime, timezone
import json
import logging
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import text
from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.security import get_current_driver
from app.db import get_db
from app.models.ambulance import Ambulance
from app.models.driver import Driver
from app.models.hospital import Hospital
from app.models.incident import Incident
from app.models.incident_ambulance import IncidentAmbulance
from app.models.incident_ambulance_cancellation import IncidentAmbulanceCancellation
from app.schemas.ambulance import (
    AmbulanceCreate,
    AmbulanceOut,
    AmbulanceLocationUpdate,
    AmbulanceOnlineUpdate,
    AmbulanceNearestOut,
    AmbulanceAssignmentOut,
    AmbulanceIncidentOut,
    AssignmentHospitalOut,
    AssignmentPatientOut,
    DriverIncidentDetailOut,
    DriverIncidentHospitalOut,
)
from app.schemas.hospital import LocationSchema
from app.schemas.incident import IncidentOut
from app.routers.incidents import _build_incident_out, _incident_location

logger = logging.getLogger(__name__)

router = APIRouter()


# ── Helpers ───────────────────────────────────────────────────────────────────

def _wkt_point(lat: float, lng: float) -> str:
    """Build a WKT POINT string (PostGIS expects lng lat order)."""
    return f"SRID=4326;POINT({lng} {lat})"


def _ambulance_orm_to_out(a: Ambulance, db: Session) -> AmbulanceOut:
    """Resolve the geography column to plain lat/lng for the response."""
    if a.location is None:
        loc = None
    else:
        try:
            result = db.execute(
                text(
                    "SELECT ST_Y(location::geometry) AS lat, "
                    "       ST_X(location::geometry) AS lng "
                    "FROM ambulances WHERE id = :id"
                ),
                {"id": a.id},
            ).fetchone()
            loc = LocationSchema(lat=result.lat, lng=result.lng) if result and result.lat is not None else None
        except Exception:
            loc = LocationSchema(lat=0.0, lng=0.0)

    return AmbulanceOut(
        id=a.id,
        registration_number=a.registration_number,
        vehicle_type=a.vehicle_type,
        location=loc,
        is_available=a.is_available,
        is_online=a.is_online,
        location_updated_at=a.location_updated_at,
    )


def _verify_driver_ambulance_access(
    ambulance_id: int, driver: Driver, db: Session
) -> Ambulance:
    """Verify that the authenticated driver is authorized to operate this ambulance."""
    link = db.execute(
        text(
            "SELECT 1 FROM ambulance_driver "
            "WHERE ambulance_id = :aid AND driver_id = :did"
        ),
        {"aid": ambulance_id, "did": driver.id},
    ).fetchone()
    if not link:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=f"Driver {driver.id} is not authorized to operate ambulance {ambulance_id}.",
        )
    amb = db.get(Ambulance, ambulance_id)
    if not amb:
        raise HTTPException(
            status_code=404, detail=f"Ambulance {ambulance_id} not found"
        )
    return amb


# ── POST /ambulances ───────────────────────────────────────────────────────────

@router.post("", response_model=AmbulanceOut, status_code=201, summary="Register an ambulance")
def create_ambulance(body: AmbulanceCreate, db: Session = Depends(get_db)):
    """Register a new ambulance with its registration number, type and starting location."""
    # Check for duplicate registration number
    existing = db.execute(
        text("SELECT id FROM ambulances WHERE registration_number = :reg"),
        {"reg": body.registration_number},
    ).fetchone()
    if existing:
        raise HTTPException(
            status_code=409,
            detail=f"Ambulance with registration number '{body.registration_number}' already exists.",
        )

    ambulance = Ambulance(
        registration_number=body.registration_number,
        vehicle_type=body.vehicle_type,
        location=_wkt_point(body.location.lat, body.location.lng),
    )
    db.add(ambulance)
    db.commit()
    db.refresh(ambulance)
    return _ambulance_orm_to_out(ambulance, db)


# ── GET /ambulances ────────────────────────────────────────────────────────────

@router.get("", response_model=list[AmbulanceOut], summary="List all ambulances")
def list_ambulances(
    skip: int = Query(0, ge=0),
    limit: int = Query(100, ge=1, le=500),
    db: Session = Depends(get_db),
):
    """Return a paginated list of all ambulances."""
    rows = db.execute(
        text(
            "SELECT a.id, a.registration_number, a.vehicle_type, a.is_available, "
            "       a.is_online, a.location_updated_at, "
            "       ST_Y(a.location::geometry) AS lat, "
            "       ST_X(a.location::geometry) AS lng "
            "FROM ambulances a "
            "ORDER BY a.id "
            "LIMIT :limit OFFSET :skip"
        ),
        {"limit": limit, "skip": skip},
    ).fetchall()

    return [
        AmbulanceOut(
            id=r.id,
            registration_number=r.registration_number,
            vehicle_type=r.vehicle_type,
            location=LocationSchema(lat=r.lat, lng=r.lng) if r.lat is not None else None,
            is_available=r.is_available,
            is_online=r.is_online,
            location_updated_at=r.location_updated_at,
        )
        for r in rows
    ]


# ── GET /ambulances/nearest ────────────────────────────────────────────────────
# IMPORTANT: declared before /{id}/location so "nearest" is not parsed as an id.

@router.get(
    "/nearest",
    response_model=AmbulanceNearestOut,
    summary="Find the nearest available ambulance",
)
def nearest_ambulance(
    lat: float = Query(..., ge=-90.0, le=90.0, description="Query latitude"),
    lng: float = Query(..., ge=-180.0, le=180.0, description="Query longitude"),
    db: Session = Depends(get_db),
):
    """
    Return the single closest available ambulance to the given coordinates,
    using ST_Distance ordered ascending with LIMIT 1.

    Raises 404 if no available ambulances are registered.
    """
    row = db.execute(
        text(
            "SELECT a.id, a.registration_number, a.vehicle_type, a.is_available, "
            "       ST_Y(a.location::geometry)  AS lat, "
            "       ST_X(a.location::geometry)  AS lng, "
            "       ST_Distance(a.location, ST_MakePoint(:lng, :lat)::geography) AS distance_m "
            "FROM ambulances a "
            "WHERE a.is_available = true "
            "  AND a.location IS NOT NULL "
            "ORDER BY distance_m ASC "
            "LIMIT 1"
        ),
        {"lat": lat, "lng": lng},
    ).fetchone()

    if not row:
        raise HTTPException(status_code=404, detail="No available ambulances found")

    return AmbulanceNearestOut(
        id=row.id,
        registration_number=row.registration_number,
        vehicle_type=row.vehicle_type,
        location=LocationSchema(lat=row.lat, lng=row.lng),
        is_available=row.is_available,
        is_online=getattr(row, "is_online", False),
        location_updated_at=getattr(row, "location_updated_at", None),
        distance_m=row.distance_m,
    )


# ── PATCH /ambulances/{id}/online ─────────────────────────────────────────────

@router.patch(
    "/{ambulance_id}/online",
    response_model=AmbulanceOut,
    summary="Toggle ambulance online status and optionally set location",
)
def update_ambulance_online(
    ambulance_id: int,
    body: AmbulanceOnlineUpdate,
    driver: Driver = Depends(get_current_driver),
    db: Session = Depends(get_db),
):
    """
    Toggle online state for the selected ambulance.
    Requires the signed-in driver to be linked to this ambulance.
    Going offline while holding an active (assigned, not completed) incident returns 409.
    When going online, backfills recent unassigned incidents within CANDIDATE_RADIUS_KM.
    """
    ambulance = _verify_driver_ambulance_access(ambulance_id, driver, db)

    if not body.is_online:
        # Check if ambulance holds an active incident
        active_case = db.execute(
            text(
                "SELECT id FROM incidents "
                "WHERE assigned_ambulance_id = :aid "
                "  AND status IN ('hospital_assigned', 'ambulance_assigned')"
            ),
            {"aid": ambulance_id},
        ).fetchone()
        if active_case:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail=f"Cannot go offline while holding active incident #{active_case.id}.",
            )
        ambulance.is_online = False
        db.commit()
        db.refresh(ambulance)
        return _ambulance_orm_to_out(ambulance, db)

    # Going online
    ambulance.is_online = True
    now = datetime.now(timezone.utc)
    if body.lat is not None and body.lng is not None:
        ambulance.location = _wkt_point(body.lat, body.lng)
        ambulance.location_updated_at = now

    # Backfill: link recent unassigned incidents within candidate radius
    radius_m = settings.CANDIDATE_RADIUS_KM * 1000.0
    window_minutes = settings.BACKFILL_WINDOW_MINUTES
    unassigned_ids = []

    if body.lat is not None and body.lng is not None:
        try:
            with db.begin_nested():
                rows = db.execute(
                    text(
                        "SELECT i.id FROM incidents i "
                        "WHERE i.assigned_ambulance_id IS NULL "
                        "  AND i.status != 'completed' "
                        "  AND i.created_at >= NOW() - (:window || ' minutes')::interval "
                        "  AND ST_DWithin("
                        "        i.location,"
                        "        ST_MakePoint(:lng, :lat)::geography,"
                        "        :radius_m"
                        "      ) "
                        "  AND NOT EXISTS ( "
                        "        SELECT 1 FROM inci_ambu_cancelled c "
                        "        WHERE c.incident_id = i.id AND c.ambulance_id = :aid "
                        "  ) "
                        "  AND NOT EXISTS ( "
                        "        SELECT 1 FROM inci_ambu ia "
                        "        WHERE ia.incident_id = i.id AND ia.ambulance_id = :aid "
                        "  )"
                    ),
                    {
                        "window": window_minutes,
                        "lat": body.lat,
                        "lng": body.lng,
                        "radius_m": radius_m,
                        "aid": ambulance.id,
                    },
                ).fetchall()
                unassigned_ids = [r.id for r in rows]
        except Exception as exc:
            logger.warning("[Ambulances] Spatial backfill query failed (%s); trying fallback.", exc)
            try:
                with db.begin_nested():
                    rows = db.execute(
                        text(
                            "SELECT i.id FROM incidents i "
                            "WHERE i.assigned_ambulance_id IS NULL "
                            "  AND i.status != 'completed' "
                            "  AND NOT EXISTS ( "
                            "        SELECT 1 FROM inci_ambu_cancelled c "
                            "        WHERE c.incident_id = i.id AND c.ambulance_id = :aid "
                            "  ) "
                            "  AND NOT EXISTS ( "
                            "        SELECT 1 FROM inci_ambu ia "
                            "        WHERE ia.incident_id = i.id AND ia.ambulance_id = :aid "
                            "  )"
                        ),
                        {"aid": ambulance.id},
                    ).fetchall()
                    unassigned_ids = [r.id for r in rows]
            except Exception:
                pass
    elif ambulance.location is not None:
        try:
            with db.begin_nested():
                rows = db.execute(
                    text(
                        "SELECT i.id FROM incidents i, ambulances a "
                        "WHERE a.id = :aid "
                        "  AND a.location IS NOT NULL "
                        "  AND i.assigned_ambulance_id IS NULL "
                        "  AND i.status != 'completed' "
                        "  AND i.created_at >= NOW() - (:window || ' minutes')::interval "
                        "  AND ST_DWithin(i.location, a.location, :radius_m) "
                        "  AND NOT EXISTS ( "
                        "        SELECT 1 FROM inci_ambu_cancelled c "
                        "        WHERE c.incident_id = i.id AND c.ambulance_id = :aid "
                        "  ) "
                        "  AND NOT EXISTS ( "
                        "        SELECT 1 FROM inci_ambu ia "
                        "        WHERE ia.incident_id = i.id AND ia.ambulance_id = :aid "
                        "  )"
                    ),
                    {
                        "window": window_minutes,
                        "radius_m": radius_m,
                        "aid": ambulance.id,
                    },
                ).fetchall()
                unassigned_ids = [r.id for r in rows]
        except Exception as exc:
            logger.warning("[Ambulances] Spatial backfill query from DB location failed (%s).", exc)

    for iid in unassigned_ids:
        db.add(IncidentAmbulance(incident_id=iid, ambulance_id=ambulance.id))

    db.commit()
    db.refresh(ambulance)
    return _ambulance_orm_to_out(ambulance, db)


def _backfill_incidents_for_location(
    db: Session, ambulance_id: int, lat: float, lng: float
) -> None:
    """Link recent unassigned incidents within range to this ambulance.

    Skips incidents it is already linked to and ones it cancelled. Best-effort:
    any failure (e.g. non-spatial test DB) leaves the location update intact.
    """
    try:
        with db.begin_nested():
            rows = db.execute(
                text(
                    "SELECT i.id FROM incidents i "
                    "WHERE i.assigned_ambulance_id IS NULL "
                    "  AND i.status != 'completed' "
                    "  AND i.created_at >= NOW() - (:window || ' minutes')::interval "
                    "  AND ST_DWithin("
                    "        i.location, ST_MakePoint(:lng, :lat)::geography, :radius_m) "
                    "  AND NOT EXISTS ( "
                    "        SELECT 1 FROM inci_ambu_cancelled c "
                    "        WHERE c.incident_id = i.id AND c.ambulance_id = :aid ) "
                    "  AND NOT EXISTS ( "
                    "        SELECT 1 FROM inci_ambu ia "
                    "        WHERE ia.incident_id = i.id AND ia.ambulance_id = :aid )"
                ),
                {
                    "window": settings.BACKFILL_WINDOW_MINUTES,
                    "lat": lat,
                    "lng": lng,
                    "radius_m": settings.CANDIDATE_RADIUS_KM * 1000.0,
                    "aid": ambulance_id,
                },
            ).fetchall()
            for r in rows:
                db.add(IncidentAmbulance(incident_id=r.id, ambulance_id=ambulance_id))
    except Exception as exc:
        logger.debug("[Ambulances] Location backfill skipped (%s).", exc)


# ── PATCH /ambulances/{id}/location ───────────────────────────────────────────

@router.patch(
    "/{ambulance_id}/location",
    response_model=AmbulanceOut,
    summary="Update an ambulance's GPS location",
)
def update_ambulance_location(
    ambulance_id: int,
    body: AmbulanceLocationUpdate,
    driver: Driver = Depends(get_current_driver),
    db: Session = Depends(get_db),
):
    """
    Update the current position of an ambulance.
    Called repeatedly from the driver's phone GPS.
    Requires the authenticated driver to be linked to this ambulance.
    """
    ambulance = _verify_driver_ambulance_access(ambulance_id, driver, db)

    ambulance.location = _wkt_point(body.location.lat, body.location.lng)
    ambulance.location_updated_at = datetime.now(timezone.utc)

    # An online, free ambulance that has just moved into range of a recent
    # unassigned incident (or just got a fresh fix) should be offered it, so
    # incidents are not missed because of timing at creation.
    if ambulance.is_online and ambulance.is_available:
        _backfill_incidents_for_location(
            db, ambulance.id, body.location.lat, body.location.lng
        )
    db.commit()
    db.refresh(ambulance)
    return _ambulance_orm_to_out(ambulance, db)


# ── GET /ambulances/{id}/incidents ────────────────────────────────────────────

@router.get(
    "/{ambulance_id}/incidents",
    response_model=list[AmbulanceIncidentOut],
    summary="List unassigned incidents requested for this ambulance",
)
def list_ambulance_incidents(
    ambulance_id: int,
    driver: Driver = Depends(get_current_driver),
    db: Session = Depends(get_db),
):
    """
    Returns incidents requested for this ambulance via inci_ambu that are still unassigned.
    Returns empty list if the ambulance is offline.
    Ordered by severity (critical first) then newest.
    """
    ambulance = _verify_driver_ambulance_access(ambulance_id, driver, db)

    if not ambulance.is_online:
        return []

    rows = []
    try:
        rows = db.execute(
            text(
                "SELECT i.id, i.severity, i.emergency_type, i.symptoms, i.victims, "
                "       i.department_needed, i.transcript, i.created_at, "
                "       ST_Y(i.location::geometry) AS lat, "
                "       ST_X(i.location::geometry) AS lng, "
                "       CASE WHEN a.location IS NOT NULL "
                "            THEN ST_Distance(i.location, a.location) / 1000.0 "
                "            ELSE NULL END AS distance_km "
                "FROM inci_ambu ia "
                "JOIN incidents i ON i.id = ia.incident_id "
                "JOIN ambulances a ON a.id = ia.ambulance_id "
                "WHERE ia.ambulance_id = :aid "
                "  AND i.assigned_ambulance_id IS NULL "
                "  AND i.status != 'completed' "
                "ORDER BY CASE i.severity "
                "           WHEN 'critical' THEN 0 WHEN 'high' THEN 1 "
                "           WHEN 'medium' THEN 2 WHEN 'low' THEN 3 ELSE 4 END, "
                "         i.created_at DESC"
            ),
            {"aid": ambulance_id},
        ).fetchall()
    except Exception as exc:
        logger.warning("[Ambulances] Query requested incidents failed (%s); checking non-spatial query.", exc)
        try:
            rows = db.execute(
                text(
                    "SELECT i.id, i.severity, i.emergency_type, i.symptoms, i.victims, "
                    "       i.department_needed, i.transcript, i.created_at, "
                    "       0.0 AS lat, 0.0 AS lng, NULL AS distance_km "
                    "FROM inci_ambu ia "
                    "JOIN incidents i ON i.id = ia.incident_id "
                    "WHERE ia.ambulance_id = :aid "
                    "  AND i.assigned_ambulance_id IS NULL "
                    "  AND i.status != 'completed' "
                    "ORDER BY CASE i.severity "
                    "           WHEN 'critical' THEN 0 WHEN 'high' THEN 1 "
                    "           WHEN 'medium' THEN 2 WHEN 'low' THEN 3 ELSE 4 END, "
                    "         i.created_at DESC"
                ),
                {"aid": ambulance_id},
            ).fetchall()
        except Exception:
            rows = []

    return [
        AmbulanceIncidentOut(
            id=r.id,
            severity=r.severity,
            emergency_type=r.emergency_type,
            symptoms=list(r.symptoms or []),
            victims=r.victims,
            department_needed=r.department_needed,
            transcript=r.transcript,
            location=LocationSchema(lat=r.lat, lng=r.lng),
            distance_km=round(r.distance_km, 2) if r.distance_km is not None else None,
            created_at=r.created_at,
        )
        for r in rows
    ]


# ── POST /ambulances/{id}/incidents/{id}/accept ───────────────────────────────

@router.post(
    "/{ambulance_id}/incidents/{incident_id}/accept",
    response_model=IncidentOut,
    summary="Ambulance accepts an incident request (race-safe)",
)
def accept_ambulance_incident(
    ambulance_id: int,
    incident_id: int,
    driver: Driver = Depends(get_current_driver),
    db: Session = Depends(get_db),
):
    """
    Called by an ambulance driver to claim a requested incident.
    Race-safe: uses SELECT ... FOR UPDATE on the incident row.
    Returns HTTP 409 if another ambulance has already accepted it.
    """
    ambulance = _verify_driver_ambulance_access(ambulance_id, driver, db)

    # 1. Lock incident row and check race condition (FOR UPDATE on Postgres)
    for_update = "" if (db.bind and db.bind.dialect.name == "sqlite") else "FOR UPDATE"
    locked_row = db.execute(
        text(
            f"SELECT id, status, assigned_ambulance_id, assigned_hospital_id "
            f"FROM incidents WHERE id = :iid {for_update}"
        ),
        {"iid": incident_id},
    ).fetchone()

    if not locked_row:
        raise HTTPException(status_code=404, detail=f"Incident {incident_id} not found")

    if locked_row.status == "completed" or locked_row.assigned_ambulance_id is not None:
        db.rollback()
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=f"Another ambulance has already accepted incident {incident_id}.",
        )

    if not ambulance.is_available:
        db.rollback()
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="This ambulance is currently busy with another incident.",
        )

    # 2. Verify incident was requested to this ambulance
    requested = db.execute(
        text("SELECT 1 FROM inci_ambu WHERE incident_id = :iid AND ambulance_id = :aid"),
        {"iid": incident_id, "aid": ambulance_id},
    ).fetchone()
    if not requested:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Incident {incident_id} was not requested to ambulance {ambulance_id}.",
        )

    # 3. Assign incident to this ambulance
    db.execute(
        text(
            "UPDATE incidents "
            "SET assigned_ambulance_id = :aid, status = 'ambulance_assigned' "
            "WHERE id = :iid"
        ),
        {"aid": ambulance_id, "iid": incident_id},
    )
    ambulance.is_available = False

    # Remove all candidate requests for this incident now that it is claimed
    db.execute(
        text("DELETE FROM inci_ambu WHERE incident_id = :iid"),
        {"iid": incident_id},
    )

    db.commit()
    db.expire_all()

    incident = db.get(Incident, incident_id)
    if not incident:
        raise HTTPException(status_code=404, detail="Incident not found after commit")
    return _build_incident_out(incident, db)


# ── POST /ambulances/{id}/incidents/{id}/reject ───────────────────────────────

@router.post(
    "/{ambulance_id}/incidents/{incident_id}/reject",
    summary="Driver rejects an incident request",
)
def reject_ambulance_incident(
    ambulance_id: int,
    incident_id: int,
    driver: Driver = Depends(get_current_driver),
    db: Session = Depends(get_db),
):
    """
    Called by a driver to turn down an incident requested to their ambulance.

    Removes this ambulance's request row so the incident disappears from its
    list, and remembers the rejection so the incident is not offered to this
    ambulance again (backfill). Other ambulances and the incident itself are
    unaffected. Returns 404 if the incident does not exist, and 409 if it is no
    longer requested to this ambulance (already taken, cancelled or rejected).
    """
    _verify_driver_ambulance_access(ambulance_id, driver, db)

    if not db.execute(
        text("SELECT 1 FROM incidents WHERE id = :iid"), {"iid": incident_id}
    ).fetchone():
        raise HTTPException(status_code=404, detail=f"Incident {incident_id} not found")

    deleted = db.execute(
        text("DELETE FROM inci_ambu WHERE incident_id = :iid AND ambulance_id = :aid"),
        {"iid": incident_id, "aid": ambulance_id},
    )
    if deleted.rowcount == 0:
        db.rollback()
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=f"Incident {incident_id} is no longer requested to ambulance {ambulance_id}.",
        )

    already = db.execute(
        text(
            "SELECT 1 FROM inci_ambu_cancelled "
            "WHERE incident_id = :iid AND ambulance_id = :aid"
        ),
        {"iid": incident_id, "aid": ambulance_id},
    ).fetchone()
    if not already:
        db.add(IncidentAmbulanceCancellation(incident_id=incident_id, ambulance_id=ambulance_id))
    db.commit()
    return {"incident_id": incident_id, "ambulance_id": ambulance_id, "status": "rejected"}


# ── POST /ambulances/{id}/incidents/{id}/cancel ───────────────────────────────

@router.post(
    "/{ambulance_id}/incidents/{incident_id}/cancel",
    response_model=IncidentOut,
    summary="Driver cancels an accepted incident (re-broadcasts to other ambulances)",
)
def cancel_ambulance_incident(
    ambulance_id: int,
    incident_id: int,
    driver: Driver = Depends(get_current_driver),
    db: Session = Depends(get_db),
):
    """
    Called by the driver when they want to cancel a mission they accepted.

    Effect:
    - Clears `assigned_ambulance_id` on the incident. An already-accepted hospital
      stays assigned (status goes to `'hospital_assigned'`); with no hospital yet the
      status returns to `'pending'`. Hospital broadcasts are never touched.
    - Marks all existing `inci_ambu` rows for this incident as deleted
      (removes them) and re-inserts candidate links for every *online, available*
      ambulance that is NOT the cancelling one, so they appear in those drivers'
      home-screen lists immediately.
    - Sets the cancelling ambulance `is_available = true` again.

    Returns HTTP 409 if the incident is already completed.
    Returns HTTP 403 if this ambulance is not the assigned ambulance for the incident.
    """
    ambulance = _verify_driver_ambulance_access(ambulance_id, driver, db)

    # Lock the incident row
    for_update = "" if (db.bind and db.bind.dialect.name == "sqlite") else "FOR UPDATE"
    locked_row = db.execute(
        text(
            f"SELECT id, status, assigned_ambulance_id "
            f"FROM incidents WHERE id = :iid {for_update}"
        ),
        {"iid": incident_id},
    ).fetchone()

    if not locked_row:
        raise HTTPException(status_code=404, detail=f"Incident {incident_id} not found")

    if locked_row.status == "completed":
        db.rollback()
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=f"Incident {incident_id} is already completed and cannot be cancelled.",
        )

    if locked_row.assigned_ambulance_id != ambulance_id:
        db.rollback()
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=f"Ambulance {ambulance_id} is not the assigned ambulance for incident {incident_id}.",
        )

    # 1. Unassign the ambulance only. If a hospital has already accepted the
    #    case it stays assigned (and its broadcast stays 'accepted'): the incident
    #    goes back to 'hospital_assigned' and is re-offered to ambulances, not to
    #    hospitals. With no hospital yet it simply returns to 'pending'.
    db.execute(
        text(
            "UPDATE incidents "
            "SET assigned_ambulance_id = NULL, "
            "    status = CASE WHEN assigned_hospital_id IS NOT NULL "
            "                  THEN 'hospital_assigned' ELSE 'pending' END "
            "WHERE id = :iid"
        ),
        {"iid": incident_id},
    )

    # 2. Free the ambulance
    db.execute(
        text("UPDATE ambulances SET is_available = true WHERE id = :aid"),
        {"aid": ambulance_id},
    )

    # 3. Clear any stale inci_ambu rows for this incident
    db.execute(
        text("DELETE FROM inci_ambu WHERE incident_id = :iid"),
        {"iid": incident_id},
    )

    # 3b. Remember who cancelled so the incident is never offered back to them
    #     (re-broadcast below, or the online / location backfill later).
    already = db.execute(
        text(
            "SELECT 1 FROM inci_ambu_cancelled "
            "WHERE incident_id = :iid AND ambulance_id = :aid"
        ),
        {"iid": incident_id, "aid": ambulance_id},
    ).fetchone()
    if not already:
        db.add(IncidentAmbulanceCancellation(incident_id=incident_id, ambulance_id=ambulance_id))
        db.flush()

    # 4. Re-broadcast with the same rules as incident creation: online,
    #    available, fresh GPS, within radius, nearest first, never anyone who
    #    already cancelled this incident.
    inc_pos = db.execute(
        text(
            "SELECT ST_Y(location::geometry) AS lat, ST_X(location::geometry) AS lng "
            "FROM incidents WHERE id = :iid"
        ),
        {"iid": incident_id},
    ).fetchone() if db.bind.dialect.name != "sqlite" else None
    try:
        if inc_pos is None:
            raise RuntimeError("no spatial support")
        candidate_rows = db.execute(
            text(
                "SELECT a.id FROM ambulances a "
                "WHERE a.is_online = true "
                "  AND a.is_available = true "
                "  AND a.location IS NOT NULL "
                "  AND a.location_updated_at >= NOW() - (:freshness || ' seconds')::interval "
                "  AND ST_DWithin(a.location, ST_MakePoint(:lng, :lat)::geography, :radius_m) "
                "  AND NOT EXISTS ( "
                "        SELECT 1 FROM inci_ambu_cancelled c "
                "        WHERE c.incident_id = :iid AND c.ambulance_id = a.id "
                "  ) "
                "ORDER BY ST_Distance(a.location, ST_MakePoint(:lng, :lat)::geography) ASC "
                "LIMIT :max_amb"
            ),
            {
                "iid": incident_id,
                "lat": inc_pos.lat,
                "lng": inc_pos.lng,
                "radius_m": settings.CANDIDATE_RADIUS_KM * 1000.0,
                "freshness": settings.LOCATION_FRESHNESS_SECONDS,
                "max_amb": settings.MAX_AMBULANCES_PER_INCIDENT,
            },
        ).fetchall()
    except Exception as exc:
        logger.warning(
            "[Ambulances] Spatial re-broadcast query failed (%s); falling back to non-spatial.", exc
        )
        try:
            # Fallback for non-spatial DB environments (e.g. SQLite unit tests)
            candidate_rows = db.execute(
                text(
                    "SELECT a.id FROM ambulances a "
                    "WHERE a.is_online = true AND a.is_available = true "
                    "  AND NOT EXISTS ( "
                    "        SELECT 1 FROM inci_ambu_cancelled c "
                    "        WHERE c.incident_id = :iid AND c.ambulance_id = a.id "
                    "  ) "
                    "LIMIT :max_amb"
                ),
                {"iid": incident_id, "max_amb": settings.MAX_AMBULANCES_PER_INCIDENT},
            ).fetchall()
        except Exception:
            candidate_rows = []

    for r in candidate_rows:
        db.add(IncidentAmbulance(incident_id=incident_id, ambulance_id=r.id))

    db.commit()
    db.expire_all()

    incident = db.get(Incident, incident_id)
    if not incident:
        raise HTTPException(status_code=404, detail="Incident not found after commit")
    return _build_incident_out(incident, db)


# ── GET /ambulances/{id}/assignment ───────────────────────────────────────────

@router.get(
    "/{ambulance_id}/assignment",
    response_model=AmbulanceAssignmentOut,
    summary="Get the active incident assigned to this ambulance",
)
def get_ambulance_assignment(ambulance_id: int, db: Session = Depends(get_db)):
    """
    Poll this from the driver's app every few seconds.

    Returns `assigned=false` when idle.  Otherwise returns the patient
    location and incident details; `hospital` is null until a hospital has
    accepted the case, so keep polling until it appears.
    """
    if not db.get(Ambulance, ambulance_id):
        raise HTTPException(status_code=404, detail=f"Ambulance {ambulance_id} not found")

    r = db.execute(
        text(
            "SELECT i.id, i.status, i.emergency_type, i.severity, i.symptoms, "
            "       i.victims, i.department_needed, i.created_at, "
            "       ST_Y(i.location::geometry) AS lat, ST_X(i.location::geometry) AS lng, "
            "       ST_Distance(i.location, a.location) / 1000.0 AS to_patient_km, "
            "       u.name AS user_name, u.phone AS user_phone, "
            "       h.id AS h_id, h.name AS h_name, h.departments AS h_departments, "
            "       ST_Y(h.location::geometry) AS h_lat, ST_X(h.location::geometry) AS h_lng, "
            "       ST_Distance(i.location, h.location) / 1000.0 AS patient_to_h_km "
            "FROM incidents i "
            "JOIN ambulances a ON a.id = i.assigned_ambulance_id "
            "LEFT JOIN users u ON u.id = i.user_id "
            "LEFT JOIN hospitals h ON h.id = i.assigned_hospital_id "
            "WHERE i.assigned_ambulance_id = :aid "
            "  AND i.status IN ('pending', 'hospital_assigned', 'ambulance_assigned') "
            "ORDER BY i.created_at DESC "
            "LIMIT 1"
        ),
        {"aid": ambulance_id},
    ).fetchone()

    if not r:
        return AmbulanceAssignmentOut(assigned=False)

    return AmbulanceAssignmentOut(
        assigned=True,
        incident_id=r.id,
        incident_status=r.status,
        emergency_type=r.emergency_type,
        severity=r.severity,
        symptoms=list(r.symptoms or []),
        victims=r.victims,
        department_needed=r.department_needed,
        created_at=r.created_at,
        patient_location=LocationSchema(lat=r.lat, lng=r.lng),
        patient=(
            AssignmentPatientOut(name=r.user_name, phone=r.user_phone)
            if r.user_name is not None else None
        ),
        hospital=(
            AssignmentHospitalOut(
                id=r.h_id,
                name=r.h_name,
                location=LocationSchema(lat=r.h_lat, lng=r.h_lng),
                departments=list(r.h_departments or []),
            )
            if r.h_id is not None else None
        ),
        distance_to_patient_km=(
            round(r.to_patient_km, 2) if r.to_patient_km is not None else None
        ),
        distance_patient_to_hospital_km=(
            round(r.patient_to_h_km, 2) if r.patient_to_h_km is not None else None
        ),
    )


def _hospital_location(hospital_id: int, db: Session) -> LocationSchema:
    """Resolve a hospital's geography column to plain lat/lng."""
    try:
        row = db.execute(
            text(
                "SELECT ST_Y(location::geometry) AS lat, "
                "       ST_X(location::geometry) AS lng "
                "FROM hospitals WHERE id = :id"
            ),
            {"id": hospital_id},
        ).fetchone()
        if row and row.lat is not None and row.lng is not None:
            return LocationSchema(lat=row.lat, lng=row.lng)
    except Exception:
        pass
    return LocationSchema(lat=0.0, lng=0.0)


def _normalize_symptoms(symptoms) -> list[str]:
    if not symptoms:
        return []
    if isinstance(symptoms, str):
        try:
            parsed = json.loads(symptoms)
            if isinstance(parsed, list):
                return [str(x) for x in parsed]
        except Exception:
            return [symptoms]
    if isinstance(symptoms, list):
        if len(symptoms) > 1 and symptoms[0] == "[" and symptoms[-1] == "]":
            try:
                parsed = json.loads("".join(symptoms))
                if isinstance(parsed, list):
                    return [str(x) for x in parsed]
            except Exception:
                pass
        return [str(x) for x in symptoms]
    return list(symptoms)


# ── GET /ambulances/{id}/incidents/{incident_id} ─────────────────────────────

@router.get(
    "/{ambulance_id}/incidents/{incident_id}",
    response_model=DriverIncidentDetailOut,
    summary="Get incident details for driver navigation",
)
def get_driver_incident_detail(
    ambulance_id: int,
    incident_id: int,
    driver: Driver = Depends(get_current_driver),
    db: Session = Depends(get_db),
):
    """
    Returns incident details for driver navigation.
    Requires that the authenticated driver is linked to the ambulance (403),
    and that the incident is assigned to this ambulance (403 or 404).
    """
    _verify_driver_ambulance_access(ambulance_id, driver, db)

    incident = db.get(Incident, incident_id)
    if not incident:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Incident {incident_id} not found",
        )

    if incident.assigned_ambulance_id != ambulance_id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=f"Incident {incident_id} is not assigned to ambulance {ambulance_id}.",
        )

    inc_loc = _incident_location(incident.id, db)

    assigned_hospital = None
    if incident.assigned_hospital_id:
        hosp = db.get(Hospital, incident.assigned_hospital_id)
        if hosp:
            h_loc = _hospital_location(hosp.id, db)
            assigned_hospital = DriverIncidentHospitalOut(
                id=hosp.id,
                name=hosp.name,
                location=h_loc,
            )

    return DriverIncidentDetailOut(
        id=incident.id,
        status=incident.status,
        severity=incident.severity,
        emergency_type=incident.emergency_type,
        symptoms=_normalize_symptoms(incident.symptoms),
        victims=incident.victims,
        department_needed=incident.department_needed,
        transcript=incident.transcript,
        location=inc_loc,
        created_at=incident.created_at,
        assigned_hospital=assigned_hospital,
    )


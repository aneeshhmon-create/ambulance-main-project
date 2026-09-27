"""
app/routers/incidents.py
────────────────────────
Core allocation logic: incident creation, hospital broadcast, ambulance
assignment, and race-safe hospital acceptance.

Endpoints
─────────
POST  /incidents
    – Create an incident, broadcast to nearby matching hospitals,
      auto-assign the nearest available ambulance.

POST  /incidents/{incident_id}/broadcasts/{broadcast_id}/accept
    – Hospital accepts the case (atomic / race-safe via SELECT FOR UPDATE).

GET   /incidents/{incident_id}
    – Full incident detail including broadcasts and statuses.

Design notes
────────────
Hospital broadcast radius : 15 km (BROADCAST_RADIUS_KM)
Ambulance assignment       : nearest available (no radius limit)
Race safety                : SELECT ... FOR UPDATE on the incident row inside
                             a serialized DB transaction — only one concurrent
                             ACCEPT can win; others get HTTP 409.
"""

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import text
from sqlalchemy.orm import Session

from app.db import get_db
from app.models.incident import Incident
from app.models.incident_broadcast import IncidentBroadcast
from app.models.ambulance import Ambulance
from app.schemas.incident import IncidentCreate, IncidentOut, BroadcastOut
from app.schemas.ambulance import AmbulanceOut
from app.schemas.hospital import LocationSchema

router = APIRouter()

BROADCAST_RADIUS_KM: float = 15.0  # hospitals within this radius get a broadcast


# ── Helpers ───────────────────────────────────────────────────────────────────

def _wkt_point(lat: float, lng: float) -> str:
    """Build a WKT POINT string (PostGIS expects lng lat order)."""
    return f"SRID=4326;POINT({lng} {lat})"


def _incident_location(incident_id: int, db: Session) -> LocationSchema:
    """Resolve an incident's geography column to plain lat/lng."""
    row = db.execute(
        text(
            "SELECT ST_Y(location::geometry) AS lat, "
            "       ST_X(location::geometry) AS lng "
            "FROM incidents WHERE id = :id"
        ),
        {"id": incident_id},
    ).fetchone()
    return LocationSchema(lat=row.lat, lng=row.lng)


def _ambulance_location(ambulance_id: int, db: Session) -> LocationSchema | None:
    """Resolve an ambulance's geography column to plain lat/lng."""
    row = db.execute(
        text(
            "SELECT ST_Y(location::geometry) AS lat, "
            "       ST_X(location::geometry) AS lng "
            "FROM ambulances WHERE id = :id AND location IS NOT NULL"
        ),
        {"id": ambulance_id},
    ).fetchone()
    if not row:
        return None
    return LocationSchema(lat=row.lat, lng=row.lng)


def _build_incident_out(incident: Incident, db: Session) -> IncidentOut:
    """
    Assemble a full IncidentOut from an ORM Incident, resolving geography
    columns and enriching with broadcasts + assigned ambulance.
    """
    # Resolve location
    loc = _incident_location(incident.id, db)

    # Broadcasts
    broadcasts_out = [
        BroadcastOut(
            id=b.id,
            incident_id=b.incident_id,
            target_type=b.target_type,
            target_id=b.target_id,
            status=b.status,
            sent_at=b.sent_at,
            responded_at=b.responded_at,
        )
        for b in incident.broadcasts
    ]

    # Assigned ambulance (optional)
    ambulance_out: AmbulanceOut | None = None
    if incident.assigned_ambulance_id is not None:
        amb = db.get(Ambulance, incident.assigned_ambulance_id)
        if amb:
            amb_loc = _ambulance_location(amb.id, db)
            ambulance_out = AmbulanceOut(
                id=amb.id,
                driver_name=amb.driver_name,
                driver_phone=amb.driver_phone,
                location=amb_loc,
                is_available=amb.is_available,
            )

    return IncidentOut(
        id=incident.id,
        user_id=incident.user_id,
        location=loc,
        emergency_type=incident.emergency_type,
        severity=incident.severity,
        symptoms=incident.symptoms or [],
        victims=incident.victims,
        department_needed=incident.department_needed,
        status=incident.status,
        assigned_hospital_id=incident.assigned_hospital_id,
        assigned_ambulance_id=incident.assigned_ambulance_id,
        created_at=incident.created_at,
        broadcasts=broadcasts_out,
        assigned_ambulance=ambulance_out,
    )


# ── POST /incidents ───────────────────────────────────────────────────────────

@router.post("", response_model=IncidentOut, status_code=201, summary="Create an incident")
def create_incident(body: IncidentCreate, db: Session = Depends(get_db)):
    """
    Creates an incident, then atomically:

    1. Finds all *active* hospitals within BROADCAST_RADIUS_KM that have
       `department_needed` in their departments array (PostGIS ST_DWithin).
       Creates one `incident_broadcasts` row per hospital with status='pending'.

    2. Finds the nearest *available* ambulance (no radius limit, ORDER BY
       ST_Distance LIMIT 1) and directly assigns it, setting
       ambulance.is_available=False.

    Returns the created incident including broadcasts and assigned ambulance.
    """
    # ── 1. Create the incident row ────────────────────────────────────────────
    incident = Incident(
        user_id=body.user_id,
        location=_wkt_point(body.lat, body.lng),
        emergency_type=body.emergency_type,
        severity=body.severity,
        symptoms=body.symptoms,
        victims=body.victims,
        department_needed=body.department_needed,
        status="pending",
    )
    db.add(incident)
    db.flush()  # get incident.id without committing yet

    # ── 2. Find matching hospitals within broadcast radius ────────────────────
    if body.department_needed:
        radius_m = BROADCAST_RADIUS_KM * 1000.0
        hospital_rows = db.execute(
            text(
                "SELECT h.id "
                "FROM hospitals h "
                "WHERE h.is_active = true "
                "  AND :dept = ANY(h.departments) "
                "  AND ST_DWithin("
                "        h.location,"
                "        ST_MakePoint(:lng, :lat)::geography,"
                "        :radius_m"
                "      ) "
                "ORDER BY ST_Distance(h.location, ST_MakePoint(:lng, :lat)::geography) ASC"
            ),
            {
                "dept": body.department_needed,
                "lat": body.lat,
                "lng": body.lng,
                "radius_m": radius_m,
            },
        ).fetchall()
    else:
        hospital_rows = []

    # Create a broadcast record for each matching hospital
    for row in hospital_rows:
        broadcast = IncidentBroadcast(
            incident_id=incident.id,
            target_type="hospital",
            target_id=row.id,
            status="pending",
        )
        db.add(broadcast)

    # ── 3. Find nearest available ambulance and assign it ─────────────────────
    amb_row = db.execute(
        text(
            "SELECT a.id "
            "FROM ambulances a "
            "WHERE a.is_available = true "
            "  AND a.location IS NOT NULL "
            "ORDER BY ST_Distance(a.location, ST_MakePoint(:lng, :lat)::geography) ASC "
            "LIMIT 1"
        ),
        {"lat": body.lat, "lng": body.lng},
    ).fetchone()

    if amb_row:
        incident.assigned_ambulance_id = amb_row.id
        # Mark the ambulance as unavailable
        ambulance = db.get(Ambulance, amb_row.id)
        if ambulance:
            ambulance.is_available = False

    # ── 4. Commit everything atomically ───────────────────────────────────────
    db.commit()
    db.refresh(incident)

    return _build_incident_out(incident, db)


# ── POST /incidents/{incident_id}/broadcasts/{broadcast_id}/accept ─────────────

@router.post(
    "/{incident_id}/broadcasts/{broadcast_id}/accept",
    response_model=IncidentOut,
    summary="Hospital accepts an incident broadcast (race-safe)",
)
def accept_broadcast(
    incident_id: int,
    broadcast_id: int,
    db: Session = Depends(get_db),
):
    """
    Called by a hospital to accept an incident broadcast.

    **Race safety**: Uses `SELECT ... FOR UPDATE` inside a transaction so that
    if two hospitals call this endpoint simultaneously, only the first commit
    wins. The second sees status != 'pending' and gets HTTP 409.

    On success:
    - incident.status           → 'hospital_assigned'
    - incident.assigned_hospital_id → hospital from the broadcast
    - this broadcast.status     → 'accepted', responded_at=now()
    - all OTHER broadcasts      → status='expired'

    Returns HTTP 409 if the incident is no longer pending.
    """
    # ── Validate the broadcast exists and belongs to this incident ────────────
    broadcast = db.get(IncidentBroadcast, broadcast_id)
    if not broadcast or broadcast.incident_id != incident_id:
        raise HTTPException(
            status_code=404,
            detail=f"Broadcast {broadcast_id} not found for incident {incident_id}",
        )
    if broadcast.target_type != "hospital":
        raise HTTPException(
            status_code=400,
            detail="Only hospital broadcasts can be accepted via this endpoint",
        )

    hospital_id = broadcast.target_id

    # ── Atomic accept: lock the incident row, then check-and-set ─────────────
    # SELECT ... FOR UPDATE acquires a row-level write lock.
    # Concurrent transactions block here until the first one commits/rolls back.
    # This guarantees at-most-one winner without application-level locking.
    locked_row = db.execute(
        text(
            "SELECT id, status "
            "FROM incidents "
            "WHERE id = :incident_id "
            "FOR UPDATE"         # row-level lock
        ),
        {"incident_id": incident_id},
    ).fetchone()

    if not locked_row:
        raise HTTPException(status_code=404, detail=f"Incident {incident_id} not found")

    if locked_row.status != "pending":
        # Someone else already accepted — release the lock and inform caller.
        db.rollback()
        raise HTTPException(
            status_code=409,
            detail=(
                f"Incident {incident_id} is no longer pending "
                f"(current status: '{locked_row.status}'). "
                "Another hospital has already accepted this case."
            ),
        )

    # ── We won the race — update everything inside the same transaction ───────

    # Mark this broadcast accepted
    db.execute(
        text(
            "UPDATE incident_broadcasts "
            "SET status = 'accepted', responded_at = NOW() "
            "WHERE id = :bid"
        ),
        {"bid": broadcast_id},
    )

    # Expire all OTHER pending broadcasts for this incident
    db.execute(
        text(
            "UPDATE incident_broadcasts "
            "SET status = 'expired', responded_at = NOW() "
            "WHERE incident_id = :incident_id "
            "  AND id != :bid "
            "  AND status = 'pending'"
        ),
        {"incident_id": incident_id, "bid": broadcast_id},
    )

    # Update the incident
    db.execute(
        text(
            "UPDATE incidents "
            "SET status = 'hospital_assigned', "
            "    assigned_hospital_id = :hospital_id "
            "WHERE id = :incident_id"
        ),
        {"hospital_id": hospital_id, "incident_id": incident_id},
    )

    db.commit()

    # Reload ORM state
    db.expire_all()
    incident = db.get(Incident, incident_id)
    if not incident:
        raise HTTPException(status_code=404, detail="Incident disappeared after commit")

    return _build_incident_out(incident, db)


# ── GET /incidents/{incident_id} ──────────────────────────────────────────────

@router.get(
    "/{incident_id}",
    response_model=IncidentOut,
    summary="Get full incident detail with broadcasts",
)
def get_incident(incident_id: int, db: Session = Depends(get_db)):
    """
    Return full detail for a single incident, including all broadcast records
    and the assigned ambulance. Useful for polling and debugging.
    """
    incident = db.get(Incident, incident_id)
    if not incident:
        raise HTTPException(status_code=404, detail=f"Incident {incident_id} not found")
    return _build_incident_out(incident, db)

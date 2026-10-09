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

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import text
from sqlalchemy.orm import Session

from app.db import get_db
from app.models.ambulance import Ambulance
from app.schemas.ambulance import (
    AmbulanceCreate,
    AmbulanceOut,
    AmbulanceLocationUpdate,
    AmbulanceNearestOut,
    AmbulanceAssignmentOut,
    AssignmentHospitalOut,
    AssignmentPatientOut,
)
from app.schemas.hospital import LocationSchema

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
        result = db.execute(
            text(
                "SELECT ST_Y(location::geometry) AS lat, "
                "       ST_X(location::geometry) AS lng "
                "FROM ambulances WHERE id = :id"
            ),
            {"id": a.id},
        ).fetchone()
        loc = LocationSchema(lat=result.lat, lng=result.lng)

    return AmbulanceOut(
        id=a.id,
        driver_name=a.driver_name,
        driver_phone=a.driver_phone,
        location=loc,
        is_available=a.is_available,
    )


# ── POST /ambulances ───────────────────────────────────────────────────────────

@router.post("", response_model=AmbulanceOut, status_code=201, summary="Register an ambulance")
def create_ambulance(body: AmbulanceCreate, db: Session = Depends(get_db)):
    """Register a new ambulance with driver details and starting location."""
    ambulance = Ambulance(
        driver_name=body.driver_name,
        driver_phone=body.driver_phone,
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
            "SELECT a.id, a.driver_name, a.driver_phone, a.is_available, "
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
            driver_name=r.driver_name,
            driver_phone=r.driver_phone,
            location=LocationSchema(lat=r.lat, lng=r.lng) if r.lat is not None else None,
            is_available=r.is_available,
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
            "SELECT a.id, a.driver_name, a.driver_phone, a.is_available, "
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
        driver_name=row.driver_name,
        driver_phone=row.driver_phone,
        location=LocationSchema(lat=row.lat, lng=row.lng),
        is_available=row.is_available,
        distance_m=row.distance_m,
    )


# ── PATCH /ambulances/{id}/location ───────────────────────────────────────────

@router.patch(
    "/{ambulance_id}/location",
    response_model=AmbulanceOut,
    summary="Update an ambulance's GPS location",
)
def update_ambulance_location(
    ambulance_id: int,
    body: AmbulanceLocationUpdate,
    db: Session = Depends(get_db),
):
    """
    Update the current position of an ambulance.
    Called repeatedly from the driver's phone GPS.
    """
    ambulance = db.get(Ambulance, ambulance_id)
    if not ambulance:
        raise HTTPException(status_code=404, detail=f"Ambulance {ambulance_id} not found")

    ambulance.location = _wkt_point(body.location.lat, body.location.lng)
    db.commit()
    db.refresh(ambulance)
    return _ambulance_orm_to_out(ambulance, db)


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

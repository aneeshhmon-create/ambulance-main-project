"""
app/routers/hospitals.py
────────────────────────
CRUD + geo-search endpoints for the Hospital resource.

Endpoints
─────────
POST   /hospitals                         – register a hospital
GET    /hospitals                         – list all hospitals
GET    /hospitals/nearby                  – geo-search (must come before /{id})
GET    /hospitals/{id}                    – fetch one hospital
PATCH  /hospitals/{id}                    – update departments / is_active

Notes on geography
──────────────────
• The `location` column is GEOGRAPHY(Point, 4326).
• We store it as WKT:  ST_GeomFromText('POINT(lng lat)', 4326)
• We read it back with ST_X / ST_Y to return plain lat/lng JSON.
• ST_DWithin on GEOGRAPHY uses metres, so radius_km * 1000.
• ST_Distance on GEOGRAPHY also returns metres.
"""

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import text
from sqlalchemy.orm import Session

from app.db import get_db
from app.models.hospital import Hospital
from app.schemas.hospital import (
    HospitalCreate,
    HospitalOut,
    HospitalUpdate,
    HospitalNearbyOut,
    LocationSchema,
)

router = APIRouter()


# ── Helpers ───────────────────────────────────────────────────────────────────

def _wkt_point(lat: float, lng: float) -> str:
    """Build a WKT POINT string from lat/lng (note PostGIS is lng lat order)."""
    return f"SRID=4326;POINT({lng} {lat})"


def _row_to_location(row) -> LocationSchema:
    """
    GeoAlchemy2 returns a WKBElement; call ST_X/ST_Y via raw SQL instead,
    so we keep things simple by reading back from the DB in query results.
    This helper is used when we already have x/y from a SELECT.
    """
    return LocationSchema(lat=row.lat, lng=row.lng)


def _hospital_orm_to_out(h: Hospital, db: Session) -> HospitalOut:
    """
    Convert a Hospital ORM row to HospitalOut, resolving the geography column
    to plain lat/lng by asking PostGIS for the coordinates.
    """
    result = db.execute(
        text("SELECT ST_Y(location::geometry) AS lat, ST_X(location::geometry) AS lng "
             "FROM hospitals WHERE id = :id"),
        {"id": h.id},
    ).fetchone()
    loc = LocationSchema(lat=result.lat, lng=result.lng)
    return HospitalOut(
        id=h.id,
        name=h.name,
        location=loc,
        departments=h.departments,
        is_active=h.is_active,
        created_at=h.created_at,
    )


# ── POST /hospitals ────────────────────────────────────────────────────────────

@router.post("", response_model=HospitalOut, status_code=201, summary="Register a hospital")
def create_hospital(body: HospitalCreate, db: Session = Depends(get_db)):
    """Register a new hospital with name, location (lat/lng) and departments."""
    hospital = Hospital(
        name=body.name,
        location=_wkt_point(body.location.lat, body.location.lng),
        departments=body.departments,
    )
    db.add(hospital)
    db.commit()
    db.refresh(hospital)
    return _hospital_orm_to_out(hospital, db)


# ── GET /hospitals ─────────────────────────────────────────────────────────────

@router.get("", response_model=list[HospitalOut], summary="List all hospitals")
def list_hospitals(
    skip: int = Query(0, ge=0),
    limit: int = Query(100, ge=1, le=500),
    db: Session = Depends(get_db),
):
    """Return a paginated list of all hospitals."""
    rows = db.execute(
        text(
            "SELECT h.id, h.name, h.departments, h.is_active, h.created_at, "
            "       ST_Y(h.location::geometry) AS lat, "
            "       ST_X(h.location::geometry) AS lng "
            "FROM hospitals h "
            "ORDER BY h.id "
            "LIMIT :limit OFFSET :skip"
        ),
        {"limit": limit, "skip": skip},
    ).fetchall()

    return [
        HospitalOut(
            id=r.id,
            name=r.name,
            location=LocationSchema(lat=r.lat, lng=r.lng),
            departments=list(r.departments),
            is_active=r.is_active,
            created_at=r.created_at,
        )
        for r in rows
    ]


# ── GET /hospitals/nearby ──────────────────────────────────────────────────────
# IMPORTANT: this route must be declared BEFORE /hospitals/{id} so FastAPI
# does not try to parse "nearby" as an integer id.

@router.get(
    "/nearby",
    response_model=list[HospitalNearbyOut],
    summary="Find nearby hospitals with a given department",
)
def nearby_hospitals(
    lat: float = Query(..., ge=-90.0, le=90.0, description="Query latitude"),
    lng: float = Query(..., ge=-180.0, le=180.0, description="Query longitude"),
    department: str = Query(..., min_length=1, description="Required department name"),
    radius_km: float = Query(10.0, gt=0, le=500, description="Search radius in km"),
    db: Session = Depends(get_db),
):
    """
    Return active hospitals within *radius_km* that have *department* in
    their departments array, ordered by distance (closest first).

    Uses PostGIS ST_DWithin (index-friendly) for filtering and ST_Distance
    for the returned distance value.
    """
    radius_m = radius_km * 1000.0
    rows = db.execute(
        text(
            "SELECT h.id, h.name, h.departments, h.is_active, h.created_at, "
            "       ST_Y(h.location::geometry)  AS lat, "
            "       ST_X(h.location::geometry)  AS lng, "
            "       ST_Distance(h.location, ST_MakePoint(:lng, :lat)::geography) AS distance_m "
            "FROM hospitals h "
            "WHERE h.is_active = true "
            "  AND :dept = ANY(h.departments) "
            "  AND ST_DWithin(h.location, ST_MakePoint(:lng, :lat)::geography, :radius_m) "
            "ORDER BY distance_m ASC"
        ),
        {"lat": lat, "lng": lng, "dept": department, "radius_m": radius_m},
    ).fetchall()

    return [
        HospitalNearbyOut(
            id=r.id,
            name=r.name,
            location=LocationSchema(lat=r.lat, lng=r.lng),
            departments=list(r.departments),
            is_active=r.is_active,
            created_at=r.created_at,
            distance_m=r.distance_m,
        )
        for r in rows
    ]


# ── GET /hospitals/{id} ────────────────────────────────────────────────────────

@router.get("/{hospital_id}", response_model=HospitalOut, summary="Get a hospital by ID")
def get_hospital(hospital_id: int, db: Session = Depends(get_db)):
    """Fetch a single hospital by its primary-key ID."""
    hospital = db.get(Hospital, hospital_id)
    if not hospital:
        raise HTTPException(status_code=404, detail=f"Hospital {hospital_id} not found")
    return _hospital_orm_to_out(hospital, db)


# ── PATCH /hospitals/{id} ──────────────────────────────────────────────────────

@router.patch("/{hospital_id}", response_model=HospitalOut, summary="Update a hospital")
def update_hospital(
    hospital_id: int,
    body: HospitalUpdate,
    db: Session = Depends(get_db),
):
    """
    Partially update a hospital.  Only `departments` and `is_active` may be
    changed through this endpoint.
    """
    hospital = db.get(Hospital, hospital_id)
    if not hospital:
        raise HTTPException(status_code=404, detail=f"Hospital {hospital_id} not found")

    if body.departments is not None:
        hospital.departments = body.departments
    if body.is_active is not None:
        hospital.is_active = body.is_active

    db.commit()
    db.refresh(hospital)
    return _hospital_orm_to_out(hospital, db)

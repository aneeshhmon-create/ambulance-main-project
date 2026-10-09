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

import os
import shutil
import tempfile
import logging

from fastapi import APIRouter, Depends, HTTPException, UploadFile, File, Form, status
from sqlalchemy import text
from sqlalchemy.orm import Session

from app.db import get_db
from app.models.incident import Incident
from app.models.incident_broadcast import IncidentBroadcast
from app.models.ambulance import Ambulance
from app.schemas.incident import IncidentCreate, IncidentOut, BroadcastOut
from app.schemas.ambulance import AmbulanceOut
from app.schemas.hospital import LocationSchema
from app.services.stt_service import transcribe_audio
from app.services.extraction_service import extract_severity

logger = logging.getLogger(__name__)

router = APIRouter()

BROADCAST_RADIUS_KM: float = 15.0  # hospitals within this radius get a broadcast


# ── Helpers ───────────────────────────────────────────────────────────────────

def _wkt_point(lat: float, lng: float) -> str:
    """Build a WKT POINT string (PostGIS expects lng lat order)."""
    return f"SRID=4326;POINT({lng} {lat})"


def _incident_location(incident_id: int, db: Session) -> LocationSchema:
    """Resolve an incident's geography column to plain lat/lng."""
    try:
        row = db.execute(
            text(
                "SELECT ST_Y(location::geometry) AS lat, "
                "       ST_X(location::geometry) AS lng "
                "FROM incidents WHERE id = :id"
            ),
            {"id": incident_id},
        ).fetchone()
        if row and row.lat is not None and row.lng is not None:
            return LocationSchema(lat=row.lat, lng=row.lng)
    except Exception:
        pass
    return LocationSchema(lat=0.0, lng=0.0)


def _ambulance_location(ambulance_id: int, db: Session) -> LocationSchema | None:
    """Resolve an ambulance's geography column to plain lat/lng."""
    try:
        row = db.execute(
            text(
                "SELECT ST_Y(location::geometry) AS lat, "
                "       ST_X(location::geometry) AS lng "
                "FROM ambulances WHERE id = :id AND location IS NOT NULL"
            ),
            {"id": ambulance_id},
        ).fetchone()
        if row and row.lat is not None and row.lng is not None:
            return LocationSchema(lat=row.lat, lng=row.lng)
    except Exception:
        pass
    return None


def _build_incident_out(
    incident: Incident,
    db: Session,
    transcript: str | None = None,
    extracted_data: dict | None = None,
) -> IncidentOut:
    """
    Assemble a full IncidentOut from an ORM Incident, resolving geography
    columns and enriching with broadcasts + assigned ambulance + AI extraction data.
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
        transcript=transcript or incident.transcript,
        extracted_data=extracted_data,
    )


def _create_incident_core(
    lat: float,
    lng: float,
    emergency_type: str | None,
    severity: str | None,
    symptoms: list[str],
    victims: int,
    department_needed: str | None,
    user_id: int | None,
    db: Session,
    transcript: str | None = None,
    extracted_data: dict | None = None,
) -> IncidentOut:
    """
    Creates an incident row, broadcasts to nearby matching hospitals,
    and auto-assigns the nearest ambulance.
    """
    # ── 1. Create the incident row ────────────────────────────────────────────
    incident = Incident(
        user_id=user_id,
        location=_wkt_point(lat, lng),
        emergency_type=emergency_type,
        severity=severity,
        symptoms=symptoms,
        victims=victims,
        department_needed=department_needed,
        transcript=transcript,
        status="pending",
    )
    db.add(incident)
    db.flush()  # get incident.id without committing yet

    # ── 2. Find matching hospitals within broadcast radius ────────────────────
    hospital_rows = []
    if department_needed:
        radius_m = BROADCAST_RADIUS_KM * 1000.0
        try:
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
                    "dept": department_needed,
                    "lat": lat,
                    "lng": lng,
                    "radius_m": radius_m,
                },
            ).fetchall()
        except Exception as exc:
            logger.warning("[Incidents] Spatial hospital query failed (%s); fallback to non-spatial department filter.", exc)
            hospital_rows = db.execute(
                text(
                    "SELECT h.id FROM hospitals h "
                    "WHERE h.is_active = true AND :dept = ANY(h.departments)"
                ),
                {"dept": department_needed},
            ).fetchall()

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
    amb_row = None
    try:
        amb_row = db.execute(
            text(
                "SELECT a.id "
                "FROM ambulances a "
                "WHERE a.is_available = true "
                "  AND a.location IS NOT NULL "
                "ORDER BY ST_Distance(a.location, ST_MakePoint(:lng, :lat)::geography) ASC "
                "LIMIT 1"
            ),
            {"lat": lat, "lng": lng},
        ).fetchone()
    except Exception as exc:
        logger.warning("[Incidents] Spatial ambulance query failed (%s); fallback to first available ambulance.", exc)
        amb_row = db.execute(
            text("SELECT a.id FROM ambulances a WHERE a.is_available = true LIMIT 1")
        ).fetchone()

    if amb_row:
        incident.assigned_ambulance_id = amb_row.id
        ambulance = db.get(Ambulance, amb_row.id)
        if ambulance:
            ambulance.is_available = False

    # ── 4. Commit everything atomically ───────────────────────────────────────
    db.commit()
    db.refresh(incident)

    return _build_incident_out(
        incident,
        db,
        transcript=transcript,
        extracted_data=extracted_data,
    )


# ── POST /incidents ───────────────────────────────────────────────────────────

@router.post(
    "",
    response_model=IncidentOut,
    status_code=201,
    summary="Create an incident from audio call (STT + LLM extraction + allocation)",
)
def create_incident_from_audio(
    audio_file: UploadFile = File(..., description="Audio recording of emergency call"),
    lat: float = Form(..., ge=-90.0, le=90.0, description="Caller latitude"),
    lng: float = Form(..., ge=-180.0, le=180.0, description="Caller longitude"),
    user_id: int | None = Form(None, description="Optional reporting user ID"),
    db: Session = Depends(get_db),
):
    """
    Real emergency dispatch intake flow:
    1. Receives audio stream / file from caller
    2. Transcribes speech via Whisper STT (handles Malayalam, English, and Code-switching)
    3. Extracts severity, emergency type, symptoms, victim count, and needed department via Gemini LLM
    4. Creates incident and broadcasts to matching nearby hospitals
    5. Auto-assigns nearest available ambulance
    6. Returns incident record enriched with transcription and extracted AI fields.
    """
    tmp_path = None
    try:
        suffix = os.path.splitext(audio_file.filename or "")[1] or ".ogg"
        with tempfile.NamedTemporaryFile(delete=False, suffix=suffix) as tmp:
            shutil.copyfileobj(audio_file.file, tmp)
            tmp_path = tmp.name

        # a. Speech to text
        stt_result = transcribe_audio(tmp_path)
        transcript = stt_result.get("transcript", "")

        # b. Severity & department extraction
        extracted = extract_severity(transcript)

        # c. & d. Create incident & dispatch
        return _create_incident_core(
            lat=lat,
            lng=lng,
            emergency_type=extracted.get("emergency_type"),
            severity=extracted.get("severity"),
            symptoms=extracted.get("symptoms", []),
            victims=extracted.get("victims", 1),
            department_needed=extracted.get("department_needed"),
            user_id=user_id,
            db=db,
            transcript=transcript,
            extracted_data=extracted,
        )
    except Exception as exc:
        logger.exception("[Incidents] Incident creation failed: %s", exc)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Incident creation failed: {exc}",
        )
    finally:
        if tmp_path and os.path.exists(tmp_path):
            try:
                os.unlink(tmp_path)
            except OSError:
                pass


# ── POST /incidents/manual ────────────────────────────────────────────────────

@router.post(
    "/manual",
    response_model=IncidentOut,
    status_code=201,
    summary="Create an incident manually via JSON (demo fallback / direct testing)",
)
def create_incident_manual(body: IncidentCreate, db: Session = Depends(get_db)):
    """
    Manual JSON-based incident creation without running audio STT / extraction.
    Used for fast testing and as a demo fallback if live audio recording misbehaves.
    """
    return _create_incident_core(
        lat=body.lat,
        lng=body.lng,
        emergency_type=body.emergency_type,
        severity=body.severity,
        symptoms=body.symptoms,
        victims=body.victims,
        department_needed=body.department_needed,
        user_id=body.user_id,
        db=db,
    )


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

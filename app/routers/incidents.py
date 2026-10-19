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

POST  /incidents/{incident_id}/complete
    – Mark the case finished and free its ambulance.

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

from app.core.config import settings
from app.core.security import get_current_hospital_account
from app.db import get_db
from app.models.hospital_account import HospitalAccount
from app.models.incident import Incident
from app.models.incident_broadcast import IncidentBroadcast
from app.models.ambulance import Ambulance
from app.models.incident_ambulance import IncidentAmbulance
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
                registration_number=amb.registration_number,
                vehicle_type=amb.vehicle_type,
                location=amb_loc,
                is_available=amb.is_available,
                is_online=amb.is_online,
                location_updated_at=amb.location_updated_at,
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
            try:
                hospital_rows = db.execute(
                    text(
                        "SELECT h.id FROM hospitals h "
                        "WHERE h.is_active = true AND :dept = ANY(h.departments)"
                    ),
                    {"dept": department_needed},
                ).fetchall()
            except Exception:
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

    # ── 3. Find candidate ambulances (online, available, fresh GPS, within radius) ───
    radius_m = settings.CANDIDATE_RADIUS_KM * 1000.0
    freshness_sec = settings.LOCATION_FRESHNESS_SECONDS
    max_amb = settings.MAX_AMBULANCES_PER_INCIDENT
    amb_rows = []
    try:
        amb_rows = db.execute(
            text(
                "SELECT a.id "
                "FROM ambulances a "
                "WHERE a.is_online = true "
                "  AND a.is_available = true "
                "  AND a.location IS NOT NULL "
                "  AND a.location_updated_at IS NOT NULL "
                "  AND a.location_updated_at >= NOW() - (:freshness || ' seconds')::interval "
                "  AND ST_DWithin("
                "        a.location,"
                "        ST_MakePoint(:lng, :lat)::geography,"
                "        :radius_m"
                "      ) "
                "ORDER BY ST_Distance(a.location, ST_MakePoint(:lng, :lat)::geography) ASC "
                "LIMIT :max_amb"
            ),
            {
                "lat": lat,
                "lng": lng,
                "radius_m": radius_m,
                "freshness": freshness_sec,
                "max_amb": max_amb,
            },
        ).fetchall()
    except Exception as exc:
        logger.warning("[Incidents] Spatial candidate ambulance query failed (%s); checking fallback.", exc)
        try:
            # Fallback for non-spatial DB environments (e.g. SQLite unit tests)
            amb_rows = db.execute(
                text(
                    "SELECT a.id FROM ambulances a "
                    "WHERE a.is_online = true AND a.is_available = true "
                    "LIMIT :max_amb"
                ),
                {"max_amb": max_amb},
            ).fetchall()
        except Exception:
            amb_rows = []

    for r in amb_rows:
        candidate_link = IncidentAmbulance(
            incident_id=incident.id,
            ambulance_id=r.id,
        )
        db.add(candidate_link)

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
    for_update = "" if (db.bind and db.bind.dialect.name == "sqlite") else "FOR UPDATE"
    locked_row = db.execute(
        text(
            f"SELECT id, status, assigned_hospital_id, assigned_ambulance_id "
            f"FROM incidents "
            f"WHERE id = :incident_id "
            f"{for_update}"
        ),
        {"incident_id": incident_id},
    ).fetchone()

    if not locked_row:
        raise HTTPException(status_code=404, detail=f"Incident {incident_id} not found")

    if locked_row.status == "completed" or locked_row.assigned_hospital_id is not None:
        # Someone else already accepted or case is completed — release lock and inform caller.
        db.rollback()
        raise HTTPException(
            status_code=409,
            detail=(
                f"Incident {incident_id} can no longer be accepted by a hospital "
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

    # Update the incident status: if ambulance is already assigned, keep ambulance_assigned
    next_status = (
        "ambulance_assigned"
        if locked_row.assigned_ambulance_id is not None
        else "hospital_assigned"
    )
    db.execute(
        text(
            "UPDATE incidents "
            "SET status = :next_status, "
            "    assigned_hospital_id = :hospital_id "
            "WHERE id = :incident_id"
        ),
        {
            "hospital_id": hospital_id,
            "incident_id": incident_id,
            "next_status": next_status,
        },
    )

    db.commit()

    # Reload ORM state
    db.expire_all()
    incident = db.get(Incident, incident_id)
    if not incident:
        raise HTTPException(status_code=404, detail="Incident disappeared after commit")

    return _build_incident_out(incident, db)


# ── POST /incidents/{incident_id}/broadcasts/{broadcast_id}/decline ───────────

@router.post(
    "/{incident_id}/broadcasts/{broadcast_id}/decline",
    summary="Hospital declines an incident broadcast",
)
def decline_broadcast(
    incident_id: int,
    broadcast_id: int,
    db: Session = Depends(get_db),
    account: HospitalAccount = Depends(get_current_hospital_account),
):
    """
    Called by a hospital to reject a case it received.

    Only the hospital the broadcast was addressed to may decline it. The
    incident itself stays pending so other hospitals can still accept it.
    Returns 409 if the broadcast was already answered or expired (for example
    another hospital accepted the case first).
    """
    broadcast = db.get(IncidentBroadcast, broadcast_id)
    if (
        not broadcast
        or broadcast.incident_id != incident_id
        or broadcast.target_type != "hospital"
    ):
        raise HTTPException(
            status_code=404,
            detail=f"Broadcast {broadcast_id} not found for incident {incident_id}",
        )
    if broadcast.target_id != account.hospital_id:
        raise HTTPException(
            status_code=403,
            detail="This broadcast was not sent to your hospital.",
        )

    # Check-and-set in one statement so a concurrent accept/expiry can't be overwritten.
    result = db.execute(
        text(
            "UPDATE incident_broadcasts "
            "SET status = 'declined', responded_at = NOW() "
            "WHERE id = :bid AND status = 'pending'"
        ),
        {"bid": broadcast_id},
    )
    db.commit()
    if result.rowcount == 0:
        db.expire_all()
        current = db.get(IncidentBroadcast, broadcast_id)
        raise HTTPException(
            status_code=409,
            detail=(
                f"This case can no longer be declined "
                f"(current status: '{current.status if current else 'unknown'}')."
            ),
        )
    return {"incident_id": incident_id, "broadcast_id": broadcast_id, "status": "declined"}


# ── POST /incidents/{incident_id}/complete ────────────────────────────────────

@router.post(
    "/{incident_id}/complete",
    response_model=IncidentOut,
    summary="Mark an incident completed and release its ambulance",
)
def complete_incident(incident_id: int, db: Session = Depends(get_db)):
    """
    Called by the ambulance app when the patient has been handed over.
    Sets status='completed' and makes the ambulance available again.
    Idempotent: completing an already-completed incident just returns it.
    """
    row = db.execute(
        text("SELECT id, status, assigned_ambulance_id FROM incidents WHERE id = :id FOR UPDATE"),
        {"id": incident_id},
    ).fetchone()
    if not row:
        raise HTTPException(status_code=404, detail=f"Incident {incident_id} not found")

    if row.status != "completed":
        db.execute(
            text("UPDATE incidents SET status = 'completed' WHERE id = :id"),
            {"id": incident_id},
        )
        db.execute(
            text(
                "UPDATE incident_broadcasts SET status = 'expired', responded_at = NOW() "
                "WHERE incident_id = :id AND status = 'pending'"
            ),
            {"id": incident_id},
        )
        if row.assigned_ambulance_id is not None:
            db.execute(
                text("UPDATE ambulances SET is_available = true WHERE id = :aid"),
                {"aid": row.assigned_ambulance_id},
            )
        db.commit()

    db.expire_all()
    return _build_incident_out(db.get(Incident, incident_id), db)


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

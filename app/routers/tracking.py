"""
app/routers/tracking.py
───────────────────────
Read-only endpoint behind the user app's live tracking map.

GET /incidents/{incident_id}/tracking
  Requires a signed-in user. The incident must belong to that user; incidents
  with no owner (e.g. created through the dev scripts) are visible to any
  signed-in user so they can be tested. Returns the incident summary, the
  assigned hospital (null until a hospital accepts) and the assigned ambulance
  with its last reported GPS position (null while no ambulance is assigned).
"""

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from app.core.security import get_current_user
from app.db import get_db
from app.models.ambulance import Ambulance
from app.models.hospital import Hospital
from app.models.incident import Incident
from app.models.user import User
from app.routers.ambulances import (
    _ambulance_orm_to_out,
    _hospital_location,
    _normalize_symptoms,
)
from app.routers.incidents import _incident_location
from app.schemas.ambulance import DriverIncidentHospitalOut
from app.schemas.tracking import IncidentTrackingOut, TrackingAmbulanceOut

router = APIRouter()


@router.get(
    "/{incident_id}/tracking",
    response_model=IncidentTrackingOut,
    summary="Live tracking data for the user's incident",
)
def get_incident_tracking(
    incident_id: int,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    incident = db.get(Incident, incident_id)
    if not incident:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Incident {incident_id} not found",
        )
    if incident.user_id is not None and incident.user_id != user.id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="This incident belongs to another user.",
        )

    hospital = None
    if incident.assigned_hospital_id:
        hosp = db.get(Hospital, incident.assigned_hospital_id)
        if hosp:
            hospital = DriverIncidentHospitalOut(
                id=hosp.id,
                name=hosp.name,
                location=_hospital_location(hosp.id, db),
            )

    ambulance = None
    if incident.assigned_ambulance_id:
        amb = db.get(Ambulance, incident.assigned_ambulance_id)
        if amb:
            amb_out = _ambulance_orm_to_out(amb, db)
            ambulance = TrackingAmbulanceOut(
                id=amb_out.id,
                registration_number=amb_out.registration_number,
                vehicle_type=amb_out.vehicle_type,
                location=amb_out.location,
                location_updated_at=amb_out.location_updated_at,
            )

    return IncidentTrackingOut(
        id=incident.id,
        status=incident.status,
        severity=incident.severity,
        emergency_type=incident.emergency_type,
        symptoms=_normalize_symptoms(incident.symptoms),
        victims=incident.victims,
        department_needed=incident.department_needed,
        transcript=incident.transcript,
        location=_incident_location(incident.id, db),
        created_at=incident.created_at,
        assigned_hospital=hospital,
        ambulance=ambulance,
    )

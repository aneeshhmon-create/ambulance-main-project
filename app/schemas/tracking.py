"""
app/schemas/tracking.py
───────────────────────
Response shape for the user app's live tracking map:
GET /incidents/{incident_id}/tracking
"""

from datetime import datetime
from typing import Optional

from pydantic import BaseModel, Field

from app.schemas.ambulance import DriverIncidentHospitalOut
from app.schemas.hospital import LocationSchema


class TrackingAmbulanceOut(BaseModel):
    """The ambulance coming to the patient, with its last reported position."""
    id: int
    registration_number: str
    vehicle_type: Optional[str] = None
    location: Optional[LocationSchema] = None
    location_updated_at: Optional[datetime] = None


class IncidentTrackingOut(BaseModel):
    id: int
    status: str
    severity: Optional[str] = None
    emergency_type: Optional[str] = None
    symptoms: list[str] = Field(default_factory=list)
    victims: int = 1
    department_needed: Optional[str] = None
    transcript: Optional[str] = None
    location: LocationSchema
    created_at: datetime
    assigned_hospital: Optional[DriverIncidentHospitalOut] = None
    ambulance: Optional[TrackingAmbulanceOut] = None

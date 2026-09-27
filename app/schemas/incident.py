"""
app/schemas/incident.py
────────────────────────
Pydantic v2 schemas for the Incident and IncidentBroadcast resources.

Request / Response shapes for:
  POST   /incidents
  POST   /incidents/{id}/broadcasts/{bid}/accept
  GET    /incidents/{id}
"""

from datetime import datetime
from typing import Optional

from pydantic import BaseModel, Field, ConfigDict

from app.schemas.hospital import LocationSchema, HospitalOut
from app.schemas.ambulance import AmbulanceOut


# ── Broadcast sub-schema ─────────────────────────────────────────────────────

class BroadcastOut(BaseModel):
    """Single broadcast record returned inside an IncidentOut."""
    model_config = ConfigDict(from_attributes=True)

    id: int
    incident_id: int
    target_type: str
    target_id: int
    status: str
    sent_at: datetime
    responded_at: Optional[datetime] = None


# ── Request schemas ──────────────────────────────────────────────────────────

class IncidentCreate(BaseModel):
    """Body accepted by POST /incidents."""
    user_id: Optional[int] = None
    lat: float = Field(..., ge=-90.0, le=90.0, description="Incident latitude")
    lng: float = Field(..., ge=-180.0, le=180.0, description="Incident longitude")
    emergency_type: Optional[str] = None
    severity: Optional[str] = Field(
        None,
        description="Severity level: low / medium / high / critical",
    )
    symptoms: list[str] = Field(default_factory=list)
    victims: int = Field(1, ge=1)
    department_needed: Optional[str] = None


# ── Response schemas ─────────────────────────────────────────────────────────

class IncidentOut(BaseModel):
    """
    Standard response for a single incident.
    Includes the list of hospital broadcasts and the assigned ambulance.
    """
    model_config = ConfigDict(from_attributes=True)

    id: int
    user_id: Optional[int]
    location: LocationSchema
    emergency_type: Optional[str]
    severity: Optional[str]
    symptoms: list[str]
    victims: int
    department_needed: Optional[str]
    status: str
    assigned_hospital_id: Optional[int]
    assigned_ambulance_id: Optional[int]
    created_at: datetime

    # Enriched fields populated by the router
    broadcasts: list[BroadcastOut] = Field(default_factory=list)
    assigned_ambulance: Optional[AmbulanceOut] = None
    transcript: Optional[str] = None
    extracted_data: Optional[dict] = None

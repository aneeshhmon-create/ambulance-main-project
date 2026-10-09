"""
app/schemas/ambulance.py
─────────────────────────
Pydantic v2 schemas for the Ambulance resource.

Location is accepted and returned as {"lat": float, "lng": float}
plain JSON; conversion to/from PostGIS WKT happens in the router.
"""

from datetime import datetime
from typing import Optional

from pydantic import BaseModel, Field, ConfigDict

from app.schemas.hospital import LocationSchema   # reuse the same sub-schema


# ── Request schemas ──────────────────────────────────────────────────────────

class AmbulanceCreate(BaseModel):
    """Body accepted by POST /ambulances."""
    driver_name: str = Field(..., min_length=1, max_length=255)
    driver_phone: str = Field(..., min_length=1, max_length=30)
    location: LocationSchema


class AmbulanceLocationUpdate(BaseModel):
    """Body accepted by PATCH /ambulances/{id}/location."""
    location: LocationSchema


# ── Response schemas ─────────────────────────────────────────────────────────

class AmbulanceOut(BaseModel):
    """Standard response for a single ambulance."""
    model_config = ConfigDict(from_attributes=True)

    id: int
    driver_name: str
    driver_phone: str
    location: Optional[LocationSchema]
    is_available: bool


class AmbulanceNearestOut(AmbulanceOut):
    """Response for the /ambulances/nearest endpoint — includes distance."""
    distance_m: float = Field(..., description="Distance from query point in metres")


# ── Assignment (what the driver's app polls) ─────────────────────────────────

class AssignmentHospitalOut(BaseModel):
    """Destination hospital; only present once a hospital has accepted."""
    id: int
    name: str
    location: LocationSchema
    departments: list[str]


class AssignmentPatientOut(BaseModel):
    """Reporting user's contact details, when the incident has a user."""
    name: str
    phone: str


class AmbulanceAssignmentOut(BaseModel):
    """
    Response of GET /ambulances/{id}/assignment.

    `assigned` is false (and everything else null) when the ambulance has no
    active incident. `hospital` stays null until a hospital accepts the case.
    """
    assigned: bool
    incident_id: Optional[int] = None
    incident_status: Optional[str] = None
    emergency_type: Optional[str] = None
    severity: Optional[str] = None
    symptoms: list[str] = Field(default_factory=list)
    victims: Optional[int] = None
    department_needed: Optional[str] = None
    created_at: Optional[datetime] = None
    patient_location: Optional[LocationSchema] = None
    patient: Optional[AssignmentPatientOut] = None
    hospital: Optional[AssignmentHospitalOut] = None
    distance_to_patient_km: Optional[float] = Field(
        None, description="Ambulance's last known position to the patient"
    )
    distance_patient_to_hospital_km: Optional[float] = None

"""
app/schemas/ambulance.py
─────────────────────────
Pydantic v2 schemas for the Ambulance resource.

Location is accepted and returned as {"lat": float, "lng": float}
plain JSON; conversion to/from PostGIS WKT happens in the router.

driver_name / driver_phone have been removed — driver information now
lives in the `drivers` table linked via `ambulance_driver`.
"""

from datetime import datetime
from typing import Optional

from pydantic import BaseModel, Field, ConfigDict

from app.schemas.hospital import LocationSchema   # reuse the same sub-schema


# ── Request schemas ──────────────────────────────────────────────────────────

class AmbulanceCreate(BaseModel):
    """Body accepted by POST /ambulances."""
    registration_number: str = Field(..., min_length=1, max_length=50)
    vehicle_type: Optional[str] = Field(
        None, description="e.g. 'ALS' or 'BLS'", max_length=50
    )
    location: LocationSchema


class AmbulanceLocationUpdate(BaseModel):
    """Body accepted by PATCH /ambulances/{id}/location."""
    location: LocationSchema


class AmbulanceOnlineUpdate(BaseModel):
    """Body accepted by PATCH /ambulances/{id}/online."""
    is_online: bool
    lat: Optional[float] = Field(None, ge=-90.0, le=90.0)
    lng: Optional[float] = Field(None, ge=-180.0, le=180.0)


# ── Response schemas ─────────────────────────────────────────────────────────

class AmbulanceOut(BaseModel):
    """Standard response for a single ambulance."""
    model_config = ConfigDict(from_attributes=True)

    id: int
    registration_number: str
    vehicle_type: Optional[str]
    location: Optional[LocationSchema]
    is_available: bool
    is_online: bool = False
    location_updated_at: Optional[datetime] = None


class AmbulanceNearestOut(AmbulanceOut):
    """Response for the /ambulances/nearest endpoint — includes distance."""
    distance_m: float = Field(..., description="Distance from query point in metres")


# ── Driver-facing ambulance summary ─────────────────────────────────────────

class DriverAmbulanceOut(BaseModel):
    """
    Minimal ambulance info returned to an authenticated driver.
    Used by GET /drivers/me/ambulances.
    """
    model_config = ConfigDict(from_attributes=True)

    id: int
    registration_number: str
    vehicle_type: Optional[str]
    is_available: bool
    is_online: bool = False
    location_updated_at: Optional[datetime] = None


class AmbulanceIncidentOut(BaseModel):
    """
    One incident candidate requested for an ambulance.
    Returned by GET /ambulances/{ambulance_id}/incidents.
    """
    model_config = ConfigDict(from_attributes=True)

    id: int
    severity: Optional[str] = None
    emergency_type: Optional[str] = None
    symptoms: list[str] = Field(default_factory=list)
    victims: int = 1
    department_needed: Optional[str] = None
    transcript: Optional[str] = None
    location: LocationSchema
    distance_km: Optional[float] = None
    created_at: datetime


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

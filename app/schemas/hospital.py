"""
app/schemas/hospital.py
────────────────────────
Pydantic v2 schemas for the Hospital resource.

Location is accepted and returned as {"lat": float, "lng": float}
plain JSON; conversion to/from PostGIS WKT happens in the router.
"""

from datetime import datetime
from typing import Optional

from pydantic import BaseModel, Field, ConfigDict


# ── Shared sub-schema ────────────────────────────────────────────────────────

class LocationSchema(BaseModel):
    """Plain lat/lng pair used in request and response bodies."""
    lat: float = Field(..., ge=-90.0, le=90.0, description="Latitude")
    lng: float = Field(..., ge=-180.0, le=180.0, description="Longitude")


# ── Request schemas ──────────────────────────────────────────────────────────

class HospitalCreate(BaseModel):
    """Body accepted by POST /hospitals."""
    name: str = Field(..., min_length=1, max_length=255)
    location: LocationSchema
    departments: list[str] = Field(default_factory=list)


class HospitalUpdate(BaseModel):
    """Body accepted by PATCH /hospitals/{id}.
    All fields are optional — only supplied fields are updated.
    """
    departments: Optional[list[str]] = None
    is_active: Optional[bool] = None


# ── Response schemas ─────────────────────────────────────────────────────────

class HospitalOut(BaseModel):
    """Standard response for a single hospital."""
    model_config = ConfigDict(from_attributes=True)

    id: int
    name: str
    location: LocationSchema
    departments: list[str]
    is_active: bool
    created_at: datetime


class HospitalNearbyOut(HospitalOut):
    """Response for the /hospitals/nearby endpoint — includes distance."""
    distance_m: float = Field(..., description="Distance from query point in metres")

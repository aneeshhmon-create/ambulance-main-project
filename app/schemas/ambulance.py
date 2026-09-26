"""
app/schemas/ambulance.py
─────────────────────────
Pydantic v2 schemas for the Ambulance resource.

Location is accepted and returned as {"lat": float, "lng": float}
plain JSON; conversion to/from PostGIS WKT happens in the router.
"""

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

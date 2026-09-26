"""
app/schemas/__init__.py
───────────────────────
Re-exports all Pydantic schemas so callers can use:
    from app.schemas import HospitalCreate, HospitalOut, ...
"""

from app.schemas.hospital import (
    HospitalCreate,
    HospitalOut,
    HospitalUpdate,
    HospitalNearbyOut,
)
from app.schemas.ambulance import (
    AmbulanceCreate,
    AmbulanceOut,
    AmbulanceLocationUpdate,
    AmbulanceNearestOut,
)

__all__ = [
    "HospitalCreate",
    "HospitalOut",
    "HospitalUpdate",
    "HospitalNearbyOut",
    "AmbulanceCreate",
    "AmbulanceOut",
    "AmbulanceLocationUpdate",
    "AmbulanceNearestOut",
]

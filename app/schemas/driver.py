"""
app/schemas/driver.py
──────────────────────
Pydantic v2 schemas for the Driver resource.
(Sign-in request/response schemas live in app/schemas/auth.py.)
"""

from datetime import datetime
from typing import Optional

from pydantic import BaseModel, ConfigDict


# ── Full driver response ──────────────────────────────────────────────────────

class DriverOut(BaseModel):
    """Full driver profile (for internal use / future endpoints)."""
    model_config = ConfigDict(from_attributes=True)

    id: int
    name: str
    email: str
    phone: Optional[str] = None
    photo_url: Optional[str] = None
    is_active: bool
    created_at: datetime

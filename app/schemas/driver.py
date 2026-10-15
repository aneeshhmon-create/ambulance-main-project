"""
app/schemas/driver.py
──────────────────────
Pydantic v2 schemas for Driver authentication and profile.
"""

from datetime import datetime
from typing import Optional

from pydantic import BaseModel, ConfigDict


# ── Auth request / response ───────────────────────────────────────────────────

class GoogleTokenRequest(BaseModel):
    """Body for POST /auth/google."""
    id_token: str


class DevLoginRequest(BaseModel):
    """Body for POST /auth/dev-login (only available when ALLOW_DEV_LOGIN=true)."""
    email: str


class DriverProfileOut(BaseModel):
    """Driver info embedded in the auth token response."""
    model_config = ConfigDict(from_attributes=True)

    id: int
    name: str
    email: str
    photo_url: Optional[str] = None


class TokenResponse(BaseModel):
    """Response of POST /auth/google and POST /auth/dev-login."""
    access_token: str
    token_type: str = "bearer"
    driver: DriverProfileOut


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

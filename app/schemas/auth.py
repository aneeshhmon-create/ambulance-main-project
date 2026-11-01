"""
app/schemas/auth.py
────────────────────
Pydantic v2 schemas shared by the Google sign-in flow for all three apps
(driver app, user app, hospital dashboard).
"""

from typing import Literal, Optional

from pydantic import BaseModel, Field, model_validator

from app.schemas.ambulance import AmbulanceType
from app.schemas.hospital import HospitalCreate

Role = Literal["driver", "user", "hospital"]


# ── Requests ──────────────────────────────────────────────────────────────────

class GoogleTokenRequest(BaseModel):
    """Body for POST /auth/google."""
    id_token: str
    role: Role = "driver"


class DevLoginRequest(BaseModel):
    """Body for POST /auth/dev-login (only available when ALLOW_DEV_LOGIN=true)."""
    email: str
    role: Role = "driver"
    name: Optional[str] = None


class RegisterPersonRequest(BaseModel):
    """Body for POST /auth/register/driver and POST /auth/register/user."""
    registration_token: str
    name: str = Field(..., min_length=1, max_length=255)
    phone: str = Field(..., min_length=1, description="Raw phone number (spaces, dashes, +91, 0 accepted)")


class RegisterDriverRequest(RegisterPersonRequest):
    """
    Body for POST /auth/register/driver.

    The ambulance fields are optional so older app builds keep working (the
    driver can add an ambulance later via POST /drivers/me/ambulances), but
    when one is given both must be.
    """
    registration_number: Optional[str] = Field(None, max_length=50)
    vehicle_type: Optional[AmbulanceType] = None

    @model_validator(mode="after")
    def _ambulance_fields_together(self) -> "RegisterDriverRequest":
        has_number = bool(self.registration_number and self.registration_number.strip())
        if has_number != (self.vehicle_type is not None):
            raise ValueError(
                "registration_number and vehicle_type must be provided together."
            )
        return self


class RegisterHospitalRequest(BaseModel):
    """Body for POST /auth/register/hospital."""
    registration_token: str
    hospital: HospitalCreate


# ── Responses ─────────────────────────────────────────────────────────────────

class AccountOut(BaseModel):
    """The signed-in account. Role-specific fields are null for other roles."""
    id: int
    name: str
    email: str
    photo_url: Optional[str] = None
    phone: Optional[str] = None          # driver, user
    hospital_id: Optional[int] = None    # hospital


class GoogleProfile(BaseModel):
    """Identity taken from the verified Google token, used to prefill forms."""
    email: str
    name: str
    photo_url: Optional[str] = None


class AuthResponse(BaseModel):
    """
    Response of POST /auth/google, POST /auth/dev-login and
    POST /auth/register/*.

    Either the account exists and `access_token` + `account` are set, or it
    does not and `registration_required` is true: the client must collect the
    role-specific details and send them to POST /auth/register/{role} together
    with `registration_token`.
    """
    registration_required: bool = False
    role: Role

    access_token: Optional[str] = None
    token_type: str = "bearer"
    account: Optional[AccountOut] = None

    registration_token: Optional[str] = None
    google_profile: Optional[GoogleProfile] = None

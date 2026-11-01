"""
app/routers/drivers.py
───────────────────────
Authenticated endpoints for the signed-in driver.

Endpoints
─────────
GET /drivers/me/ambulances
    Returns the ambulances linked to the currently authenticated driver.
    Requires a valid Bearer JWT (issued by POST /auth/google).
"""

import re

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.core.security import get_current_driver
from app.db import get_db
from app.models.ambulance import Ambulance
from app.models.ambulance_driver import AmbulanceDriver
from app.models.driver import Driver
from app.schemas.ambulance import DriverAmbulanceCreate, DriverAmbulanceOut

router = APIRouter()

_REGISTRATION_RE = re.compile(r"^[A-Z0-9]{4,15}$")


def normalize_registration_number(raw: str) -> str:
    """
    Canonical form: upper-case letters and digits only (spaces and hyphens
    dropped), so "KL 07 AB 1234" and "kl-07-ab-1234" are the same vehicle.
    """
    number = re.sub(r"[\s-]+", "", raw.upper())
    if not _REGISTRATION_RE.match(number):
        raise HTTPException(
            status_code=422,
            detail="Enter a valid ambulance registration number, e.g. KL 07 AB 1234.",
        )
    return number


def add_ambulance_to_driver(
    db: Session, driver: Driver, registration_number: str, vehicle_type: str
) -> Ambulance:
    """
    Create a new ambulance and link it to `driver`. Does not commit.

    A registration number that already exists is rejected rather than linked:
    otherwise anyone could attach themselves to another crew's ambulance.
    """
    number = normalize_registration_number(registration_number)
    if db.query(Ambulance).filter_by(registration_number=number).first():
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="An ambulance with this registration number is already registered.",
        )
    ambulance = Ambulance(registration_number=number, vehicle_type=vehicle_type)
    db.add(ambulance)
    db.flush()
    db.add(AmbulanceDriver(driver_id=driver.id, ambulance_id=ambulance.id))
    return ambulance


def _ambulance_out(ambulance: Ambulance) -> DriverAmbulanceOut:
    return DriverAmbulanceOut(
        id=ambulance.id,
        registration_number=ambulance.registration_number,
        vehicle_type=ambulance.vehicle_type,
        is_available=ambulance.is_available,
        is_online=ambulance.is_online,
        location_updated_at=ambulance.location_updated_at,
    )


@router.get(
    "/me/ambulances",
    response_model=list[DriverAmbulanceOut],
    summary="Get ambulances linked to the signed-in driver",
)
def get_my_ambulances(
    driver: Driver = Depends(get_current_driver),
    db: Session = Depends(get_db),
):
    """
    Returns all ambulances the authenticated driver is authorised to operate.

    The ambulance list comes from the `ambulance_driver` junction table.
    The driver is identified by the JWT bearer token — the client never
    sends a driver ID explicitly.
    """
    return [_ambulance_out(link.ambulance) for link in driver.ambulance_links]


@router.post(
    "/me/ambulances",
    response_model=DriverAmbulanceOut,
    status_code=status.HTTP_201_CREATED,
    summary="Register an ambulance and link it to the signed-in driver",
)
def add_my_ambulance(
    body: DriverAmbulanceCreate,
    driver: Driver = Depends(get_current_driver),
    db: Session = Depends(get_db),
):
    """
    For drivers who have no ambulance yet (or drive an additional one).
    `vehicle_type` is ALS, BLS, or ALS+BLS for a vehicle equipped for both.
    """
    ambulance = add_ambulance_to_driver(
        db, driver, body.registration_number, body.vehicle_type
    )
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="An ambulance with this registration number is already registered.",
        )
    db.refresh(ambulance)
    return _ambulance_out(ambulance)

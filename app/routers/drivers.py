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

from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app.core.security import get_current_driver
from app.db import get_db
from app.models.driver import Driver
from app.schemas.ambulance import DriverAmbulanceOut

router = APIRouter()


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
    return [
        DriverAmbulanceOut(
            id=link.ambulance.id,
            registration_number=link.ambulance.registration_number,
            vehicle_type=link.ambulance.vehicle_type,
            is_available=link.ambulance.is_available,
        )
        for link in driver.ambulance_links
    ]

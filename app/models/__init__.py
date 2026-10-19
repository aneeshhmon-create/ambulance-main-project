"""
app/models/__init__.py
──────────────────────
Imports every ORM model so that:
  • Alembic autogenerate detects all tables.
  • Any code that does `from app.models import User` works cleanly.
"""

from app.models.user import User
from app.models.hospital import Hospital
from app.models.ambulance import Ambulance
from app.models.incident import Incident
from app.models.incident_broadcast import IncidentBroadcast
from app.models.driver import Driver
from app.models.ambulance_driver import AmbulanceDriver
from app.models.hospital_account import HospitalAccount
from app.models.incident_ambulance import IncidentAmbulance
from app.models.incident_ambulance_cancellation import IncidentAmbulanceCancellation

__all__ = [
    "HospitalAccount",
    "User",
    "Hospital",
    "Ambulance",
    "Incident",
    "IncidentBroadcast",
    "Driver",
    "AmbulanceDriver",
    "IncidentAmbulance",
    "IncidentAmbulanceCancellation",
]

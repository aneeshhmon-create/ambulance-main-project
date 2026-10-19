"""
app/models/incident_ambulance_cancellation.py
──────────────────────────────────────────────
Remembers which ambulances cancelled an accepted incident or rejected a
requested one, so it is not offered to them again (re-broadcast or
online/location backfill).
"""

from datetime import datetime

from sqlalchemy import Integer, ForeignKey, DateTime, func
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base


class IncidentAmbulanceCancellation(Base):
    __tablename__ = "inci_ambu_cancelled"

    incident_id: Mapped[int] = mapped_column(
        Integer,
        ForeignKey("incidents.id", ondelete="CASCADE"),
        primary_key=True,
    )
    ambulance_id: Mapped[int] = mapped_column(
        Integer,
        ForeignKey("ambulances.id", ondelete="CASCADE"),
        primary_key=True,
        index=True,
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        nullable=False,
    )

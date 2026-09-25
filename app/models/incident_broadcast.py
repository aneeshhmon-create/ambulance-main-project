"""
app/models/incident_broadcast.py
──────────────────────────────────
SQLAlchemy ORM model for the `incident_broadcasts` table.
Tracks which ambulances were notified about an incident
and what their response was.
"""

from datetime import datetime

from typing import TYPE_CHECKING

from sqlalchemy import String, DateTime, ForeignKey, func
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base

if TYPE_CHECKING:
    from app.models.incident import Incident
    from app.models.ambulance import Ambulance


class IncidentBroadcast(Base):
    __tablename__ = "incident_broadcasts"

    id: Mapped[int] = mapped_column(primary_key=True, index=True)

    incident_id: Mapped[int] = mapped_column(
        ForeignKey("incidents.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )

    ambulance_id: Mapped[int] = mapped_column(
        ForeignKey("ambulances.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )

    # status: sent / accepted / declined / ignored
    status: Mapped[str] = mapped_column(
        String, default="sent", server_default="sent", nullable=False, index=True
    )

    sent_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        nullable=False,
    )

    responded_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True),
        nullable=True,
    )

    # Relationships
    incident: Mapped["Incident"] = relationship(
        "Incident", back_populates="broadcasts"
    )
    ambulance: Mapped["Ambulance"] = relationship(
        "Ambulance", back_populates="broadcasts"
    )

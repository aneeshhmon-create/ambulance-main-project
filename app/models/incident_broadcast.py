"""
app/models/incident_broadcast.py
──────────────────────────────────
SQLAlchemy ORM model for the `incident_broadcasts` table.

Tracks which hospitals (or other targets) were notified about an incident
and what their response was.

Columns
───────
target_type  – discriminator: 'hospital' | 'ambulance' (extensible)
target_id    – FK-free integer; the actual ID in the target table
status       – pending / accepted / expired / declined
"""

from datetime import datetime

from typing import TYPE_CHECKING

from sqlalchemy import String, Integer, DateTime, ForeignKey, func
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base

if TYPE_CHECKING:
    from app.models.incident import Incident


class IncidentBroadcast(Base):
    __tablename__ = "incident_broadcasts"

    id: Mapped[int] = mapped_column(primary_key=True, index=True)

    incident_id: Mapped[int] = mapped_column(
        ForeignKey("incidents.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )

    # Generic target — avoids coupling to a single FK table.
    # target_type: 'hospital'
    # target_id  : hospitals.id
    target_type: Mapped[str] = mapped_column(
        String, nullable=False, index=True
    )
    target_id: Mapped[int] = mapped_column(
        Integer, nullable=False, index=True
    )

    # status: pending / accepted / expired / declined
    status: Mapped[str] = mapped_column(
        String, default="pending", server_default="pending", nullable=False, index=True
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

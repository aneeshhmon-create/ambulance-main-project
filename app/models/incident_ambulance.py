"""
app/models/incident_ambulance.py
─────────────────────────────────
Junction table tracking which incidents were requested to which candidate
ambulances (many-to-many, composite PK).
"""

from datetime import datetime
from typing import TYPE_CHECKING

from sqlalchemy import Integer, ForeignKey, DateTime, func
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base

if TYPE_CHECKING:
    from app.models.incident import Incident
    from app.models.ambulance import Ambulance


class IncidentAmbulance(Base):
    __tablename__ = "inci_ambu"

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

    # Relationships
    incident: Mapped["Incident"] = relationship(
        "Incident", back_populates="requested_ambulances"
    )
    ambulance: Mapped["Ambulance"] = relationship(
        "Ambulance", back_populates="requested_incidents"
    )

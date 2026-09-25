"""
app/models/incident.py
───────────────────────
SQLAlchemy ORM model for the `incidents` table.
"""

from datetime import datetime
from typing import TYPE_CHECKING

from sqlalchemy import (
    String,
    Integer,
    DateTime,
    ForeignKey,
    func,
    text,
)
from sqlalchemy.dialects.postgresql import ARRAY
from sqlalchemy.orm import Mapped, mapped_column, relationship
from geoalchemy2 import Geography

from app.db.base import Base

if TYPE_CHECKING:
    from app.models.user import User
    from app.models.hospital import Hospital
    from app.models.ambulance import Ambulance
    from app.models.incident_broadcast import IncidentBroadcast


class Incident(Base):
    __tablename__ = "incidents"

    id: Mapped[int] = mapped_column(primary_key=True, index=True)

    # Who reported
    user_id: Mapped[int | None] = mapped_column(
        ForeignKey("users.id", ondelete="SET NULL"), nullable=True, index=True
    )

    # Geography
    location: Mapped[object] = mapped_column(
        Geography(geometry_type="POINT", srid=4326, spatial_index=False),
        nullable=False,
    )

    # Incident details
    audio_url: Mapped[str | None] = mapped_column(String, nullable=True)
    emergency_type: Mapped[str | None] = mapped_column(String, nullable=True)
    severity: Mapped[str | None] = mapped_column(String, nullable=True)
    symptoms: Mapped[list[str] | None] = mapped_column(
        ARRAY(String),
        nullable=True,
        server_default=text("'{}'::text[]"),
    )
    victims: Mapped[int] = mapped_column(Integer, default=1, nullable=False)
    department_needed: Mapped[str | None] = mapped_column(String, nullable=True)

    # Status — pending / hospital_assigned / ambulance_assigned / completed
    status: Mapped[str] = mapped_column(
        String, default="pending", server_default="pending", nullable=False, index=True
    )

    # Assignments (nullable FKs)
    assigned_hospital_id: Mapped[int | None] = mapped_column(
        ForeignKey("hospitals.id", ondelete="SET NULL"), nullable=True, index=True
    )
    assigned_ambulance_id: Mapped[int | None] = mapped_column(
        ForeignKey("ambulances.id", ondelete="SET NULL"), nullable=True, index=True
    )

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        nullable=False,
    )

    # Relationships
    user: Mapped["User"] = relationship(
        "User", back_populates="incidents"
    )
    assigned_hospital: Mapped["Hospital"] = relationship(
        "Hospital",
        foreign_keys=[assigned_hospital_id],
        back_populates="assigned_incidents",
    )
    assigned_ambulance: Mapped["Ambulance"] = relationship(
        "Ambulance",
        foreign_keys=[assigned_ambulance_id],
        back_populates="assigned_incidents",
    )
    broadcasts: Mapped[list["IncidentBroadcast"]] = relationship(
        "IncidentBroadcast", back_populates="incident"
    )

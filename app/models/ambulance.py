"""
app/models/ambulance.py
────────────────────────
SQLAlchemy ORM model for the `ambulances` table.
Uses GeoAlchemy2 for the GEOGRAPHY(Point, 4326) column and a GIST index.

Driver information is no longer stored on this table; it lives in the
`drivers` table and is linked via the `ambulance_driver` junction.
"""

from datetime import datetime
from typing import TYPE_CHECKING

from sqlalchemy import String, Boolean, Text, Index, DateTime, text
from sqlalchemy.orm import Mapped, mapped_column, relationship
from geoalchemy2 import Geography

from app.db.base import Base

if TYPE_CHECKING:
    from app.models.incident import Incident
    from app.models.ambulance_driver import AmbulanceDriver
    from app.models.incident_ambulance import IncidentAmbulance


class Ambulance(Base):
    __tablename__ = "ambulances"
    __table_args__ = (
        Index("idx_ambulances_location", "location", postgresql_using="gist"),
    )

    id: Mapped[int] = mapped_column(primary_key=True, index=True)

    # Vehicle identity — replaces old driver_name / driver_phone
    registration_number: Mapped[str] = mapped_column(
        String, unique=True, nullable=False, index=True
    )
    vehicle_type: Mapped[str | None] = mapped_column(
        Text, nullable=True
    )  # e.g. "ALS", "BLS"

    location: Mapped[object | None] = mapped_column(
        Geography(geometry_type="POINT", srid=4326, spatial_index=False),
        nullable=True,
    )
    is_available: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    is_online: Mapped[bool] = mapped_column(
        Boolean, default=False, server_default=text("false"), nullable=False, index=True
    )
    location_updated_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )

    # Relationships
    assigned_incidents: Mapped[list["Incident"]] = relationship(
        "Incident",
        foreign_keys="Incident.assigned_ambulance_id",
        back_populates="assigned_ambulance",
    )

    driver_links: Mapped[list["AmbulanceDriver"]] = relationship(
        "AmbulanceDriver",
        back_populates="ambulance",
        cascade="all, delete-orphan",
    )

    requested_incidents: Mapped[list["IncidentAmbulance"]] = relationship(
        "IncidentAmbulance",
        back_populates="ambulance",
        cascade="all, delete-orphan",
    )

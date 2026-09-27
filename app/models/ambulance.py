"""
app/models/ambulance.py
────────────────────────
SQLAlchemy ORM model for the `ambulances` table.
Uses GeoAlchemy2 for the GEOGRAPHY(Point, 4326) column and a GIST index.
"""

from typing import TYPE_CHECKING

from sqlalchemy import String, Boolean, Index
from sqlalchemy.orm import Mapped, mapped_column, relationship
from geoalchemy2 import Geography

from app.db.base import Base

if TYPE_CHECKING:
    from app.models.incident import Incident


class Ambulance(Base):
    __tablename__ = "ambulances"
    __table_args__ = (
        Index("idx_ambulances_location", "location", postgresql_using="gist"),
    )

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    driver_name: Mapped[str] = mapped_column(String, nullable=False)
    driver_phone: Mapped[str] = mapped_column(
        String, unique=True, nullable=False, index=True
    )
    location: Mapped[object | None] = mapped_column(
        Geography(geometry_type="POINT", srid=4326, spatial_index=False),
        nullable=True,
    )
    is_available: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)

    # Relationships
    assigned_incidents: Mapped[list["Incident"]] = relationship(
        "Incident",
        foreign_keys="Incident.assigned_ambulance_id",
        back_populates="assigned_ambulance",
    )

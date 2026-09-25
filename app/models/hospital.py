"""
app/models/hospital.py
───────────────────────
SQLAlchemy ORM model for the `hospitals` table.
Uses GeoAlchemy2 for the GEOGRAPHY(Point, 4326) column and a GIST index.
"""

from datetime import datetime
from typing import TYPE_CHECKING

from sqlalchemy import String, Boolean, DateTime, func, text, Index
from sqlalchemy.dialects.postgresql import ARRAY
from sqlalchemy.orm import Mapped, mapped_column, relationship
from geoalchemy2 import Geography

from app.db.base import Base

if TYPE_CHECKING:
    from app.models.incident import Incident


class Hospital(Base):
    __tablename__ = "hospitals"
    __table_args__ = (
        Index("idx_hospitals_location", "location", postgresql_using="gist"),
    )

    id: Mapped[int] = mapped_column(primary_key=True, index=True)
    name: Mapped[str] = mapped_column(String, nullable=False)
    location: Mapped[object] = mapped_column(
        Geography(geometry_type="POINT", srid=4326, spatial_index=False),
        nullable=False,
    )
    departments: Mapped[list[str]] = mapped_column(
        ARRAY(String),
        nullable=False,
        server_default=text("'{}'::text[]"),
    )
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        nullable=False,
    )

    # Relationships
    assigned_incidents: Mapped[list["Incident"]] = relationship(
        "Incident",
        foreign_keys="Incident.assigned_hospital_id",
        back_populates="assigned_hospital",
    )

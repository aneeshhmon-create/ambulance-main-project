"""
app/models/ambulance_driver.py
───────────────────────────────
Junction table linking drivers ↔ ambulances (many-to-many).

A driver can be linked to several ambulances (e.g. on different shifts)
and an ambulance can have several authorised drivers.
"""

from datetime import datetime
from typing import TYPE_CHECKING

from sqlalchemy import Integer, ForeignKey, DateTime, func
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base

if TYPE_CHECKING:
    from app.models.driver import Driver
    from app.models.ambulance import Ambulance


class AmbulanceDriver(Base):
    __tablename__ = "ambulance_driver"

    driver_id: Mapped[int] = mapped_column(
        Integer,
        ForeignKey("drivers.id", ondelete="CASCADE"),
        primary_key=True,
    )
    ambulance_id: Mapped[int] = mapped_column(
        Integer,
        ForeignKey("ambulances.id", ondelete="CASCADE"),
        primary_key=True,
    )

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        nullable=False,
    )

    # Relationships
    driver: Mapped["Driver"] = relationship(
        "Driver", back_populates="ambulance_links"
    )
    ambulance: Mapped["Ambulance"] = relationship(
        "Ambulance", back_populates="driver_links"
    )

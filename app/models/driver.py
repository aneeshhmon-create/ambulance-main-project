"""
app/models/driver.py
────────────────────
SQLAlchemy ORM model for the `drivers` table.

A driver is a human who drives one or more ambulances.
Authentication is via Google sign-in (email is the stable identifier).
"""

from datetime import datetime
from typing import TYPE_CHECKING

from sqlalchemy import String, Boolean, DateTime, func
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base

if TYPE_CHECKING:
    from app.models.ambulance_driver import AmbulanceDriver


class Driver(Base):
    __tablename__ = "drivers"

    id: Mapped[int] = mapped_column(primary_key=True, index=True)

    # Google account identity — the server always reads email from the
    # verified ID token, never from client-supplied input.
    name: Mapped[str] = mapped_column(String, nullable=False)
    email: Mapped[str] = mapped_column(
        String, unique=True, nullable=False, index=True
    )

    # Optional contact / display fields
    phone: Mapped[str | None] = mapped_column(String, nullable=True)
    photo_url: Mapped[str | None] = mapped_column(String, nullable=True)

    is_active: Mapped[bool] = mapped_column(
        Boolean, default=True, nullable=False
    )

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        nullable=False,
    )

    # M2M to ambulances via the junction table
    ambulance_links: Mapped[list["AmbulanceDriver"]] = relationship(
        "AmbulanceDriver",
        back_populates="driver",
        cascade="all, delete-orphan",
    )

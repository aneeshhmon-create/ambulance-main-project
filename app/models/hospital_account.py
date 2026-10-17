"""
app/models/hospital_account.py
──────────────────────────────
SQLAlchemy ORM model for the `hospital_accounts` table.

A hospital account is a Google-authenticated login for the hospital
dashboard. Each account manages exactly one hospital, which is created
together with the account the first time someone signs in.
"""

from datetime import datetime
from typing import TYPE_CHECKING

from sqlalchemy import String, Integer, ForeignKey, DateTime, func
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base

if TYPE_CHECKING:
    from app.models.hospital import Hospital


class HospitalAccount(Base):
    __tablename__ = "hospital_accounts"

    id: Mapped[int] = mapped_column(primary_key=True, index=True)

    # Read from the verified Google ID token, never from client input.
    email: Mapped[str] = mapped_column(
        String, unique=True, nullable=False, index=True
    )
    name: Mapped[str] = mapped_column(String, nullable=False)
    photo_url: Mapped[str | None] = mapped_column(String, nullable=True)

    hospital_id: Mapped[int] = mapped_column(
        Integer,
        ForeignKey("hospitals.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        nullable=False,
    )

    hospital: Mapped["Hospital"] = relationship("Hospital")

"""
app/db/base.py
──────────────
Declarative base that all ORM models inherit from.
Importing this file (and all models) before calling
`Base.metadata.create_all(engine)` or running Alembic ensures every
table is registered in the metadata graph.
"""

from sqlalchemy.orm import DeclarativeBase


class Base(DeclarativeBase):
    pass


# Import all models here so Alembic autogenerate picks them up.
from app.models import User, Hospital, Ambulance, Incident, IncidentBroadcast  # noqa: E402, F401

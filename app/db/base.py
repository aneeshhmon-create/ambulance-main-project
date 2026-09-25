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


# Re-export model modules here so Alembic autogenerate picks them up.
# Example (uncomment as you add models):
# from app.models import hospital, ambulance, patient  # noqa: F401

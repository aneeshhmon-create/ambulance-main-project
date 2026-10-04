"""
app/routers/__init__.py
────────────────────────
Makes routers importable as `from app.routers import hospitals, ambulances, incidents`.
"""

from app.routers import hospitals, ambulances, incidents, users  # noqa: F401

__all__ = ["hospitals", "ambulances", "incidents", "users"]

"""
app/routers/__init__.py
────────────────────────
Makes routers importable as `from app.routers import hospitals, ambulances`.
"""

from app.routers import hospitals, ambulances  # noqa: F401

__all__ = ["hospitals", "ambulances"]


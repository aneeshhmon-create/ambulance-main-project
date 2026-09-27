"""
app/main.py
───────────
Application entry-point.

- Creates the FastAPI instance with metadata (title, version, docs URL).
- Registers all routers.
- Exposes a /health endpoint that verifies both the app and the DB are alive.
- On startup, ensures the PostGIS extension exists in the database.
"""

import time
from contextlib import asynccontextmanager

from fastapi import FastAPI, Depends
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy import text
from sqlalchemy.orm import Session

from app.core.config import settings
from app.db import get_db, engine


# ── Lifespan (replaces deprecated @app.on_event) ────────────────────────────

@asynccontextmanager
async def lifespan(app: FastAPI):
    """Runs once on startup; teardown code goes after `yield`."""
    # Enable PostGIS extension if it doesn't exist yet
    with engine.begin() as conn:
        conn.execute(text("CREATE EXTENSION IF NOT EXISTS postgis;"))
    print("✅  PostGIS extension ensured.")
    yield
    # Shutdown logic (e.g. close connection pools) would go here


# ── App factory ──────────────────────────────────────────────────────────────

app = FastAPI(
    title="Ambulance & Hospital Allocation API",
    description="MVP backend for geo-aware ambulance dispatch and hospital bed allocation.",
    version="0.1.0",
    docs_url="/docs",
    redoc_url="/redoc",
    lifespan=lifespan,
)

# Allow all origins in development; tighten this for production.
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"] if settings.APP_ENV == "development" else [],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


# ── Routers ──────────────────────────────────────────────────────────────────
from app.routers import hospitals, ambulances, incidents

app.include_router(hospitals.router, prefix="/hospitals", tags=["Hospitals"])
app.include_router(ambulances.router, prefix="/ambulances", tags=["Ambulances"])
app.include_router(incidents.router, prefix="/incidents", tags=["Incidents"])


# ── Health-check ─────────────────────────────────────────────────────────────

@app.get("/health", tags=["Meta"])
def health_check(db: Session = Depends(get_db)):
    """
    Returns HTTP 200 when both the application and the PostgreSQL/PostGIS
    database are reachable. Useful for Docker health-checks and load-balancer
    probes.
    """
    start = time.perf_counter()
    db.execute(text("SELECT 1"))
    db_latency_ms = round((time.perf_counter() - start) * 1000, 2)

    return {
        "status": "ok",
        "environment": settings.APP_ENV,
        "database": "reachable",
        "db_latency_ms": db_latency_ms,
    }

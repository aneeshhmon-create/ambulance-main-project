"""
app/tests/test_driver_navigation.py
───────────────────────────────────
Backend unit tests for the driver navigation feature:
  - GET /ambulances/{ambulance_id}/incidents/{incident_id}
  - 401 without auth token
  - 403 for driver not linked to the ambulance
  - 404 when incident does not exist
  - 403 when incident is assigned to another ambulance
  - 200 with assigned_hospital=None before hospital acceptance
  - 200 with assigned_hospital populated after hospital acceptance
"""

from datetime import datetime, timezone
from unittest.mock import MagicMock, patch
import json
import sqlite3

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine, event
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool
from sqlalchemy.ext.compiler import compiles
from sqlalchemy.types import ARRAY
from geoalchemy2.types import Geography
from sqlalchemy.schema import DefaultClause

from app.db.base import Base
from app.db import get_db

with patch("faster_whisper.WhisperModel", MagicMock()):
    from app.main import app

from app.models.driver import Driver
from app.models.ambulance import Ambulance
from app.models.ambulance_driver import AmbulanceDriver
from app.models.incident import Incident
from app.models.hospital import Hospital
from app.core.security import create_driver_token

# ── SQLite in-memory setup with Spatial mock functions ────────────────────────

SQLALCHEMY_DATABASE_URL = "sqlite://"
engine = create_engine(
    SQLALCHEMY_DATABASE_URL,
    connect_args={"check_same_thread": False},
    poolclass=StaticPool,
)

sqlite3.register_adapter(list, json.dumps)
sqlite3.register_converter("TEXT", lambda b: json.loads(b.decode()) if b.startswith(b"[") else b.decode())

@event.listens_for(engine, "connect")
def connect(dbapi_connection, connection_record):
    dbapi_connection.create_function("ST_GeogFromText", 1, lambda x: x)
    dbapi_connection.create_function("ST_AsBinary", 1, lambda x: x)
    dbapi_connection.create_function("AsBinary", 1, lambda x: x)
    dbapi_connection.create_function("ST_Y", 1, lambda x: 9.9312)
    dbapi_connection.create_function("ST_X", 1, lambda x: 76.2673)
    dbapi_connection.create_function("ST_Distance", 2, lambda a, b: 1200.0)
    dbapi_connection.create_function("ST_DWithin", 3, lambda a, b, c: 1)
    dbapi_connection.create_function("ST_MakePoint", 2, lambda x, y: f"POINT({x} {y})")
    dbapi_connection.create_function("ST_GeomFromWKB", 1, lambda x: x)


TestingSessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)


@compiles(ARRAY, "sqlite")
def compile_array_sqlite(type_, compiler, **kw):
    return "TEXT"


@compiles(Geography, "sqlite")
def compile_geography_sqlite(type_, compiler, **kw):
    return "TEXT"


@compiles(DefaultClause, "sqlite")
def compile_default_sqlite(element, compiler, **kw):
    arg = str(element.arg)
    if "::" in arg:
        return ""
    return compiler.visit_default_clause(element, **kw)


_TEST_TABLES = [
    Driver.__table__,
    Ambulance.__table__,
    AmbulanceDriver.__table__,
    Incident.__table__,
    Hospital.__table__,
]

Incident.__table__.columns["symptoms"].server_default = None
Hospital.__table__.columns["departments"].server_default = None


def override_get_db():
    db = TestingSessionLocal()
    try:
        yield db
    finally:
        db.close()


@pytest.fixture(autouse=True)
def setup_db():
    Base.metadata.create_all(bind=engine, tables=_TEST_TABLES)
    app.dependency_overrides[get_db] = override_get_db
    yield
    Base.metadata.drop_all(bind=engine, tables=_TEST_TABLES)
    app.dependency_overrides.clear()


@pytest.fixture()
def db():
    session = TestingSessionLocal()
    try:
        yield session
    finally:
        session.close()


@pytest.fixture()
def client():
    return TestClient(app)


# ── Fixtures for driver, ambulances, hospital and incidents ───────────────────

@pytest.fixture()
def driver_and_ambulance(db):
    """Driver 1 linked to Ambulance 1."""
    d1 = Driver(name="Driver One", email="driver1@example.com", is_active=True)
    db.add(d1)
    db.flush()

    a1 = Ambulance(
        registration_number="KL-07-AA-1111",
        vehicle_type="ALS",
        is_available=True,
        is_online=True,
        location="POINT(76.2673 9.9312)",
        location_updated_at=datetime.now(timezone.utc),
    )
    db.add(a1)
    db.flush()

    db.add(AmbulanceDriver(driver_id=d1.id, ambulance_id=a1.id))
    db.commit()

    token1 = create_driver_token(d1.id)
    return d1, a1, token1


@pytest.fixture()
def second_driver_and_ambulance(db):
    """Driver 2 linked to Ambulance 2."""
    d2 = Driver(name="Driver Two", email="driver2@example.com", is_active=True)
    db.add(d2)
    db.flush()

    a2 = Ambulance(
        registration_number="KL-07-BB-2222",
        vehicle_type="BLS",
        is_available=True,
        is_online=True,
        location="POINT(76.2700 9.9350)",
        location_updated_at=datetime.now(timezone.utc),
    )
    db.add(a2)
    db.flush()

    db.add(AmbulanceDriver(driver_id=d2.id, ambulance_id=a2.id))
    db.commit()

    token2 = create_driver_token(d2.id)
    return d2, a2, token2


@pytest.fixture()
def hospital(db):
    h = Hospital(
        name="City General Hospital",
        location="POINT(76.2800 9.9400)",
        departments=["Cardiology", "Trauma", "Emergency"],
        is_active=True,
    )
    db.add(h)
    db.commit()
    db.refresh(h)
    return h


# ── Tests ─────────────────────────────────────────────────────────────────────

def test_navigation_requires_auth(client):
    """401 when called without JWT auth."""
    resp = client.get("/ambulances/1/incidents/1")
    assert resp.status_code == 401


def test_navigation_unlinked_driver_forbidden(
    client, driver_and_ambulance, second_driver_and_ambulance
):
    """403 when authenticated driver is not linked to this ambulance."""
    _, a1, token1 = driver_and_ambulance
    _, a2, _ = second_driver_and_ambulance

    headers = {"Authorization": f"Bearer {token1}"}
    resp = client.get(f"/ambulances/{a2.id}/incidents/1", headers=headers)
    assert resp.status_code == 403
    assert "not authorized" in resp.json()["detail"].lower()


def test_navigation_incident_not_found(client, driver_and_ambulance):
    """404 when incident id does not exist."""
    _, a1, token1 = driver_and_ambulance

    headers = {"Authorization": f"Bearer {token1}"}
    resp = client.get(f"/ambulances/{a1.id}/incidents/9999", headers=headers)
    assert resp.status_code == 404
    assert "not found" in resp.json()["detail"].lower()


def test_navigation_incident_not_assigned_to_this_ambulance(
    client, db, driver_and_ambulance, second_driver_and_ambulance
):
    """403 when incident belongs to another ambulance."""
    _, a1, token1 = driver_and_ambulance
    _, a2, _ = second_driver_and_ambulance

    inc = Incident(
        status="ambulance_assigned",
        emergency_type="Trauma",
        severity="high",
        symptoms=["fracture"],
        victims=1,
        location="POINT(76.2673 9.9312)",
        assigned_ambulance_id=a2.id,  # assigned to a2, not a1
    )
    db.add(inc)
    db.commit()
    db.refresh(inc)

    headers = {"Authorization": f"Bearer {token1}"}
    resp = client.get(f"/ambulances/{a1.id}/incidents/{inc.id}", headers=headers)
    assert resp.status_code == 403
    assert "not assigned" in resp.json()["detail"].lower()


def test_navigation_assigned_hospital_null_initially(
    client, db, driver_and_ambulance
):
    """200 with assigned_hospital=None before a hospital accepts the broadcast."""
    _, a1, token1 = driver_and_ambulance

    inc = Incident(
        status="ambulance_assigned",
        emergency_type="Cardiac Arrest",
        severity="critical",
        symptoms=["chest pain", "unconscious"],
        victims=1,
        department_needed="Cardiology",
        transcript="Patient collapsed suddenly.",
        location="POINT(76.2673 9.9312)",
        assigned_ambulance_id=a1.id,
        assigned_hospital_id=None,
    )
    db.add(inc)
    db.commit()
    db.refresh(inc)

    headers = {"Authorization": f"Bearer {token1}"}
    resp = client.get(f"/ambulances/{a1.id}/incidents/{inc.id}", headers=headers)
    assert resp.status_code == 200
    data = resp.json()
    assert data["id"] == inc.id
    assert data["status"] == "ambulance_assigned"
    assert data["severity"] == "critical"
    assert data["emergency_type"] == "Cardiac Arrest"
    assert data["symptoms"] == ["chest pain", "unconscious"]
    assert data["victims"] == 1
    assert data["department_needed"] == "Cardiology"
    assert data["transcript"] == "Patient collapsed suddenly."
    assert "lat" in data["location"] and "lng" in data["location"]
    assert data["assigned_hospital"] is None


def test_navigation_assigned_hospital_populated_after_accept(
    client, db, driver_and_ambulance, hospital
):
    """200 with populated assigned_hospital once a hospital has accepted."""
    _, a1, token1 = driver_and_ambulance

    inc = Incident(
        status="ambulance_assigned",
        emergency_type="Cardiac Arrest",
        severity="critical",
        symptoms=["chest pain"],
        victims=1,
        location="POINT(76.2673 9.9312)",
        assigned_ambulance_id=a1.id,
        assigned_hospital_id=hospital.id,
    )
    db.add(inc)
    db.commit()
    db.refresh(inc)

    headers = {"Authorization": f"Bearer {token1}"}
    resp = client.get(f"/ambulances/{a1.id}/incidents/{inc.id}", headers=headers)
    assert resp.status_code == 200
    data = resp.json()
    assert data["assigned_hospital"] is not None
    assert data["assigned_hospital"]["id"] == hospital.id
    assert data["assigned_hospital"]["name"] == hospital.name
    assert "lat" in data["assigned_hospital"]["location"]
    assert "lng" in data["assigned_hospital"]["location"]

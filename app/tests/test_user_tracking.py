"""
app/tests/test_user_tracking.py
───────────────────────────────
GET /incidents/{incident_id}/tracking (user app live tracking map):
  - 401 without a token
  - 404 for a missing incident
  - 403 for another user's incident; owner and ownerless incidents allowed
  - ambulance and hospital are null until assigned, populated afterwards
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
from app.models.incident_broadcast import IncidentBroadcast
from app.models.incident_ambulance import IncidentAmbulance
from app.models.incident_ambulance_cancellation import IncidentAmbulanceCancellation
from app.core.security import create_access_token
from app.models.user import User

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
    IncidentBroadcast.__table__,
    IncidentAmbulance.__table__,
    IncidentAmbulanceCancellation.__table__,
    User.__table__,
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


# ── Fixtures ──────────────────────────────────────────────────────────────────

@pytest.fixture()
def users(db):
    u1 = User(name="User One", phone="9000000001", email="u1@example.com")
    u2 = User(name="User Two", phone="9000000002", email="u2@example.com")
    db.add_all([u1, u2])
    db.commit()
    db.refresh(u1)
    db.refresh(u2)
    return (u1, create_access_token(u1.id, "user")), (u2, create_access_token(u2.id, "user"))


def _incident(db, **kw):
    inc = Incident(
        status=kw.pop("status", "pending"),
        emergency_type="Cardiac Arrest",
        severity="critical",
        symptoms=["chest pain"],
        victims=1,
        department_needed="Cardiology",
        transcript="Patient collapsed.",
        location="POINT(76.2673 9.9312)",
        **kw,
    )
    db.add(inc)
    db.commit()
    db.refresh(inc)
    return inc


def _auth(token):
    return {"Authorization": f"Bearer {token}"}


# ── Tests ─────────────────────────────────────────────────────────────────────

def test_tracking_requires_auth(client, db):
    inc = _incident(db)
    assert client.get(f"/incidents/{inc.id}/tracking").status_code == 401


def test_tracking_missing_incident(client, users):
    (_, token1), _ = users
    assert client.get("/incidents/99999/tracking", headers=_auth(token1)).status_code == 404


def test_tracking_other_users_incident_forbidden(client, db, users):
    (u1, _), (_, token2) = users
    inc = _incident(db, user_id=u1.id)
    assert client.get(f"/incidents/{inc.id}/tracking", headers=_auth(token2)).status_code == 403


def test_tracking_owner_and_ownerless_allowed(client, db, users):
    (u1, token1), _ = users
    mine = _incident(db, user_id=u1.id)
    ownerless = _incident(db)
    assert client.get(f"/incidents/{mine.id}/tracking", headers=_auth(token1)).status_code == 200
    assert client.get(f"/incidents/{ownerless.id}/tracking", headers=_auth(token1)).status_code == 200


def test_tracking_nothing_assigned_yet(client, db, users):
    (_, token1), _ = users
    inc = _incident(db)
    data = client.get(f"/incidents/{inc.id}/tracking", headers=_auth(token1)).json()
    assert data["status"] == "pending"
    assert data["emergency_type"] == "Cardiac Arrest"
    assert data["symptoms"] == ["chest pain"]
    assert data["transcript"] == "Patient collapsed."
    assert "lat" in data["location"] and "lng" in data["location"]
    assert data["assigned_hospital"] is None
    assert data["ambulance"] is None


def test_tracking_ambulance_and_hospital_populated(client, db, users):
    (_, token1), _ = users
    amb = Ambulance(
        registration_number="KL-07-AA-1111", vehicle_type="ALS",
        is_available=False, is_online=True,
        location="POINT(76.2673 9.9312)",
        location_updated_at=datetime.now(timezone.utc),
    )
    hosp = Hospital(
        name="City General Hospital", location="POINT(76.2800 9.9400)",
        departments=["Cardiology"], is_active=True,
    )
    db.add_all([amb, hosp])
    db.commit()
    inc = _incident(
        db, status="ambulance_assigned",
        assigned_ambulance_id=amb.id, assigned_hospital_id=hosp.id,
    )

    data = client.get(f"/incidents/{inc.id}/tracking", headers=_auth(token1)).json()
    assert data["status"] == "ambulance_assigned"
    assert data["assigned_hospital"]["id"] == hosp.id
    assert data["assigned_hospital"]["name"] == "City General Hospital"
    assert "lat" in data["assigned_hospital"]["location"]
    assert data["ambulance"]["id"] == amb.id
    assert data["ambulance"]["registration_number"] == "KL-07-AA-1111"
    assert "lat" in data["ambulance"]["location"]
    assert data["ambulance"]["location_updated_at"] is not None

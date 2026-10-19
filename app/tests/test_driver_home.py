"""
app/tests/test_driver_home.py
──────────────────────────────
Backend unit tests for the ambulance driver home features:
  - Driver authorization: driver cannot touch an ambulance they are not linked to (403)
  - Online toggle & offline blocked during active incident (409)
  - Incident requests list: only unassigned incidents for this ambulance, empty when offline
  - Atomic accept: two ambulances attempting accept -> exactly one 200, one 409
  - Candidate fan-out on incident creation & backfill on going online
"""

from datetime import datetime, timezone
from unittest.mock import MagicMock, patch

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine, event
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool
from sqlalchemy.ext.compiler import compiles
from sqlalchemy.types import ARRAY
from geoalchemy2.types import Geography

from app.db.base import Base
from app.db import get_db

with patch("faster_whisper.WhisperModel", MagicMock()):
    from app.main import app

from app.models.driver import Driver
from app.models.ambulance import Ambulance
from app.models.ambulance_driver import AmbulanceDriver
from app.models.incident import Incident
from app.models.incident_ambulance import IncidentAmbulance
from app.models.incident_broadcast import IncidentBroadcast
from app.models.hospital import Hospital
from app.models.user import User
from app.core.security import create_driver_token

# ── SQLite in-memory setup with Spatial mock functions ────────────────────────

SQLALCHEMY_DATABASE_URL = "sqlite://"
engine = create_engine(
    SQLALCHEMY_DATABASE_URL,
    connect_args={"check_same_thread": False},
    poolclass=StaticPool,
)


import sqlite3
import json

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


from sqlalchemy.schema import DefaultClause

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
    IncidentAmbulance.__table__,
    IncidentBroadcast.__table__,
    Hospital.__table__,
]

# In SQLite, Postgres typecasts like '{}'::text[] cause syntax errors in DDL
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


# ── Fixtures for driver and ambulance ─────────────────────────────────────────

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
        is_online=False,
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
        is_online=False,
        location="POINT(76.2700 9.9350)",
        location_updated_at=datetime.now(timezone.utc),
    )
    db.add(a2)
    db.flush()

    db.add(AmbulanceDriver(driver_id=d2.id, ambulance_id=a2.id))
    db.commit()

    token2 = create_driver_token(d2.id)
    return d2, a2, token2


# ── Tests ─────────────────────────────────────────────────────────────────────

def test_driver_cannot_access_unlinked_ambulance(
    client, driver_and_ambulance, second_driver_and_ambulance
):
    _, a1, token1 = driver_and_ambulance
    _, a2, _ = second_driver_and_ambulance

    headers = {"Authorization": f"Bearer {token1}"}

    # Driver 1 attempts to toggle online on Ambulance 2 -> 403
    res = client.patch(f"/ambulances/{a2.id}/online", json={"is_online": True}, headers=headers)
    assert res.status_code == 403
    assert "not authorized" in res.json()["detail"].lower()

    # Driver 1 attempts to list incidents for Ambulance 2 -> 403
    res = client.get(f"/ambulances/{a2.id}/incidents", headers=headers)
    assert res.status_code == 403

    # Driver 1 attempts to update location of Ambulance 2 -> 403
    res = client.patch(
        f"/ambulances/{a2.id}/location",
        json={"location": {"lat": 9.9312, "lng": 76.2673}},
        headers=headers,
    )
    assert res.status_code == 403


def test_online_toggle_and_blocked_when_active_incident(
    client, db, driver_and_ambulance
):
    _, a1, token1 = driver_and_ambulance
    headers = {"Authorization": f"Bearer {token1}"}

    # 1. Toggle online
    res = client.patch(
        f"/ambulances/{a1.id}/online",
        json={"is_online": True, "lat": 9.9312, "lng": 76.2673},
        headers=headers,
    )
    assert res.status_code == 200
    assert res.json()["is_online"] is True

    # 2. Simulate assigning an active incident to a1
    inc = Incident(
        location="POINT(76.2673 9.9312)",
        emergency_type="Chest Pain",
        severity="critical",
        status="ambulance_assigned",
        assigned_ambulance_id=a1.id,
    )
    db.add(inc)
    db.commit()

    # 3. Attempt to go offline -> 409 Conflict
    res = client.patch(f"/ambulances/{a1.id}/online", json={"is_online": False}, headers=headers)
    assert res.status_code == 409
    assert "active incident" in res.json()["detail"].lower()

    # 4. Mark incident completed
    inc.status = "completed"
    db.commit()

    # 5. Now going offline succeeds
    res = client.patch(f"/ambulances/{a1.id}/online", json={"is_online": False}, headers=headers)
    assert res.status_code == 200
    assert res.json()["is_online"] is False


def test_requested_incidents_list_offline_and_online(
    client, db, driver_and_ambulance
):
    _, a1, token1 = driver_and_ambulance
    headers = {"Authorization": f"Bearer {token1}"}

    # Create two incidents requested for a1
    i1 = Incident(
        location="POINT(76.2673 9.9312)",
        emergency_type="Accident",
        severity="medium",
        status="pending",
    )
    i2 = Incident(
        location="POINT(76.2680 9.9320)",
        emergency_type="Cardiac Arrest",
        severity="critical",
        status="pending",
    )
    db.add_all([i1, i2])
    db.flush()

    db.add_all([
        IncidentAmbulance(incident_id=i1.id, ambulance_id=a1.id),
        IncidentAmbulance(incident_id=i2.id, ambulance_id=a1.id),
    ])
    db.commit()

    # When offline -> returns empty list
    res = client.get(f"/ambulances/{a1.id}/incidents", headers=headers)
    assert res.status_code == 200
    assert res.json() == []

    # Turn online
    client.patch(f"/ambulances/{a1.id}/online", json={"is_online": True}, headers=headers)

    # When online -> returns both, with critical first
    res = client.get(f"/ambulances/{a1.id}/incidents", headers=headers)
    assert res.status_code == 200
    items = res.json()
    assert len(items) == 2
    assert items[0]["id"] == i2.id  # Critical is first
    assert items[0]["severity"] == "critical"
    assert items[1]["id"] == i1.id
    assert items[1]["severity"] == "medium"


def test_atomic_accept_two_ambulances(
    client, db, driver_and_ambulance, second_driver_and_ambulance
):
    _, a1, token1 = driver_and_ambulance
    _, a2, token2 = second_driver_and_ambulance

    headers1 = {"Authorization": f"Bearer {token1}"}
    headers2 = {"Authorization": f"Bearer {token2}"}

    # Incident requested to both ambulances
    inc = Incident(
        location="POINT(76.2673 9.9312)",
        emergency_type="Stroke",
        severity="high",
        status="pending",
    )
    db.add(inc)
    db.flush()

    db.add_all([
        IncidentAmbulance(incident_id=inc.id, ambulance_id=a1.id),
        IncidentAmbulance(incident_id=inc.id, ambulance_id=a2.id),
    ])
    db.commit()

    # Ambulance 1 accepts
    res1 = client.post(f"/ambulances/{a1.id}/incidents/{inc.id}/accept", headers=headers1)
    assert res1.status_code == 200
    data1 = res1.json()
    assert data1["assigned_ambulance_id"] == a1.id
    assert data1["status"] == "ambulance_assigned"

    # Ambulance 2 tries to accept the same incident -> 409
    res2 = client.post(f"/ambulances/{a2.id}/incidents/{inc.id}/accept", headers=headers2)
    assert res2.status_code == 409
    assert "already accepted" in res2.json()["detail"].lower()

    # inci_ambu requests for this incident are deleted
    links = db.query(IncidentAmbulance).filter_by(incident_id=inc.id).all()
    assert len(links) == 0


def test_backfill_on_going_online(client, db, driver_and_ambulance):
    _, a1, token1 = driver_and_ambulance
    headers = {"Authorization": f"Bearer {token1}"}

    # Incident created while ambulance is offline
    inc = Incident(
        location="POINT(76.2673 9.9312)",
        emergency_type="Asthma",
        severity="medium",
        status="pending",
        created_at=datetime.now(timezone.utc),
    )
    db.add(inc)
    db.commit()

    # Ambulance goes online
    res = client.patch(
        f"/ambulances/{a1.id}/online",
        json={"is_online": True, "lat": 9.9312, "lng": 76.2673},
        headers=headers,
    )
    assert res.status_code == 200

    # Backfill should have linked the incident
    links = db.query(IncidentAmbulance).filter_by(incident_id=inc.id, ambulance_id=a1.id).all()
    assert len(links) == 1


def test_candidate_fan_out_on_manual_incident_creation(
    client, db, driver_and_ambulance, second_driver_and_ambulance
):
    _, a1, token1 = driver_and_ambulance
    _, a2, token2 = second_driver_and_ambulance

    headers1 = {"Authorization": f"Bearer {token1}"}
    headers2 = {"Authorization": f"Bearer {token2}"}

    # Put both ambulances online
    client.patch(f"/ambulances/{a1.id}/online", json={"is_online": True, "lat": 9.9312, "lng": 76.2673}, headers=headers1)
    client.patch(f"/ambulances/{a2.id}/online", json={"is_online": True, "lat": 9.9320, "lng": 76.2680}, headers=headers2)

    # Post an incident
    res = client.post(
        "/incidents/manual",
        json={
            "lat": 9.9315,
            "lng": 76.2675,
            "emergency_type": "Trauma",
            "severity": "critical",
            "victims": 1,
            "symptoms": ["bleeding"],
            "department_needed": "Trauma",
        },
    )
    assert res.status_code == 201
    inc_data = res.json()
    assert inc_data["assigned_ambulance_id"] is None

    # Check inci_ambu table has candidate links for both ambulances
    links = db.query(IncidentAmbulance).filter_by(incident_id=inc_data["id"]).all()
    candidate_amb_ids = {link.ambulance_id for link in links}
    assert a1.id in candidate_amb_ids
    assert a2.id in candidate_amb_ids


def test_fan_out_ignores_offline_or_busy(client, db, driver_and_ambulance):
    _, a1, _ = driver_and_ambulance
    a1.is_online = False  # offline
    db.commit()

    res = client.post(
        "/incidents/manual",
        json={
            "lat": 9.9315,
            "lng": 76.2675,
            "emergency_type": "Fever",
            "severity": "low",
            "victims": 1,
        },
    )
    assert res.status_code == 201
    inc_data = res.json()

    # a1 should NOT be in inci_ambu
    link = db.query(IncidentAmbulance).filter_by(incident_id=inc_data["id"], ambulance_id=a1.id).first()
    assert link is None

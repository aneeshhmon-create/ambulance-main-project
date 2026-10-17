"""
app/tests/test_registration_auth.py
────────────────────────────────────
Backend tests for first-time Google sign-in and registration of drivers,
users and hospital accounts, plus role separation of access tokens.

The Google token verification call is mocked, so no real credentials are
needed. Hospital creation needs PostGIS/ARRAY columns, which the in-memory
SQLite database cannot store, so that path is covered only for its guards
here (bad token, wrong role) and exercised end-to-end against Postgres.
"""

from unittest.mock import patch

import jwt
import pytest
from fastapi.testclient import TestClient

from app.core.config import settings as real_settings
from app.core.security import (
    create_access_token,
    create_registration_token,
)
from app.db import get_db
from app.db.base import Base
from app.models.ambulance import Ambulance
from app.models.ambulance_driver import AmbulanceDriver
from app.models.driver import Driver
from app.models.hospital_account import HospitalAccount
from app.models.user import User
from app.tests.test_driver_auth import (  # noqa: F401  (shared in-memory DB + app)
    TestingSessionLocal,
    app,
    engine,
    override_get_db,
)

_TABLES = [
    Driver.__table__,
    User.__table__,
    HospitalAccount.__table__,
    Ambulance.__table__,
    AmbulanceDriver.__table__,
]


@pytest.fixture(autouse=True)
def setup_db():
    Base.metadata.create_all(bind=engine, tables=_TABLES)
    app.dependency_overrides[get_db] = override_get_db
    yield
    Base.metadata.drop_all(bind=engine, tables=_TABLES)
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


def _google_sign_in(client, email, role, name="Asha Nair"):
    claims = {
        "email": email,
        "email_verified": True,
        "name": name,
        "picture": "https://example.com/p.png",
    }
    with patch("app.routers.auth.settings") as cfg, patch(
        "google.oauth2.id_token.verify_oauth2_token", return_value=claims
    ), patch("google.auth.transport.requests.Request"):
        cfg.GOOGLE_CLIENT_ID = "fake-client-id"
        return client.post("/auth/google", json={"id_token": "t", "role": role})


@pytest.mark.parametrize("role,model", [("driver", Driver), ("user", User)])
class TestPersonRegistration:
    def test_new_google_account_then_register_then_sign_in(self, client, db, role, model):
        first = _google_sign_in(client, "new@gmail.com", role)
        assert first.status_code == 200
        body = first.json()
        assert body["registration_required"] is True
        assert body["google_profile"]["name"] == "Asha Nair"

        reg = client.post(
            f"/auth/register/{role}",
            json={
                "registration_token": body["registration_token"],
                "name": "  Asha K Nair ",
                "phone": "+91 98765-43210",
            },
        )
        assert reg.status_code == 201
        data = reg.json()
        assert data["registration_required"] is False
        assert data["role"] == role
        assert data["account"]["name"] == "Asha K Nair"
        assert data["account"]["phone"] == "9876543210"
        assert data["account"]["email"] == "new@gmail.com"
        assert db.query(model).filter_by(email="new@gmail.com").count() == 1

        # Signing in again goes straight through and keeps the entered name.
        again = _google_sign_in(client, "new@gmail.com", role, name="Google Name")
        assert again.status_code == 200
        assert again.json()["registration_required"] is False
        assert again.json()["account"]["name"] == "Asha K Nair"

    def test_invalid_phone_is_rejected(self, client, role, model):
        token = _google_sign_in(client, "x@gmail.com", role).json()["registration_token"]
        resp = client.post(
            f"/auth/register/{role}",
            json={"registration_token": token, "name": "X", "phone": "12345"},
        )
        assert resp.status_code == 422

    def test_blank_name_is_rejected(self, client, role, model):
        token = _google_sign_in(client, "x@gmail.com", role).json()["registration_token"]
        resp = client.post(
            f"/auth/register/{role}",
            json={"registration_token": token, "name": "   ", "phone": "9876543210"},
        )
        assert resp.status_code == 422

    def test_registering_twice_conflicts(self, client, role, model):
        token = _google_sign_in(client, "dup@gmail.com", role).json()["registration_token"]
        payload = {"registration_token": token, "name": "Dup", "phone": "9876543210"}
        assert client.post(f"/auth/register/{role}", json=payload).status_code == 201
        assert client.post(f"/auth/register/{role}", json=payload).status_code == 409

    def test_garbage_registration_token_is_rejected(self, client, role, model):
        resp = client.post(
            f"/auth/register/{role}",
            json={"registration_token": "nope", "name": "X", "phone": "9876543210"},
        )
        assert resp.status_code == 401

    def test_registration_token_is_role_bound(self, client, role, model):
        other = "user" if role == "driver" else "driver"
        token = create_registration_token(other, "x@gmail.com", "X", None)
        resp = client.post(
            f"/auth/register/{role}",
            json={"registration_token": token, "name": "X", "phone": "9876543210"},
        )
        assert resp.status_code == 401


def test_user_phone_taken_by_google_account_conflicts(client, db):
    db.add(User(name="Taken", phone="9876543210", email="owner@gmail.com"))
    db.commit()
    token = _google_sign_in(client, "new@gmail.com", "user").json()["registration_token"]
    resp = client.post(
        "/auth/register/user",
        json={"registration_token": token, "name": "New", "phone": "9876543210"},
    )
    assert resp.status_code == 409


def test_legacy_phone_only_user_is_adopted(client, db):
    legacy = User(name="Legacy", phone="9876543210")
    db.add(legacy)
    db.commit()
    legacy_id = legacy.id

    token = _google_sign_in(client, "new@gmail.com", "user").json()["registration_token"]
    resp = client.post(
        "/auth/register/user",
        json={"registration_token": token, "name": "Renamed", "phone": "98765 43210"},
    )
    assert resp.status_code == 201
    assert resp.json()["account"]["id"] == legacy_id
    db.expire_all()
    adopted = db.get(User, legacy_id)
    assert adopted.email == "new@gmail.com"
    assert adopted.name == "Renamed"
    assert db.query(User).count() == 1


def test_hospital_unknown_email_requires_registration(client):
    resp = _google_sign_in(client, "hosp@gmail.com", "hospital")
    assert resp.status_code == 200
    assert resp.json()["registration_required"] is True
    assert resp.json()["role"] == "hospital"


def test_hospital_registration_rejects_wrong_role_token(client):
    token = create_registration_token("driver", "hosp@gmail.com", "H", None)
    resp = client.post(
        "/auth/register/hospital",
        json={
            "registration_token": token,
            "hospital": {"name": "H", "location": {"lat": 9.9, "lng": 76.2}, "departments": []},
        },
    )
    assert resp.status_code == 401


def test_existing_hospital_account_signs_in(client, db):
    db.add(HospitalAccount(email="hosp@gmail.com", name="Admin", hospital_id=7))
    db.commit()
    resp = _google_sign_in(client, "hosp@gmail.com", "hospital")
    assert resp.status_code == 200
    data = resp.json()
    assert data["registration_required"] is False
    assert data["account"]["hospital_id"] == 7


class TestTokenRoles:
    def test_me_returns_account_for_each_role(self, client, db):
        db.add_all([Driver(name="D", email="d@gmail.com"), User(name="U", phone="9876543210", email="u@gmail.com")])
        db.commit()
        for role, model in (("driver", Driver), ("user", User)):
            account = db.query(model).first()
            token = create_access_token(account.id, role)
            resp = client.get("/auth/me", headers={"Authorization": f"Bearer {token}"})
            assert resp.status_code == 200
            assert resp.json()["role"] == role
            assert resp.json()["account"]["id"] == account.id

    def test_user_token_cannot_use_driver_endpoint(self, client, db):
        user = User(name="U", phone="9876543210", email="u@gmail.com")
        db.add(user)
        db.commit()
        token = create_access_token(user.id, "user")
        resp = client.get("/drivers/me/ambulances", headers={"Authorization": f"Bearer {token}"})
        assert resp.status_code == 401

    def test_registration_token_cannot_authenticate(self, client):
        token = create_registration_token("driver", "x@gmail.com", "X", None)
        resp = client.get("/auth/me", headers={"Authorization": f"Bearer {token}"})
        assert resp.status_code == 401
        resp = client.get("/drivers/me/ambulances", headers={"Authorization": f"Bearer {token}"})
        assert resp.status_code == 401

    def test_legacy_token_without_role_is_a_driver_token(self, client, db):
        driver = Driver(name="D", email="d@gmail.com")
        db.add(driver)
        db.commit()
        legacy = jwt.encode({"sub": str(driver.id)}, real_settings.JWT_SECRET, algorithm="HS256")
        resp = client.get("/drivers/me/ambulances", headers={"Authorization": f"Bearer {legacy}"})
        assert resp.status_code == 200


class TestDevLoginRegistration:
    def test_unknown_email_returns_registration_token(self, client):
        with patch("app.routers.auth.settings") as cfg:
            cfg.ALLOW_DEV_LOGIN = True
            resp = client.post(
                "/auth/dev-login", json={"email": "someone@example.com", "role": "user"}
            )
        assert resp.status_code == 200
        assert resp.json()["registration_required"] is True
        assert resp.json()["google_profile"]["name"] == "someone"

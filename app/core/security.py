"""
app/core/security.py
─────────────────────
JWT issuance and validation for the Google sign-in system (drivers, users
and hospital dashboard accounts).

Two kinds of token exist:

  • access token        – `sub` (account id) + `role`; proves who is signed in.
  • registration token  – short-lived, carries the verified Google identity
                          (email/name/photo) of someone who has no account
                          yet. It is only accepted by POST /auth/register/*
                          and can never authenticate a request.

Usage
─────
  token = create_access_token(account_id=42, role="driver")

  @router.get("/protected")
  def protected(driver: Driver = Depends(get_current_driver)):
      ...
"""

import logging
from datetime import datetime, timedelta, timezone

import jwt
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.orm import Session

from app.core.config import settings
from app.db import get_db
from app.models.driver import Driver
from app.models.hospital_account import HospitalAccount
from app.models.user import User

logger = logging.getLogger(__name__)

_ALGORITHM = "HS256"
_REGISTRATION_PURPOSE = "registration"
_REGISTRATION_EXPIRE_MINUTES = 15
_bearer_scheme = HTTPBearer(auto_error=False)


# ── Token creation ────────────────────────────────────────────────────────────

def create_access_token(account_id: int, role: str) -> str:
    """Issue a signed JWT for the given account and role."""
    now = datetime.now(timezone.utc)
    payload = {
        "sub": str(account_id),
        "role": role,
        "exp": now + timedelta(minutes=settings.JWT_EXPIRE_MINUTES),
        "iat": now,
    }
    return jwt.encode(payload, settings.JWT_SECRET, algorithm=_ALGORITHM)


def create_driver_token(driver_id: int) -> str:
    """Issue an access token for a driver (kept for existing callers/tests)."""
    return create_access_token(driver_id, "driver")


def create_registration_token(
    role: str, email: str, name: str, photo_url: str | None
) -> str:
    """
    Issue a short-lived token that vouches for a verified Google identity
    which has no account for `role` yet. Contains no `sub`, so it cannot be
    used as an access token.
    """
    now = datetime.now(timezone.utc)
    payload = {
        "purpose": _REGISTRATION_PURPOSE,
        "role": role,
        "email": email,
        "name": name,
        "picture": photo_url,
        "exp": now + timedelta(minutes=_REGISTRATION_EXPIRE_MINUTES),
        "iat": now,
    }
    return jwt.encode(payload, settings.JWT_SECRET, algorithm=_ALGORITHM)


def decode_registration_token(token: str, role: str) -> dict:
    """
    Validate a registration token for `role` and return its claims.
    Raises HTTP 401 if it is invalid, expired or issued for another role.
    """
    try:
        payload = jwt.decode(token, settings.JWT_SECRET, algorithms=[_ALGORITHM])
    except jwt.ExpiredSignatureError:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Registration session expired. Please sign in with Google again.",
        )
    except jwt.PyJWTError:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid registration token.",
        )

    if payload.get("purpose") != _REGISTRATION_PURPOSE or payload.get("role") != role:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid registration token.",
        )
    return payload


# ── Token validation ──────────────────────────────────────────────────────────

def _decode_access_token(
    credentials: HTTPAuthorizationCredentials | None, role: str | None
) -> tuple[str, int]:
    """
    Validate the Bearer JWT and return (role, account id). When `role` is
    given the token must have been issued for it.

    Raises HTTP 401 if the token is missing, malformed, expired, a
    registration token, or issued for a different role.
    """
    _401 = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Missing or invalid authentication token.",
        headers={"WWW-Authenticate": "Bearer"},
    )

    if credentials is None:
        raise _401

    try:
        payload = jwt.decode(
            credentials.credentials,
            settings.JWT_SECRET,
            algorithms=[_ALGORITHM],
        )
    except jwt.ExpiredSignatureError:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Token has expired. Please sign in again.",
            headers={"WWW-Authenticate": "Bearer"},
        )
    except jwt.PyJWTError:
        raise _401

    if "purpose" in payload:
        raise _401
    # Tokens issued before roles existed were driver tokens.
    token_role = payload.get("role", "driver")
    if role is not None and token_role != role:
        raise _401

    try:
        return token_role, int(payload.get("sub"))
    except (TypeError, ValueError):
        raise _401


def _account_or_401(db: Session, model, account_id: int):
    account = db.get(model, account_id)
    if not account:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Missing or invalid authentication token.",
            headers={"WWW-Authenticate": "Bearer"},
        )
    return account


def get_current_driver(
    credentials: HTTPAuthorizationCredentials | None = Depends(_bearer_scheme),
    db: Session = Depends(get_db),
) -> Driver:
    """
    FastAPI dependency — validates the Bearer JWT and returns the Driver row.

    Raises HTTP 401 if the token is missing, malformed, or expired.
    Raises HTTP 403 if the driver account has been deactivated.
    """
    _, driver_id = _decode_access_token(credentials, "driver")
    driver = _account_or_401(db, Driver, driver_id)
    if not driver.is_active:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="This driver account has been deactivated.",
        )
    return driver


def get_current_user(
    credentials: HTTPAuthorizationCredentials | None = Depends(_bearer_scheme),
    db: Session = Depends(get_db),
) -> User:
    """FastAPI dependency — validates the Bearer JWT and returns the User row."""
    _, user_id = _decode_access_token(credentials, "user")
    return _account_or_401(db, User, user_id)


def get_current_hospital_account(
    credentials: HTTPAuthorizationCredentials | None = Depends(_bearer_scheme),
    db: Session = Depends(get_db),
) -> HospitalAccount:
    """FastAPI dependency — validates the Bearer JWT and returns the HospitalAccount."""
    _, account_id = _decode_access_token(credentials, "hospital")
    return _account_or_401(db, HospitalAccount, account_id)


_ROLE_MODELS = {"driver": Driver, "user": User, "hospital": HospitalAccount}


def get_current_account(
    credentials: HTTPAuthorizationCredentials | None = Depends(_bearer_scheme),
    db: Session = Depends(get_db),
) -> tuple[str, Driver | User | HospitalAccount]:
    """FastAPI dependency — returns (role, account) for any valid access token."""
    role, account_id = _decode_access_token(credentials, None)
    model = _ROLE_MODELS.get(role)
    if model is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Missing or invalid authentication token.",
            headers={"WWW-Authenticate": "Bearer"},
        )
    account = _account_or_401(db, model, account_id)
    if role == "driver" and not account.is_active:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="This driver account has been deactivated.",
        )
    return role, account

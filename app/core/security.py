"""
app/core/security.py
─────────────────────
JWT issuance and validation for the driver authentication system.

Usage
─────
  # Create a token after successful Google sign-in:
  token = create_driver_token(driver_id=42)

  # FastAPI dependency for protected endpoints:
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

logger = logging.getLogger(__name__)

_ALGORITHM = "HS256"
_bearer_scheme = HTTPBearer(auto_error=False)


# ── Token creation ────────────────────────────────────────────────────────────

def create_driver_token(driver_id: int) -> str:
    """
    Issue a signed JWT for the given driver.
    The token carries `sub` (driver id as string) and `exp`.
    """
    expire = datetime.now(timezone.utc) + timedelta(
        minutes=settings.JWT_EXPIRE_MINUTES
    )
    payload = {
        "sub": str(driver_id),
        "exp": expire,
        "iat": datetime.now(timezone.utc),
    }
    return jwt.encode(payload, settings.JWT_SECRET, algorithm=_ALGORITHM)


# ── Token validation dependency ───────────────────────────────────────────────

def get_current_driver(
    credentials: HTTPAuthorizationCredentials | None = Depends(_bearer_scheme),
    db: Session = Depends(get_db),
) -> Driver:
    """
    FastAPI dependency — validates the Bearer JWT and returns the Driver row.

    Raises HTTP 401 if the token is missing, malformed, or expired.
    Raises HTTP 403 if the driver account has been deactivated.
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

    driver_id_str = payload.get("sub")
    if not driver_id_str:
        raise _401

    try:
        driver_id = int(driver_id_str)
    except ValueError:
        raise _401

    driver = db.get(Driver, driver_id)
    if not driver:
        raise _401

    if not driver.is_active:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="This driver account has been deactivated.",
        )

    return driver

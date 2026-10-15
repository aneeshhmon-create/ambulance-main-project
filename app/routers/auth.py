"""
app/routers/auth.py
────────────────────
Driver authentication endpoints.

Endpoints
─────────
POST /auth/google
    Verifies a Google ID token on the server, looks up the driver by
    verified email, and returns our own short-lived JWT.

POST /auth/dev-login   (only when ALLOW_DEV_LOGIN=true in .env)
    Skips Google verification for local development when Google OAuth
    is not yet configured. Logs a loud warning at every call. This
    endpoint cannot be reached at all when ALLOW_DEV_LOGIN=false.
"""

import logging

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.security import create_driver_token
from app.db import get_db
from app.models.driver import Driver
from app.schemas.driver import (
    DevLoginRequest,
    DriverProfileOut,
    GoogleTokenRequest,
    TokenResponse,
)

logger = logging.getLogger(__name__)

router = APIRouter()


# ── Helper ────────────────────────────────────────────────────────────────────

def _driver_to_token_response(driver: Driver) -> TokenResponse:
    """Build the standard token response for a successfully authenticated driver."""
    token = create_driver_token(driver.id)
    return TokenResponse(
        access_token=token,
        token_type="bearer",
        driver=DriverProfileOut(
            id=driver.id,
            name=driver.name,
            email=driver.email,
            photo_url=driver.photo_url,
        ),
    )


def _lookup_driver(email: str, db: Session) -> Driver:
    """
    Find an active driver by verified email.
    Raises HTTP 403 with a clear message if not found or inactive.
    """
    driver = db.query(Driver).filter_by(email=email).first()
    if not driver or not driver.is_active:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=(
                "This Google account is not registered as a driver. "
                "Contact your administrator to be added to the system."
            ),
        )
    return driver


# ── POST /auth/google ─────────────────────────────────────────────────────────

@router.post(
    "/google",
    response_model=TokenResponse,
    summary="Sign in with Google ID token",
)
def google_sign_in(body: GoogleTokenRequest, db: Session = Depends(get_db)):
    """
    Verify a Google ID token (issued by the mobile app) on the server.

    Flow:
      1. Verify the token's signature, expiry, and audience against
         GOOGLE_CLIENT_ID using google.oauth2.id_token — **never trust
         email sent directly from the client**.
      2. Require email_verified=true in the token claims.
      3. Look up the driver by the verified email.
      4. Return our own JWT if the driver is active.

    Returns HTTP 403 if the email is not registered or inactive.
    Returns HTTP 401 if the Google token is invalid or expired.
    """
    if not settings.GOOGLE_CLIENT_ID:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=(
                "Google authentication is not configured on this server. "
                "Set GOOGLE_CLIENT_ID in .env, or use /auth/dev-login if enabled."
            ),
        )

    # Verify the ID token with Google's public keys.
    # This import is deferred so the app can start without google-auth
    # installed in environments that only use dev-login.
    try:
        from google.oauth2 import id_token as google_id_token
        from google.auth.transport import requests as google_requests

        id_info = google_id_token.verify_oauth2_token(
            body.id_token,
            google_requests.Request(),
            settings.GOOGLE_CLIENT_ID,
        )
    except ValueError as exc:
        # verify_oauth2_token raises ValueError for any validation failure
        logger.warning("Google token verification failed: %s", exc)
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired Google ID token.",
        )

    if not id_info.get("email_verified"):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Google account email is not verified.",
        )

    verified_email: str = id_info["email"]
    photo_url: str | None = id_info.get("picture")
    name: str = id_info.get("name", verified_email)

    driver = _lookup_driver(verified_email, db)

    # Opportunistically update the driver's display name and photo_url
    # from the Google token so the app always shows fresh data.
    if driver.photo_url != photo_url or driver.name != name:
        driver.photo_url = photo_url
        driver.name = name
        db.commit()

    return _driver_to_token_response(driver)


# ── POST /auth/dev-login ──────────────────────────────────────────────────────
# This endpoint is registered by app/main.py only when ALLOW_DEV_LOGIN=true.
# It is defined here for colocation but the router is mounted conditionally.

@router.post(
    "/dev-login",
    response_model=TokenResponse,
    summary="[DEV ONLY] Sign in by email without Google verification",
    include_in_schema=settings.ALLOW_DEV_LOGIN,  # hide from docs when off
)
def dev_login(body: DevLoginRequest, db: Session = Depends(get_db)):
    """
    **Development only** — skips Google token verification entirely.

    Only reachable when ALLOW_DEV_LOGIN=true in .env.
    A loud WARNING is logged on every call.
    """
    logger.warning(
        "⚠️  DEV LOGIN used for email '%s'. "
        "ALLOW_DEV_LOGIN must be false in production!",
        body.email,
    )
    driver = _lookup_driver(body.email, db)
    return _driver_to_token_response(driver)

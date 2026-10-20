"""
app/routers/auth.py
────────────────────
Google sign-in for the driver app, the user app and the hospital dashboard.

Endpoints
─────────
POST /auth/google
    Verifies a Google ID token on the server and looks up the account for
    the requested role (driver | user | hospital) by verified email.
    • Account exists  → returns our own JWT and the account.
    • No account yet  → returns `registration_required: true` plus a
      short-lived `registration_token`; the app then collects the missing
      details and calls POST /auth/register/{role}.

POST /auth/register/driver | /auth/register/user
    Creates the account from the registration token + name and phone.

POST /auth/register/hospital
    Creates the hospital (name, location, departments) and the dashboard
    account that manages it.

GET /auth/me
    Returns the account behind the Bearer token (used to restore a session).

POST /auth/dev-login   (only when ALLOW_DEV_LOGIN=true in .env)
    Same lookup as /auth/google but skips Google verification, for local
    development before Google OAuth is configured. Logs a loud warning at
    every call and returns 404 when ALLOW_DEV_LOGIN=false.
"""

import logging

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.security import (
    create_access_token,
    create_registration_token,
    decode_registration_token,
    get_current_account,
)
from app.db import get_db
from app.models.driver import Driver
from app.models.hospital import Hospital
from app.models.hospital_account import HospitalAccount
from app.models.user import User
from app.routers.hospitals import _wkt_point
from app.routers.users import normalize_phone
from app.schemas.auth import (
    AccountOut,
    AuthResponse,
    DevLoginRequest,
    GoogleProfile,
    GoogleTokenRequest,
    RegisterHospitalRequest,
    RegisterPersonRequest,
    Role,
)

logger = logging.getLogger(__name__)

router = APIRouter()


# ── Helpers ───────────────────────────────────────────────────────────────────

def _account_out(role: Role, account) -> AccountOut:
    return AccountOut(
        id=account.id,
        name=account.name,
        email=account.email,
        photo_url=account.photo_url,
        phone=getattr(account, "phone", None),
        hospital_id=account.hospital_id if role == "hospital" else None,
    )


def _signed_in(role: Role, account) -> AuthResponse:
    return AuthResponse(
        role=role,
        access_token=create_access_token(account.id, role),
        account=_account_out(role, account),
    )


def _find_account(role: Role, email: str, db: Session):
    """Return the existing account for (role, email) or None."""
    model = {"driver": Driver, "user": User, "hospital": HospitalAccount}[role]
    account = db.query(model).filter_by(email=email).first()
    if role == "driver" and account and not account.is_active:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="This driver account has been deactivated.",
        )
    return account


def _sign_in_or_prompt_registration(
    role: Role, email: str, name: str, photo_url: str | None, db: Session
) -> AuthResponse:
    """Sign in an existing account, or ask the client to register a new one."""
    account = _find_account(role, email, db)
    if account is None:
        return AuthResponse(
            registration_required=True,
            role=role,
            registration_token=create_registration_token(role, email, name, photo_url),
            google_profile=GoogleProfile(email=email, name=name, photo_url=photo_url),
        )

    # Keep the Google profile picture fresh. The name is deliberately left
    # alone: it was entered by the person during registration.
    if photo_url and account.photo_url != photo_url:
        account.photo_url = photo_url
        db.commit()
    return _signed_in(role, account)


def _verify_google_token(token: str) -> dict:
    """
    Verify a Google ID token (or, for Flutter Web, an OAuth access token)
    and return its claims. Raises HTTP 401 / 503 on failure.
    """
    if not settings.GOOGLE_CLIENT_ID:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=(
                "Google authentication is not configured on this server. "
                "Set GOOGLE_CLIENT_ID in .env, or use /auth/dev-login if enabled."
            ),
        )

    # Deferred import so the app can start without google-auth installed in
    # environments that only use dev-login.
    id_info = None
    try:
        from google.oauth2 import id_token as google_id_token
        from google.auth.transport import requests as google_requests

        id_info = google_id_token.verify_oauth2_token(
            token,
            google_requests.Request(),
            settings.GOOGLE_CLIENT_ID,
        )
    except Exception as exc:
        # verify_oauth2_token raises ValueError or GoogleAuthError for validation failure,
        # including when an OAuth2 access token is passed from Flutter Web.
        # Fall back to validating the access token with Google's endpoints.
        try:
            import requests as py_requests

            token_resp = py_requests.get(
                "https://oauth2.googleapis.com/tokeninfo",
                params={"access_token": token},
                timeout=5,
            )
            if token_resp.status_code == 200:
                token_data = token_resp.json()
                token_aud = token_data.get("aud") or token_data.get("azp")
                if token_aud == settings.GOOGLE_CLIENT_ID:
                    user_resp = py_requests.get(
                        "https://www.googleapis.com/oauth2/v3/userinfo",
                        headers={"Authorization": f"Bearer {token}"},
                        timeout=5,
                    )
                    if user_resp.status_code == 200:
                        id_info = user_resp.json()
        except Exception as fallback_exc:
            logger.warning("Google access token fallback check failed: %s", fallback_exc)

        if not id_info:
            logger.warning("Google token verification failed: %s", exc)
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail=f"Invalid or expired Google ID token: {exc}",
            )

    email_verified = id_info.get("email_verified")
    if isinstance(email_verified, str):
        email_verified = email_verified.lower() == "true"
    if not email_verified:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Google account email is not verified.",
        )
    return id_info


# ── POST /auth/google ─────────────────────────────────────────────────────────

@router.post(
    "/google",
    response_model=AuthResponse,
    summary="Sign in with Google ID token",
)
def google_sign_in(body: GoogleTokenRequest, db: Session = Depends(get_db)):
    """
    Verify a Google ID token on the server and sign in (or start registration).

    Flow:
      1. Verify the token's signature, expiry and audience against
         GOOGLE_CLIENT_ID — **never trust an email sent by the client**.
      2. Require email_verified=true.
      3. Look up the account for `role` by the verified email.
      4. Existing account → our JWT. No account → `registration_required`
         with a registration token for POST /auth/register/{role}.

    Returns HTTP 401 if the Google token is invalid or expired and HTTP 403
    if a driver account has been deactivated.
    """
    id_info = _verify_google_token(body.id_token)
    email: str = id_info["email"]
    return _sign_in_or_prompt_registration(
        body.role,
        email,
        id_info.get("name") or email,
        id_info.get("picture"),
        db,
    )


# ── POST /auth/register/* ─────────────────────────────────────────────────────

def _register_person(
    model, role: Role, body: RegisterPersonRequest, db: Session
) -> AuthResponse:
    claims = decode_registration_token(body.registration_token, role)
    email: str = claims["email"]

    name = body.name.strip()
    if not name:
        raise HTTPException(status_code=422, detail="Name cannot be blank.")
    phone = normalize_phone(body.phone)

    if db.query(model).filter_by(email=email).first():
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="This Google account is already registered. Please sign in.",
        )

    account = None
    if model is User:
        existing = db.query(User).filter_by(phone=phone).first()
        if existing and existing.email is not None:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="This phone number is already registered to another account.",
            )
        if existing:
            # Created before Google sign-in (phone only): adopt it so the
            # person keeps their incident history.
            existing.name = name
            existing.email = email
            existing.photo_url = claims.get("picture")
            account = existing

    if account is None:
        account = model(
            name=name,
            email=email,
            phone=phone,
            photo_url=claims.get("picture"),
        )
        db.add(account)
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="This account or phone number is already registered.",
        )
    db.refresh(account)
    return _signed_in(role, account)


@router.post(
    "/register/driver",
    response_model=AuthResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Complete driver registration after Google sign-in",
)
def register_driver(body: RegisterPersonRequest, db: Session = Depends(get_db)):
    """Create a driver from the registration token plus name and phone."""
    return _register_person(Driver, "driver", body, db)


@router.post(
    "/register/user",
    response_model=AuthResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Complete user registration after Google sign-in",
)
def register_user(body: RegisterPersonRequest, db: Session = Depends(get_db)):
    """Create a user from the registration token plus name and phone."""
    return _register_person(User, "user", body, db)


@router.post(
    "/register/hospital",
    response_model=AuthResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Complete hospital registration after Google sign-in",
)
def register_hospital(body: RegisterHospitalRequest, db: Session = Depends(get_db)):
    """Create the hospital and the dashboard account that manages it."""
    claims = decode_registration_token(body.registration_token, "hospital")
    email: str = claims["email"]

    if db.query(HospitalAccount).filter_by(email=email).first():
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="This Google account is already registered. Please sign in.",
        )

    h = body.hospital
    hospital = Hospital(
        name=h.name.strip(),
        location=_wkt_point(h.location.lat, h.location.lng),
        departments=h.departments,
    )
    db.add(hospital)
    db.flush()

    account = HospitalAccount(
        email=email,
        name=claims.get("name") or email,
        photo_url=claims.get("picture"),
        hospital_id=hospital.id,
    )
    db.add(account)
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="This Google account is already registered. Please sign in.",
        )
    db.refresh(account)
    return _signed_in("hospital", account)


# ── GET /auth/me ──────────────────────────────────────────────────────────────

@router.get(
    "/me",
    response_model=AuthResponse,
    summary="Get the account behind the Bearer token",
)
def me(current=Depends(get_current_account)):
    """Validate the token and return the signed-in account (no new token)."""
    role, account = current
    return AuthResponse(role=role, account=_account_out(role, account))


# ── POST /auth/dev-login ──────────────────────────────────────────────────────

@router.post(
    "/dev-login",
    response_model=AuthResponse,
    summary="[DEV ONLY] Sign in by email without Google verification",
    include_in_schema=settings.ALLOW_DEV_LOGIN,  # hide from docs when off
)
def dev_login(body: DevLoginRequest, db: Session = Depends(get_db)):
    """
    **Development only** — skips Google token verification entirely.

    Only usable when ALLOW_DEV_LOGIN=true in .env; otherwise returns 404.
    A loud WARNING is logged on every call. Behaves like /auth/google: an
    unknown email gets `registration_required` so the registration screens
    can be exercised without a Google account.
    """
    if not settings.ALLOW_DEV_LOGIN:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Dev login is disabled.",
        )
    logger.warning(
        "⚠️  DEV LOGIN used for %s '%s'. "
        "ALLOW_DEV_LOGIN must be false in production!",
        body.role,
        body.email,
    )
    return _sign_in_or_prompt_registration(
        body.role, body.email, body.name or body.email.split("@")[0], None, db
    )

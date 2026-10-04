"""
app/routers/users.py
────────────────────
CRUD endpoints for the User resource.

Endpoints
─────────
POST /users     – Register / get-or-create user by phone
GET  /users/{id} – Fetch a user by primary-key ID
"""

from fastapi import APIRouter, Depends, HTTPException, Response, status
from sqlalchemy.orm import Session

from app.db import get_db
from app.models.user import User
from app.schemas.user import UserCreate, UserOut

router = APIRouter()


def normalize_phone(phone: str) -> str:
    """
    Normalize Indian phone numbers:
    - Strips spaces and dashes.
    - Strips leading '+91' or '0'.
    - Requires exactly 10 digits afterwards.
    - Otherwise raises HTTP 422 with a clear message.
    """
    cleaned = phone.strip().replace(" ", "").replace("-", "")
    if cleaned.startswith("+91"):
        cleaned = cleaned[3:]
    if cleaned.startswith("0"):
        cleaned = cleaned[1:]

    if not (cleaned.isdigit() and len(cleaned) == 10):
        raise HTTPException(
            status_code=422,
            detail=(
                f"Invalid phone number '{phone}'. Phone number must contain "
                "exactly 10 digits after removing spaces, dashes, or a leading '+91' / '0'."
            ),
        )
    return cleaned


@router.post(
    "",
    response_model=UserOut,
    status_code=status.HTTP_201_CREATED,
    summary="Register or fetch existing user by phone",
)
def create_or_get_user(
    body: UserCreate,
    response: Response,
    db: Session = Depends(get_db),
):
    """
    Get-or-create a user by normalized phone number:
    - If a user with that phone exists: update the name if it differs,
      and return the user with HTTP 200.
    - Otherwise: create the user and return it with HTTP 201.
    """
    normalized_phone = normalize_phone(body.phone)
    name = body.name.strip()
    if not name:
        raise HTTPException(
            status_code=422,
            detail="User name cannot be blank.",
        )

    user = db.query(User).filter(User.phone == normalized_phone).first()

    if user:
        if user.name != name:
            user.name = name
            db.commit()
            db.refresh(user)
        response.status_code = status.HTTP_200_OK
        return user

    new_user = User(
        name=name,
        phone=normalized_phone,
    )
    db.add(new_user)
    db.commit()
    db.refresh(new_user)
    response.status_code = status.HTTP_201_CREATED
    return new_user


@router.get(
    "/{user_id}",
    response_model=UserOut,
    summary="Get user by ID",
)
def get_user(
    user_id: int,
    db: Session = Depends(get_db),
):
    """Fetch a single user by primary-key ID. Returns 404 if missing."""
    user = db.get(User, user_id)
    if not user:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"User with ID {user_id} not found",
        )
    return user

"""
app/schemas/user.py
───────────────────
Pydantic v2 schemas for the User resource.
"""

from datetime import datetime
from pydantic import BaseModel, Field, ConfigDict


class UserCreate(BaseModel):
    """Body accepted by POST /users."""
    name: str = Field(..., min_length=1, max_length=255, description="Full name of user")
    phone: str = Field(..., min_length=1, description="Raw phone number (spaces, dashes, +91, 0 accepted)")


class UserOut(BaseModel):
    """Standard response for a User."""
    model_config = ConfigDict(from_attributes=True)

    id: int
    name: str
    phone: str
    created_at: datetime

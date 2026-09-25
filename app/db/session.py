"""
app/db/session.py
─────────────────
Creates the SQLAlchemy engine and session factory.
`get_db` is a FastAPI dependency that yields a DB session per request
and guarantees it is closed even if an exception is raised.
"""

from sqlalchemy import create_engine
from typing import Generator

from sqlalchemy.orm import sessionmaker, Session
from app.core.config import settings

engine = create_engine(
    settings.DATABASE_URL,
    pool_pre_ping=True,   # automatically reconnects on stale connections
    echo=settings.APP_ENV == "development",  # log SQL in dev only
)

SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)


def get_db() -> Generator[Session, None, None]:
    """FastAPI dependency — use with `Depends(get_db)`."""
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

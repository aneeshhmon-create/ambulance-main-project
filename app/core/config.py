"""
app/core/config.py
──────────────────
Centralised settings using Pydantic v2's BaseSettings.
Values are read from environment variables / .env file automatically.
Access anywhere via:  from app.core.config import settings
"""

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    APP_ENV: str = "development"
    SECRET_KEY: str = "change-me"

    # Database
    DATABASE_URL: str = (
        "postgresql+psycopg2://postgres:postgres@db:5432/ambulance_db"
    )

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        case_sensitive=True,
        extra="ignore",   # silently drop POSTGRES_* and any other undeclared vars
    )


settings = Settings()

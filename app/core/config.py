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

    # ── Driver authentication ─────────────────────────────────────────────────
    # Google Web OAuth 2.0 client ID — used to verify ID tokens on the server.
    # Must match the serverClientId passed to google_sign_in in the Flutter app.
    GOOGLE_CLIENT_ID: str = ""

    # Secret key for signing / verifying our own JWT access tokens.
    JWT_SECRET: str = "change-me-jwt-secret"

    # Token lifetime in minutes. Default = 7 days.
    JWT_EXPIRE_MINUTES: int = 10080

    # When true, the POST /auth/dev-login endpoint is enabled so developers
    # can test without a real Google token. MUST be false in production.
    ALLOW_DEV_LOGIN: bool = False

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        case_sensitive=True,
        extra="ignore",   # silently drop POSTGRES_* and any other undeclared vars
    )


settings = Settings()

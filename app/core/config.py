"""
app/core/config.py
──────────────────
Centralised settings using Pydantic v2's BaseSettings.
Values are read from environment variables / .env file automatically.
Access anywhere via:  from app.core.config import settings
"""

from pydantic import model_validator
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

    # Comma-separated browser origins allowed by CORS outside development,
    # e.g. "https://dash.example.com". Native mobile apps don't need CORS.
    CORS_ORIGINS: str = ""

    # ── Ambulance dispatch tuning ─────────────────────────────────────────────
    CANDIDATE_RADIUS_KM: float = 15.0
    MAX_AMBULANCES_PER_INCIDENT: int = 5
    LOCATION_FRESHNESS_SECONDS: int = 120
    BACKFILL_WINDOW_MINUTES: int = 30

    @property
    def cors_origin_list(self) -> list[str]:
        return [o.strip() for o in self.CORS_ORIGINS.split(",") if o.strip()]

    @model_validator(mode="after")
    def _reject_insecure_production(self) -> "Settings":
        """Refuse to start in production with default secrets or dev login on."""
        if self.APP_ENV != "production":
            return self
        problems = []
        if self.SECRET_KEY == "change-me":
            problems.append("SECRET_KEY is still the default")
        if self.JWT_SECRET == "change-me-jwt-secret":
            problems.append("JWT_SECRET is still the default")
        if self.ALLOW_DEV_LOGIN:
            problems.append("ALLOW_DEV_LOGIN must be false")
        if problems:
            raise ValueError("Insecure production config: " + "; ".join(problems))
        return self

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        case_sensitive=True,
        extra="ignore",   # silently drop POSTGRES_* and any other undeclared vars
    )


settings = Settings()

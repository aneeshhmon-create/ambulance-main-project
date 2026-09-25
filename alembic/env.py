"""
alembic/env.py
──────────────
Alembic environment configuration.
- Reads DATABASE_URL from app.core.config.settings (→ .env).
- Imports Base + all models so autogenerate detects every table.
- Restricts autogenerate to the `public` schema only, so that PostGIS
  system tables in `tiger`, `topology`, etc. are never touched.
- Supports both offline (SQL dump) and online (live DB) migration modes.
"""

import os
import sys
from logging.config import fileConfig

from sqlalchemy import engine_from_config, pool
from alembic import context

# ── Make project root importable ────────────────────────────────────────────
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

# ── Project imports ──────────────────────────────────────────────────────────
from app.core.config import settings          # noqa: E402
from app.db.base import Base                  # noqa: E402  (also imports all models)
import app.models                             # noqa: E402, F401  ensure all models loaded

# ── Alembic Config object ────────────────────────────────────────────────────
config = context.config

# Override sqlalchemy.url with the value from our settings / .env
config.set_main_option("sqlalchemy.url", settings.DATABASE_URL)

# Interpret the config file for Python logging.
if config.config_file_name is not None:
    fileConfig(config.config_file_name)

# Metadata for autogenerate
target_metadata = Base.metadata


def include_object(object, name, type_, reflected, compare_to):
    """
    Only manage objects that live in the `public` schema (our app tables).
    PostGIS ships tables into `tiger`, `tiger_data`, `topology`, and also
    creates views/functions in `public` we should not touch.
    Any reflected table not in our metadata is silently skipped.
    """
    if type_ == "table":
        # Skip any table outside the public schema
        schema = getattr(object, "schema", None)
        if schema is not None and schema != "public":
            return False
        # Skip reflected public tables that don't belong to our models
        if reflected and compare_to is None:
            return False
    return True


# ── Offline mode ─────────────────────────────────────────────────────────────
def run_migrations_offline() -> None:
    """Run migrations without an actual DB connection (emits SQL to stdout)."""
    url = config.get_main_option("sqlalchemy.url")
    context.configure(
        url=url,
        target_metadata=target_metadata,
        literal_binds=True,
        dialect_opts={"paramstyle": "named"},
        include_object=include_object,
        include_schemas=False,
    )

    with context.begin_transaction():
        context.run_migrations()


# ── Online mode ───────────────────────────────────────────────────────────────
def run_migrations_online() -> None:
    """Run migrations against a live database connection."""
    connectable = engine_from_config(
        config.get_section(config.config_ini_section, {}),
        prefix="sqlalchemy.",
        poolclass=pool.NullPool,
    )

    with connectable.connect() as connection:
        context.configure(
            connection=connection,
            target_metadata=target_metadata,
            include_object=include_object,
            include_schemas=False,
        )

        with context.begin_transaction():
            context.run_migrations()


if context.is_offline_mode():
    run_migrations_offline()
else:
    run_migrations_online()

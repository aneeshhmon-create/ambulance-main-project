"""driver_auth_tables

Adds driver authentication tables and refactors the ambulances table:

  1. Creates `drivers`          – Google-authenticated driver accounts
  2. Adds `registration_number` and `vehicle_type` to `ambulances`
  3. Backfills `registration_number` for any existing ambulance rows
     using a placeholder Kerala-style number so the NOT NULL constraint
     can be applied safely
  4. Migrates any existing driver_name / driver_phone data into `drivers`
     rows (linked via the junction) so no data is lost
  5. Drops `driver_name` and `driver_phone` from `ambulances`
  6. Creates `ambulance_driver` junction table (M2M, composite PK)

Revision ID: c3d4e5f6a7b8
Revises: b2c3d4e5f6a7
Create Date: 2026-10-15
"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

# revision identifiers, used by Alembic.
revision: str = 'c3d4e5f6a7b8'
down_revision: Union[str, Sequence[str], None] = 'b2c3d4e5f6a7'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # ── 1. Create the `drivers` table ────────────────────────────────────────
    op.create_table(
        'drivers',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('name', sa.String(), nullable=False),
        sa.Column('email', sa.String(), nullable=False),
        sa.Column('phone', sa.String(), nullable=True),
        sa.Column('photo_url', sa.String(), nullable=True),
        sa.Column('is_active', sa.Boolean(), nullable=False,
                  server_default=sa.text('true')),
        sa.Column('created_at', sa.DateTime(timezone=True),
                  server_default=sa.text('now()'), nullable=False),
        sa.PrimaryKeyConstraint('id'),
    )
    op.create_index(op.f('ix_drivers_id'), 'drivers', ['id'], unique=False)
    op.create_index(op.f('ix_drivers_email'), 'drivers', ['email'], unique=True)

    # ── 2. Add new columns to `ambulances` (nullable first) ──────────────────
    op.add_column(
        'ambulances',
        sa.Column('registration_number', sa.String(), nullable=True),
    )
    op.add_column(
        'ambulances',
        sa.Column('vehicle_type', sa.Text(), nullable=True),
    )

    # ── 3. Backfill registration_number for existing ambulance rows ───────────
    # Uses a placeholder Kerala-style format: KL-99-TMP-XXXX where XXXX = id.
    # These will be replaced by real numbers when seed_demo_drivers.py is run.
    conn = op.get_bind()
    existing_ids = conn.execute(
        sa.text("SELECT id FROM ambulances")
    ).fetchall()
    for row in existing_ids:
        conn.execute(
            sa.text(
                "UPDATE ambulances "
                "SET registration_number = :reg "
                "WHERE id = :id"
            ),
            {"reg": f"KL-99-TMP-{row.id:04d}", "id": row.id},
        )

    # Now make registration_number NOT NULL and UNIQUE
    op.alter_column('ambulances', 'registration_number', nullable=False)
    op.create_index(
        op.f('ix_ambulances_registration_number'),
        'ambulances',
        ['registration_number'],
        unique=True,
    )

    # ── 4. Migrate existing driver_name/driver_phone → drivers rows ───────────
    # Create a `drivers` row for each existing ambulance that had driver data,
    # using a synthetic email to avoid NULL constraint. Real emails come from
    # seed_demo_drivers.py. Skip if driver_name column doesn't exist (fresh DB).
    insp = sa.inspect(conn)
    ambulance_cols = [c['name'] for c in insp.get_columns('ambulances')]
    if 'driver_name' in ambulance_cols and 'driver_phone' in ambulance_cols:
        old_drivers = conn.execute(
            sa.text(
                "SELECT id, driver_name, driver_phone FROM ambulances "
                "WHERE driver_name IS NOT NULL"
            )
        ).fetchall()

        # ── 4a. Create junction table early (needed for inserts below) ────────
        _create_junction_table()

        for row in old_drivers:
            # Derive a stable synthetic email from the phone number
            clean_phone = (row.driver_phone or "").strip().lstrip("+")
            synthetic_email = f"migrated_{clean_phone}@placeholder.internal"

            # Insert driver row (idempotent — skip if email already exists)
            result = conn.execute(
                sa.text(
                    "INSERT INTO drivers (name, email, phone, is_active) "
                    "VALUES (:name, :email, :phone, true) "
                    "ON CONFLICT (email) DO NOTHING "
                    "RETURNING id"
                ),
                {
                    "name": row.driver_name,
                    "email": synthetic_email,
                    "phone": row.driver_phone,
                },
            ).fetchone()

            if result:
                driver_id = result.id
            else:
                driver_id = conn.execute(
                    sa.text("SELECT id FROM drivers WHERE email = :e"),
                    {"e": synthetic_email},
                ).scalar()

            # Link driver ↔ ambulance
            conn.execute(
                sa.text(
                    "INSERT INTO ambulance_driver (driver_id, ambulance_id) "
                    "VALUES (:did, :aid) "
                    "ON CONFLICT DO NOTHING"
                ),
                {"did": driver_id, "aid": row.id},
            )

    else:
        # Fresh DB — just create the junction table
        _create_junction_table()

    # ── 5. Drop old driver columns from `ambulances` ─────────────────────────
    if 'driver_phone' in ambulance_cols:
        op.drop_index(
            op.f('ix_ambulances_driver_phone'), table_name='ambulances'
        )
        op.drop_column('ambulances', 'driver_phone')
    if 'driver_name' in ambulance_cols:
        op.drop_column('ambulances', 'driver_name')


def _create_junction_table() -> None:
    """Create the ambulance_driver junction table (extracted for reuse)."""
    op.create_table(
        'ambulance_driver',
        sa.Column('driver_id', sa.Integer(), nullable=False),
        sa.Column('ambulance_id', sa.Integer(), nullable=False),
        sa.Column(
            'created_at',
            sa.DateTime(timezone=True),
            server_default=sa.text('now()'),
            nullable=False,
        ),
        sa.ForeignKeyConstraint(
            ['ambulance_id'], ['ambulances.id'], ondelete='CASCADE'
        ),
        sa.ForeignKeyConstraint(
            ['driver_id'], ['drivers.id'], ondelete='CASCADE'
        ),
        sa.PrimaryKeyConstraint('driver_id', 'ambulance_id'),
    )


def downgrade() -> None:
    # ── Reverse order ─────────────────────────────────────────────────────────

    # 1. Drop junction
    op.drop_table('ambulance_driver')

    # 2. Restore driver columns to ambulances (nullable — we can't recover data)
    op.add_column(
        'ambulances',
        sa.Column('driver_name', sa.String(), nullable=True),
    )
    op.add_column(
        'ambulances',
        sa.Column('driver_phone', sa.String(), nullable=True),
    )
    op.create_index(
        op.f('ix_ambulances_driver_phone'),
        'ambulances',
        ['driver_phone'],
        unique=True,
    )

    # 3. Drop new ambulances columns
    op.drop_index(
        op.f('ix_ambulances_registration_number'), table_name='ambulances'
    )
    op.drop_column('ambulances', 'vehicle_type')
    op.drop_column('ambulances', 'registration_number')

    # 4. Drop drivers table
    op.drop_index(op.f('ix_drivers_email'), table_name='drivers')
    op.drop_index(op.f('ix_drivers_id'), table_name='drivers')
    op.drop_table('drivers')

"""inci_ambu_and_ambulance_online

Revision ID: e5f6a7b8c9d0
Revises: d4e5f6a7b8c9
Create Date: 2026-10-19

Adds:
  1. `inci_ambu` junction table for requesting incidents to candidate ambulances
  2. `is_online` (bool, default false) and `location_updated_at` (timestamptz, nullable)
     to `ambulances`
"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

# revision identifiers, used by Alembic.
revision: str = 'e5f6a7b8c9d0'
down_revision: Union[str, Sequence[str], None] = 'd4e5f6a7b8c9'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # ── 1. Create inci_ambu junction table ──────────────────────────────────
    op.create_table(
        'inci_ambu',
        sa.Column('incident_id', sa.Integer(), nullable=False),
        sa.Column('ambulance_id', sa.Integer(), nullable=False),
        sa.Column(
            'created_at',
            sa.DateTime(timezone=True),
            server_default=sa.text('now()'),
            nullable=False,
        ),
        sa.ForeignKeyConstraint(
            ['incident_id'],
            ['incidents.id'],
            ondelete='CASCADE',
        ),
        sa.ForeignKeyConstraint(
            ['ambulance_id'],
            ['ambulances.id'],
            ondelete='CASCADE',
        ),
        sa.PrimaryKeyConstraint('incident_id', 'ambulance_id'),
    )
    op.create_index(
        op.f('ix_inci_ambu_ambulance_id'),
        'inci_ambu',
        ['ambulance_id'],
        unique=False,
    )

    # ── 2. Add is_online and location_updated_at to ambulances ──────────────
    op.add_column(
        'ambulances',
        sa.Column(
            'is_online',
            sa.Boolean(),
            server_default=sa.text('false'),
            nullable=False,
        ),
    )
    op.add_column(
        'ambulances',
        sa.Column(
            'location_updated_at',
            sa.DateTime(timezone=True),
            nullable=True,
        ),
    )
    op.create_index(
        op.f('ix_ambulances_is_online'),
        'ambulances',
        ['is_online'],
        unique=False,
    )


def downgrade() -> None:
    op.drop_index(op.f('ix_ambulances_is_online'), table_name='ambulances')
    op.drop_column('ambulances', 'location_updated_at')
    op.drop_column('ambulances', 'is_online')
    op.drop_index(op.f('ix_inci_ambu_ambulance_id'), table_name='inci_ambu')
    op.drop_table('inci_ambu')

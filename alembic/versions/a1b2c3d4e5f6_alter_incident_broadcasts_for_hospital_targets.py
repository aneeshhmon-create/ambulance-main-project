"""alter_incident_broadcasts_for_hospital_targets

Replaces the old `ambulance_id` FK column on `incident_broadcasts` with
a generic `target_type` / `target_id` pair so that the table can track
broadcasts to hospitals (and other target types in the future).

Also adds default-value change: status default -> 'pending' (was 'sent').

Revision ID: a1b2c3d4e5f6
Revises: 220a3b2579b8
Create Date: 2026-09-26 22:40:00
"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

# revision identifiers, used by Alembic.
revision: str = 'a1b2c3d4e5f6'
down_revision: Union[str, Sequence[str], None] = '220a3b2579b8'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Drop old ambulance-centric columns, add generic target columns."""

    # 1. Drop the old ambulance-based FK index and column
    op.drop_index('ix_incident_broadcasts_ambulance_id', table_name='incident_broadcasts')
    op.drop_constraint(
        'incident_broadcasts_ambulance_id_fkey',
        'incident_broadcasts',
        type_='foreignkey',
    )
    op.drop_column('incident_broadcasts', 'ambulance_id')

    # 2. Add generic target columns
    op.add_column(
        'incident_broadcasts',
        sa.Column('target_type', sa.String(), nullable=False, server_default='hospital'),
    )
    op.add_column(
        'incident_broadcasts',
        sa.Column('target_id', sa.Integer(), nullable=False, server_default='0'),
    )

    # 3. Create indexes on the new columns
    op.create_index(
        'ix_incident_broadcasts_target_type',
        'incident_broadcasts',
        ['target_type'],
    )
    op.create_index(
        'ix_incident_broadcasts_target_id',
        'incident_broadcasts',
        ['target_id'],
    )

    # 4. Update the status default from 'sent' to 'pending'
    op.alter_column(
        'incident_broadcasts',
        'status',
        server_default='pending',
    )


def downgrade() -> None:
    """Reverse: restore ambulance_id column and remove target columns."""

    # Restore status default
    op.alter_column(
        'incident_broadcasts',
        'status',
        server_default='sent',
    )

    # Drop new indexes and columns
    op.drop_index('ix_incident_broadcasts_target_id', table_name='incident_broadcasts')
    op.drop_index('ix_incident_broadcasts_target_type', table_name='incident_broadcasts')
    op.drop_column('incident_broadcasts', 'target_id')
    op.drop_column('incident_broadcasts', 'target_type')

    # Restore ambulance_id
    op.add_column(
        'incident_broadcasts',
        sa.Column('ambulance_id', sa.Integer(), nullable=False, server_default='0'),
    )
    op.create_foreign_key(
        'incident_broadcasts_ambulance_id_fkey',
        'incident_broadcasts',
        'ambulances',
        ['ambulance_id'],
        ['id'],
        ondelete='CASCADE',
    )
    op.create_index(
        'ix_incident_broadcasts_ambulance_id',
        'incident_broadcasts',
        ['ambulance_id'],
    )

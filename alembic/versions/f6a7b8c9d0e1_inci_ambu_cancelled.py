"""inci_ambu_cancelled

Revision ID: f6a7b8c9d0e1
Revises: e5f6a7b8c9d0
Create Date: 2026-10-19

Adds `inci_ambu_cancelled`: which ambulances cancelled which incident, so a
cancelled incident is not offered back to the same ambulance.
"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

# revision identifiers, used by Alembic.
revision: str = 'f6a7b8c9d0e1'
down_revision: Union[str, Sequence[str], None] = 'e5f6a7b8c9d0'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        'inci_ambu_cancelled',
        sa.Column('incident_id', sa.Integer(), nullable=False),
        sa.Column('ambulance_id', sa.Integer(), nullable=False),
        sa.Column(
            'created_at',
            sa.DateTime(timezone=True),
            server_default=sa.text('now()'),
            nullable=False,
        ),
        sa.ForeignKeyConstraint(['incident_id'], ['incidents.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['ambulance_id'], ['ambulances.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('incident_id', 'ambulance_id'),
    )
    op.create_index(
        'ix_inci_ambu_cancelled_ambulance_id',
        'inci_ambu_cancelled',
        ['ambulance_id'],
    )


def downgrade() -> None:
    op.drop_index('ix_inci_ambu_cancelled_ambulance_id', table_name='inci_ambu_cancelled')
    op.drop_table('inci_ambu_cancelled')

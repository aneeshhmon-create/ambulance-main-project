"""google_auth_users_and_hospitals

Extends Google sign-in beyond drivers:

  1. Adds `email` (unique, nullable) and `photo_url` to `users`
  2. Creates `hospital_accounts` – dashboard logins, each tied to one hospital

Revision ID: d4e5f6a7b8c9
Revises: c3d4e5f6a7b8
Create Date: 2026-10-16
"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

# revision identifiers, used by Alembic.
revision: str = 'd4e5f6a7b8c9'
down_revision: Union[str, Sequence[str], None] = 'c3d4e5f6a7b8'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column('users', sa.Column('email', sa.String(), nullable=True))
    op.add_column('users', sa.Column('photo_url', sa.String(), nullable=True))
    op.create_index(op.f('ix_users_email'), 'users', ['email'], unique=True)

    op.create_table(
        'hospital_accounts',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('email', sa.String(), nullable=False),
        sa.Column('name', sa.String(), nullable=False),
        sa.Column('photo_url', sa.String(), nullable=True),
        sa.Column('hospital_id', sa.Integer(), nullable=False),
        sa.Column('created_at', sa.DateTime(timezone=True),
                  server_default=sa.text('now()'), nullable=False),
        sa.ForeignKeyConstraint(['hospital_id'], ['hospitals.id'],
                                ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id'),
    )
    op.create_index(op.f('ix_hospital_accounts_id'),
                    'hospital_accounts', ['id'], unique=False)
    op.create_index(op.f('ix_hospital_accounts_email'),
                    'hospital_accounts', ['email'], unique=True)
    op.create_index(op.f('ix_hospital_accounts_hospital_id'),
                    'hospital_accounts', ['hospital_id'], unique=False)


def downgrade() -> None:
    op.drop_index(op.f('ix_hospital_accounts_hospital_id'),
                  table_name='hospital_accounts')
    op.drop_index(op.f('ix_hospital_accounts_email'),
                  table_name='hospital_accounts')
    op.drop_index(op.f('ix_hospital_accounts_id'),
                  table_name='hospital_accounts')
    op.drop_table('hospital_accounts')

    op.drop_index(op.f('ix_users_email'), table_name='users')
    op.drop_column('users', 'photo_url')
    op.drop_column('users', 'email')

"""Add is_pro to profiles

Revision ID: 002
Revises: 001
Create Date: 2026-06-07
"""

import sqlalchemy as sa
from alembic import op

revision = "002"
down_revision = "001"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "profiles",
        sa.Column("is_pro", sa.Boolean, nullable=False, server_default="false"),
    )


def downgrade() -> None:
    op.drop_column("profiles", "is_pro")

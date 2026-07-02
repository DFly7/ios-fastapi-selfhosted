"""Rename indexes to match SQLAlchemy ORM naming convention (ix_<table>_<col>).

Revision ID: 003
Revises: 002
Create Date: 2026-07-02

Migration 001 created indexes with project-local names (e.g. ``notes_user_id_idx``)
that differ from the names SQLAlchemy autogenerates when the model declares
``index=True`` (e.g. ``ix_notes_user_id``). The users.email column also had a
separate non-unique index plus a plain unique constraint; SQLAlchemy expects a
single unique index when ``unique=True, index=True`` are both set.

This migration reconciles the live schema with ``Base.metadata`` so that the
drift guard (``test_migration_drift.py``) can pass.
"""

from alembic import op

revision = "003"
down_revision = "002"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # --- users.email ---
    # Remove the hand-named non-unique index and the auto-named unique constraint
    # that PostgreSQL created from the inline ``unique=True`` in migration 001.
    # Replace them with a single unique index using SQLAlchemy's default name.
    op.drop_index("users_email_idx", table_name="users")
    op.drop_constraint("users_email_key", table_name="users", type_="unique")
    op.create_index("ix_users_email", "users", ["email"], unique=True)

    # --- notes.user_id ---
    op.drop_index("notes_user_id_idx", table_name="notes")
    op.create_index("ix_notes_user_id", "notes", ["user_id"])

    # --- refresh_tokens.user_id ---
    op.drop_index("refresh_tokens_user_id_idx", table_name="refresh_tokens")
    op.create_index("ix_refresh_tokens_user_id", "refresh_tokens", ["user_id"])


def downgrade() -> None:
    # Restore the original index names from migration 001.
    op.drop_index("ix_users_email", table_name="users")
    op.create_index("users_email_idx", "users", ["email"])
    # Recreate the unique constraint; PostgreSQL will auto-name it users_email_key.
    op.create_unique_constraint("users_email_key", "users", ["email"])

    op.drop_index("ix_notes_user_id", table_name="notes")
    op.create_index("notes_user_id_idx", "notes", ["user_id"])

    op.drop_index("ix_refresh_tokens_user_id", table_name="refresh_tokens")
    op.create_index("refresh_tokens_user_id_idx", "refresh_tokens", ["user_id"])

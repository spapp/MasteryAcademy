"""Initial schema: users, sessions, courses, progress_records, sync_counters.

Revision ID: 0001
Revises:
"""
import sqlalchemy as sa
from alembic import op

revision = "0001"
down_revision = None


def upgrade() -> None:
    op.create_table(
        "users",
        sa.Column("id", sa.Uuid(), primary_key=True),
        sa.Column("email", sa.String(320), nullable=False, unique=True),
        sa.Column("display_name", sa.String(80), nullable=False),
        sa.Column("password_hash", sa.String(255), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("deleted_at", sa.DateTime(timezone=True), nullable=True),
    )
    op.create_table(
        "sessions",
        sa.Column("id", sa.Uuid(), primary_key=True),
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("device_name", sa.String(120), nullable=False),
        sa.Column("refresh_hash", sa.String(64), nullable=False, unique=True),
        sa.Column("prev_refresh_hash", sa.String(64), nullable=True),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("revoked_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
    )
    op.create_index("ix_sessions_user_id", "sessions", ["user_id"])
    op.create_index("ix_sessions_prev_refresh_hash", "sessions", ["prev_refresh_hash"])
    op.create_table(
        "courses",
        sa.Column("id", sa.String(64), primary_key=True),
        sa.Column("version", sa.String(32), nullable=False),
        sa.Column("summary", sa.JSON(), nullable=False),
        sa.Column("body", sa.Text(), nullable=True),
        sa.Column("position", sa.Integer(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
    )
    op.create_table(
        "progress_records",
        sa.Column("user_id", sa.Uuid(), primary_key=True),
        sa.Column("course_id", sa.String(64), primary_key=True),
        sa.Column("kind", sa.String(16), primary_key=True),
        sa.Column("item_id", sa.String(160), primary_key=True),
        sa.Column("done", sa.Boolean(), nullable=False),
        sa.Column("score", sa.Integer(), nullable=True),
        sa.Column("total", sa.Integer(), nullable=True),
        sa.Column("client_updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("seq", sa.BigInteger(), nullable=False),
    )
    op.create_index("ix_progress_user_seq", "progress_records", ["user_id", "seq"])
    op.create_table(
        "sync_counters",
        sa.Column("user_id", sa.Uuid(), primary_key=True),
        sa.Column("value", sa.BigInteger(), nullable=False),
    )


def downgrade() -> None:
    for table in ("sync_counters", "progress_records", "courses", "sessions", "users"):
        op.drop_table(table)

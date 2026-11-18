"""Phase 2: ai_usage, one row per model call.

Revision ID: 0002
Revises: 0001
"""
import sqlalchemy as sa
from alembic import op

revision = "0002"
down_revision = "0001"


def upgrade() -> None:
    op.create_table(
        "ai_usage",
        sa.Column("id", sa.Uuid(), primary_key=True),
        sa.Column("day", sa.String(10), nullable=False),
        sa.Column("mode", sa.String(16), nullable=False),
        sa.Column("model", sa.String(64), nullable=False),
        sa.Column("input_tokens", sa.Integer(), nullable=False),
        sa.Column("output_tokens", sa.Integer(), nullable=False),
        sa.Column("cost_microusd", sa.BigInteger(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
    )
    op.create_index("ix_ai_usage_day", "ai_usage", ["day"])


def downgrade() -> None:
    op.drop_table("ai_usage")

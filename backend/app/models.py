"""Tables. Must match spec/api.json `tables` and alembic/versions. Ids are UUIDs, times are UTC."""
import uuid
from datetime import datetime, timezone

from sqlalchemy import JSON, BigInteger, Boolean, DateTime, Index, Integer, String, Text, Uuid
from sqlalchemy.orm import Mapped, mapped_column

from .db import Base


def now() -> datetime:
    return datetime.now(timezone.utc)


class User(Base):
    __tablename__ = "users"
    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    email: Mapped[str] = mapped_column(String(320), unique=True)
    display_name: Mapped[str] = mapped_column(String(80))
    password_hash: Mapped[str] = mapped_column(String(255))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=now)
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)


class Session(Base):
    __tablename__ = "sessions"
    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(Uuid, index=True)
    device_name: Mapped[str] = mapped_column(String(120), default="")
    refresh_hash: Mapped[str] = mapped_column(String(64), unique=True)
    prev_refresh_hash: Mapped[str | None] = mapped_column(String(64), nullable=True, index=True)
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    revoked_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=now)


class Course(Base):
    __tablename__ = "courses"
    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    version: Mapped[str] = mapped_column(String(32), default="")
    summary: Mapped[dict] = mapped_column(JSON)
    body: Mapped[str | None] = mapped_column(Text, nullable=True)
    position: Mapped[int] = mapped_column(Integer, default=0)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=now)


class ProgressRecord(Base):
    __tablename__ = "progress_records"
    user_id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True)
    course_id: Mapped[str] = mapped_column(String(64), primary_key=True)
    kind: Mapped[str] = mapped_column(String(16), primary_key=True)
    item_id: Mapped[str] = mapped_column(String(160), primary_key=True)
    done: Mapped[bool] = mapped_column(Boolean, default=False)
    score: Mapped[int | None] = mapped_column(Integer, nullable=True)
    total: Mapped[int | None] = mapped_column(Integer, nullable=True)
    client_updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    seq: Mapped[int] = mapped_column(BigInteger)
    __table_args__ = (Index("ix_progress_user_seq", "user_id", "seq"),)


class AiUsage(Base):
    """One row per model call, for the daily request limit and the monthly cost cap."""
    __tablename__ = "ai_usage"
    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    day: Mapped[str] = mapped_column(String(10), index=True)
    mode: Mapped[str] = mapped_column(String(16))
    model: Mapped[str] = mapped_column(String(64))
    input_tokens: Mapped[int] = mapped_column(Integer, default=0)
    output_tokens: Mapped[int] = mapped_column(Integer, default=0)
    cost_microusd: Mapped[int] = mapped_column(BigInteger, default=0)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=now)


class SyncCounter(Base):
    __tablename__ = "sync_counters"
    user_id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True)
    value: Mapped[int] = mapped_column(BigInteger, default=0)

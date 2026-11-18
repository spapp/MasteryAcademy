"""Request and response shapes. Field names are the wire names in spec/api.json (camelCase)."""
import uuid
from datetime import datetime
from typing import Literal

from pydantic import BaseModel, ConfigDict, EmailStr, Field


class Wire(BaseModel):
    model_config = ConfigDict(extra="forbid")


class RegisterBody(Wire):
    email: EmailStr
    password: str = Field(min_length=8, max_length=128)
    displayName: str = Field(min_length=1, max_length=80)


class SessionBody(Wire):
    email: EmailStr
    password: str = Field(min_length=1, max_length=128)
    deviceName: str | None = Field(default=None, max_length=120)


class RefreshBody(Wire):
    refreshToken: str = Field(min_length=20, max_length=200)


class ProgressRecordIn(Wire):
    courseId: str = Field(min_length=1, max_length=64)
    kind: Literal["lesson", "quiz", "card", "bookmark"]
    itemId: str = Field(min_length=1, max_length=160)
    done: bool
    score: int | None = Field(default=None, ge=0, le=10000)
    total: int | None = Field(default=None, ge=0, le=10000)
    updatedAt: datetime


class ProgressPush(Wire):
    records: list[ProgressRecordIn] = Field(max_length=500)


class AskBody(Wire):
    courseId: str = Field(min_length=1, max_length=64)
    lessonId: str = Field(min_length=1, max_length=160)
    mode: Literal["tutor", "explain"]
    question: str | None = Field(default=None, max_length=2000)
    blockIndex: int | None = Field(default=None, ge=0, le=5000)
    depth: str | None = Field(default=None, max_length=16)


class QuizBody(Wire):
    courseId: str = Field(min_length=1, max_length=64)
    lessonId: str = Field(min_length=1, max_length=160)
    count: int | None = Field(default=None, ge=1, le=5)


class MarkBody(Wire):
    courseId: str = Field(min_length=1, max_length=64)
    kind: Literal["quiz", "task", "interview"]
    lessonId: str | None = Field(default=None, max_length=160)
    itemId: str | None = Field(default=None, max_length=200)
    question: str | None = Field(default=None, max_length=2000)
    answer: str = Field(min_length=1, max_length=8000)


def user_out(u) -> dict:
    return {"id": str(u.id), "email": u.email, "displayName": u.display_name, "createdAt": iso(u.created_at)}


def iso(dt: datetime) -> str:
    from datetime import timezone
    if dt.tzinfo is None:  # SQLite returns naive datetimes; they are stored as UTC
        dt = dt.replace(tzinfo=timezone.utc)
    return dt.astimezone(timezone.utc).isoformat().replace("+00:00", "Z")

import json
import os

import pytest
from fastapi.testclient import TestClient

os.environ.setdefault("JWT_SECRET", "test-secret-test-secret-test-secret-1234")
os.environ["APP_KEY"] = "test-app-key"
os.environ["ANTHROPIC_API_KEY"] = "test-not-a-real-key"
os.environ["AI_DAILY_LIMIT"] = "5"
os.environ["AI_MONTHLY_CAP_USD"] = "1"
APP_KEY = {"X-App-Key": "test-app-key"}


def _database_url(tmp_path_factory) -> str:
    """TEST_DATABASE_URL (disposable Postgres) when set, otherwise a throwaway SQLite file."""
    return os.environ.get("TEST_DATABASE_URL") or f"sqlite:///{tmp_path_factory.mktemp('db') / 'test.db'}"


@pytest.fixture(scope="session")
def content_dir(tmp_path_factory):
    d = tmp_path_factory.mktemp("content")
    summary = lambda cid, status, version: {"id": cid, "title": cid.title(), "subtitle": "", "icon": "book", "tint": "#000000", "group": "Test", "status": status,
                                            "artifactURL": None, "note": None, "version": version, "lessonCount": 1 if version else 0, "questionCount": 0, "quizCount": 0, "minutes": 5, "web": None}
    (d / "catalog.json").write_text(json.dumps({"schemaVersion": 1, "courses": [summary("alpha", "available", "v1"), summary("beta", "planned", "")]}))
    (d / "course-alpha.json").write_text(json.dumps({"schemaVersion": 1, "id": "alpha", "title": "Alpha", "subtitle": "", "version": "v1", "modules": [
        {"id": "m1", "title": "M1", "summary": "", "tag": "", "lessons": [{"id": "l1", "title": "L1 — unicode ✓", "minutes": 5, "level": 0, "blocks": [
            {"type": "heading", "text": "Few-shot prompts"}, {"type": "text", "text": "Three to five varied examples show a pattern."},
            {"type": "code", "code": "label = classify(ticket)", "language": "python"},
            {"type": "task", "id": "l1-task", "prompt": "Rewrite the weak prompt.", "material": "Classify this.", "rubric": ["States the labels", "Has three examples"], "answer": "Labels: A, B. Examples: ..."}], "quiz": []}]}],
        "questions": [{"id": "q1", "topic": "T", "level": "Senior", "q": "Why few-shot?", "a": "Examples show the pattern.", "points": [{"title": "Must mention", "items": ["pattern", "variety"]}]}], "resources": []}, ensure_ascii=False))
    return str(d)


@pytest.fixture()
def client(tmp_path_factory, content_dir):
    from sqlalchemy.orm import Session

    os.environ["DATABASE_URL"] = _database_url(tmp_path_factory)
    from app import db, deps, models  # noqa: F401
    from app.config import get_settings
    from app.seed import seed

    get_settings.cache_clear()
    db.reset_engine()
    deps.reset_rate_limits()
    engine = db.get_engine()
    db.Base.metadata.drop_all(engine)
    db.Base.metadata.create_all(engine)
    with Session(engine) as s:
        seed(s, content_dir)
    from app.main import create_app

    with TestClient(create_app()) as c:
        yield c
    db.reset_engine()


def register(client, email="a@example.com", password="correct horse", name="A"):
    r = client.post("/v1/auth/users", json={"email": email, "password": password, "displayName": name})
    assert r.status_code == 201, r.text
    return r.json()["data"]


def auth(tokens) -> dict:
    return {"Authorization": f"Bearer {tokens['accessToken']}"}

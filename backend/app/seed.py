"""Loads content/build into the courses table. Idempotent. Usage: python -m app.seed [content_dir]"""
import json
import os
import sys

from sqlalchemy.orm import Session as Db

from . import models
from .config import get_settings
from .db import get_engine


def seed(db: Db, content_dir: str) -> dict:
    catalog = json.load(open(os.path.join(content_dir, "catalog.json")))
    changed = unchanged = 0
    for position, summary in enumerate(catalog["courses"]):
        path = os.path.join(content_dir, f"course-{summary['id']}.json")
        body = open(path, encoding="utf-8").read() if summary["status"] == "available" and os.path.exists(path) else None
        row = db.get(models.Course, summary["id"])
        if row is None:
            row = models.Course(id=summary["id"], summary=summary)
            db.add(row)
        if row.version == summary["version"] and row.summary == summary and row.position == position and (row.body is None) == (body is None):
            unchanged += 1
            continue
        row.version, row.summary, row.body, row.position, row.updated_at = summary["version"], summary, body, position, models.now()
        changed += 1
    db.commit()
    return {"changed": changed, "unchanged": unchanged}


if __name__ == "__main__":
    with Db(get_engine()) as session:
        print(seed(session, sys.argv[1] if len(sys.argv) > 1 else get_settings().content_dir))

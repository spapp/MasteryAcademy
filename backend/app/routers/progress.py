from datetime import timezone

from fastapi import APIRouter, Depends, Query
from sqlalchemy import select
from sqlalchemy.orm import Session as Db

from .. import models
from ..db import get_db
from ..deps import Principal, current_user, rate_limit
from ..schemas import ProgressPush, iso

router = APIRouter()


def _utc(dt):
    return dt.replace(tzinfo=timezone.utc) if dt.tzinfo is None else dt.astimezone(timezone.utc)


def _out(r: models.ProgressRecord) -> dict:
    return {"courseId": r.course_id, "kind": r.kind, "itemId": r.item_id, "done": r.done, "score": r.score, "total": r.total, "updatedAt": iso(r.client_updated_at)}


@router.get("/progress", dependencies=[Depends(rate_limit("standard"))])
def listProgress(since: int = Query(0, ge=0), limit: int = Query(500, ge=1, le=1000), p: Principal = Depends(current_user), db: Db = Depends(get_db)):
    rows = db.scalars(select(models.ProgressRecord).where(models.ProgressRecord.user_id == p.user.id, models.ProgressRecord.seq > since)
                      .order_by(models.ProgressRecord.seq).limit(limit + 1)).all()
    page, more = rows[:limit], len(rows) > limit
    return {"data": [_out(r) for r in page], "page": {"nextCursor": page[-1].seq if more else None, "cursor": page[-1].seq if page else since}}


@router.put("/progress", dependencies=[Depends(rate_limit("standard"))])
def pushProgress(body: ProgressPush, p: Principal = Depends(current_user), db: Db = Depends(get_db)):
    uid = p.user.id
    # Row lock on the per-user counter serialises concurrent pushes from two devices (no-op on SQLite).
    counter = db.scalar(select(models.SyncCounter).where(models.SyncCounter.user_id == uid).with_for_update())
    if counter is None:
        counter = models.SyncCounter(user_id=uid, value=0)
        db.add(counter)
    applied = stale = 0
    for rec in body.records:
        incoming = _utc(rec.updatedAt)
        row = db.get(models.ProgressRecord, (uid, rec.courseId, rec.kind, rec.itemId))
        if row is not None and _utc(row.client_updated_at) >= incoming:
            stale += 1
            continue
        counter.value += 1
        if row is None:
            row = models.ProgressRecord(user_id=uid, course_id=rec.courseId, kind=rec.kind, item_id=rec.itemId)
            db.add(row)
        row.done, row.score, row.total, row.client_updated_at, row.seq = rec.done, rec.score, rec.total, incoming, counter.value
        applied += 1
    return {"data": {"applied": applied, "stale": stale, "cursor": counter.value}}

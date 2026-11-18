from fastapi import APIRouter, Depends, Request, Response
from sqlalchemy import select
from sqlalchemy.orm import Session as Db

from .. import models
from ..db import get_db
from ..deps import rate_limit
from ..errors import ApiError

router = APIRouter()


@router.get("/courses", dependencies=[Depends(rate_limit("standard"))])
def listCourses(db: Db = Depends(get_db)):
    rows = db.scalars(select(models.Course).order_by(models.Course.position)).all()
    return {"data": {"schemaVersion": 1, "courses": [r.summary for r in rows]}}


@router.get("/courses/{courseId}", dependencies=[Depends(rate_limit("standard"))])
def getCourse(courseId: str, request: Request, db: Db = Depends(get_db)):
    course = db.get(models.Course, courseId)
    if course is None or course.body is None:
        raise ApiError(404, "NOT_FOUND", "This course has no content yet.")
    etag = f'"{course.version}"'
    if request.headers.get("if-none-match") == etag:
        return Response(status_code=304, headers={"ETag": etag})
    # The body is stored as JSON text and passed through untouched, so the version hash stays valid.
    return Response(content='{"data":' + course.body + "}", media_type="application/json", headers={"ETag": etag, "Cache-Control": "public, max-age=300"})

from fastapi import APIRouter, Depends
from sqlalchemy import func, select
from sqlalchemy.orm import Session as Db

from .. import models
from ..db import get_db

router = APIRouter()


@router.get("/health")
def getHealth(db: Db = Depends(get_db)):
    count = db.scalar(select(func.count()).select_from(models.Course).where(models.Course.body.is_not(None)))
    return {"data": {"status": "ok", "database": "ok", "courses": count}}

"""On Postgres only: the Alembic migration must produce exactly the tables the models declare."""
import os
import subprocess
import sys
from pathlib import Path

import pytest

URL = os.environ.get("TEST_DATABASE_URL", "")


@pytest.mark.skipif(not URL.startswith("postgresql"), reason="needs TEST_DATABASE_URL pointing at a disposable Postgres")
def test_migration_matches_models():
    from alembic.autogenerate import compare_metadata
    from alembic.migration import MigrationContext
    from sqlalchemy import create_engine, text

    from app import models  # noqa: F401
    from app.db import Base

    engine = create_engine(URL)
    with engine.begin() as c:
        c.execute(text("DROP SCHEMA public CASCADE"))
        c.execute(text("CREATE SCHEMA public"))
    env = {**os.environ, "DATABASE_URL": URL}
    backend = Path(__file__).resolve().parents[1]
    result = subprocess.run([sys.executable, "-m", "alembic", "upgrade", "head"], cwd=backend, env=env, capture_output=True, text=True)
    assert result.returncode == 0, result.stderr
    with engine.connect() as c:
        diff = compare_metadata(MigrationContext.configure(c, opts={"compare_type": True}), Base.metadata)
    engine.dispose()
    assert diff == []

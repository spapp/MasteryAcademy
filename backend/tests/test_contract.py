"""The running app and spec/api.json must describe the same routes."""
import subprocess
import sys
from pathlib import Path

from app.generated.operations import BASE_PATH, OPERATIONS
from app.main import create_app

ROOT = Path(__file__).resolve().parents[2]


def test_routes_match_the_spec():
    app = create_app()
    actual = {(method.upper(), path): op["operationId"] for path, item in app.openapi()["paths"].items() for method, op in item.items()}
    expected = {(op["method"], BASE_PATH + op["path"]): op_id for op_id, op in OPERATIONS.items()}
    assert actual == expected


def test_generated_files_are_current():
    result = subprocess.run([sys.executable, str(ROOT / "tools/specgen/gen.py"), "--check"], capture_output=True, text=True)
    assert result.returncode == 0, result.stdout + result.stderr


def test_protected_operations_reject_anonymous_calls(client):
    for op_id, op in OPERATIONS.items():
        if op["auth"] == "public":
            continue
        r = client.request(op["method"], BASE_PATH + op["path"], json={})
        assert r.status_code == 401, op_id

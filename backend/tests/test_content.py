def test_catalog_lists_available_and_planned(client):
    data = client.get("/v1/courses").json()["data"]
    assert [c["id"] for c in data["courses"]] == ["alpha", "beta"]
    assert data["courses"][1]["status"] == "planned"


def test_course_body_and_etag(client):
    r = client.get("/v1/courses/alpha")
    assert r.status_code == 200 and r.headers["etag"] == '"v1"'
    course = r.json()["data"]
    assert course["modules"][0]["lessons"][0]["title"] == "L1 — unicode ✓"
    assert client.get("/v1/courses/alpha", headers={"If-None-Match": '"v1"'}).status_code == 304
    assert client.get("/v1/courses/alpha", headers={"If-None-Match": '"old"'}).status_code == 200


def test_planned_or_unknown_course_is_404(client):
    for cid in ("beta", "nope"):
        r = client.get(f"/v1/courses/{cid}")
        assert r.status_code == 404 and r.json()["error"]["code"] == "NOT_FOUND"


def test_seed_is_idempotent(client, content_dir):
    from sqlalchemy.orm import Session
    from app.db import get_engine
    from app.seed import seed
    with Session(get_engine()) as s:
        assert seed(s, content_dir) == {"changed": 0, "unchanged": 2}


def test_health_and_request_id(client):
    r = client.get("/v1/health", headers={"X-Request-Id": "abc123"})
    assert r.json()["data"] == {"status": "ok", "database": "ok", "courses": 1} and r.headers["x-request-id"] == "abc123"


def test_unknown_route_uses_envelope(client):
    r = client.get("/v1/nope")
    assert r.status_code == 404 and r.json()["error"]["code"] == "NOT_FOUND"

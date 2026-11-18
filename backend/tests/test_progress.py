from .conftest import auth, register


def rec(item, done=True, at="2026-11-17T10:00:00Z", kind="lesson", **kw):
    return {"courseId": "alpha", "kind": kind, "itemId": item, "done": done, "updatedAt": at, **kw}


def test_push_then_pull(client):
    h = auth(register(client)["tokens"])
    r = client.put("/v1/progress", headers=h, json={"records": [rec("l1"), rec("quiz-l1", kind="quiz", score=3, total=4)]})
    assert r.json()["data"] == {"applied": 2, "stale": 0, "cursor": 2}
    page = client.get("/v1/progress", headers=h).json()
    assert [(x["itemId"], x["kind"], x["score"]) for x in page["data"]] == [("l1", "lesson", None), ("quiz-l1", "quiz", 3)]
    assert page["data"][0]["updatedAt"] == "2026-11-17T10:00:00Z"
    assert page["page"] == {"nextCursor": None, "cursor": 2}


def test_newest_update_wins(client):
    h = auth(register(client)["tokens"])
    client.put("/v1/progress", headers=h, json={"records": [rec("l1", done=True, at="2026-11-17T10:00:00Z")]})
    older = client.put("/v1/progress", headers=h, json={"records": [rec("l1", done=False, at="2026-11-17T09:00:00Z")]})
    assert older.json()["data"] == {"applied": 0, "stale": 1, "cursor": 1}
    same = client.put("/v1/progress", headers=h, json={"records": [rec("l1", done=False, at="2026-11-17T10:00:00Z")]})
    assert same.json()["data"]["stale"] == 1
    newer = client.put("/v1/progress", headers=h, json={"records": [rec("l1", done=False, at="2026-11-17T15:30:00+05:30")]})  # 10:00:00Z, still not newer
    assert newer.json()["data"]["stale"] == 1
    newer = client.put("/v1/progress", headers=h, json={"records": [rec("l1", done=False, at="2026-11-17T11:00:00Z")]})
    assert newer.json()["data"] == {"applied": 1, "stale": 0, "cursor": 2}
    assert client.get("/v1/progress", headers=h).json()["data"][0]["done"] is False


def test_cursor_returns_only_changes_and_pages(client):
    h = auth(register(client)["tokens"])
    client.put("/v1/progress", headers=h, json={"records": [rec(f"l{i}") for i in range(5)]})
    first = client.get("/v1/progress?limit=2", headers=h).json()
    assert len(first["data"]) == 2 and first["page"]["nextCursor"] == 2
    rest = client.get(f"/v1/progress?since={first['page']['nextCursor']}", headers=h).json()
    assert [x["itemId"] for x in rest["data"]] == ["l2", "l3", "l4"] and rest["page"]["nextCursor"] is None
    client.put("/v1/progress", headers=h, json={"records": [rec("l0", done=False, at="2026-11-18T00:00:00Z")]})
    delta = client.get("/v1/progress?since=5", headers=h).json()
    assert [(x["itemId"], x["done"]) for x in delta["data"]] == [("l0", False)] and delta["page"]["cursor"] == 6
    assert client.get("/v1/progress?since=6", headers=h).json() == {"data": [], "page": {"nextCursor": None, "cursor": 6}}


def test_users_are_isolated(client):
    a = auth(register(client, "a@example.com")["tokens"])
    b = auth(register(client, "b@example.com")["tokens"])
    client.put("/v1/progress", headers=a, json={"records": [rec("l1")]})
    assert client.get("/v1/progress", headers=b).json()["data"] == []
    assert client.put("/v1/progress", headers=b, json={"records": [rec("l1", done=False)]}).json()["data"]["cursor"] == 1


def test_validation(client):
    h = auth(register(client)["tokens"])
    assert client.put("/v1/progress", json={"records": []}).status_code == 401
    bad = client.put("/v1/progress", headers=h, json={"records": [rec("l1", kind="note")]})
    assert bad.status_code == 422 and bad.json()["error"]["code"] == "VALIDATION_FAILED"
    assert client.put("/v1/progress", headers=h, json={"records": [rec("x")] * 501}).status_code == 422
    assert client.get("/v1/progress?since=-1", headers=h).status_code == 422

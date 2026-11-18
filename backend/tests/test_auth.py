from .conftest import auth, register


def test_register_sign_in_me(client):
    data = register(client, email="Dibya@Example.com")
    assert data["user"]["email"] == "dibya@example.com"
    assert set(data["tokens"]) == {"accessToken", "refreshToken", "expiresIn"}
    me = client.get("/v1/me", headers=auth(data["tokens"]))
    assert me.status_code == 200 and me.json()["data"]["id"] == data["user"]["id"]
    again = client.post("/v1/auth/sessions", json={"email": "dibya@example.com", "password": "correct horse", "deviceName": "iPhone"})
    assert again.status_code == 201


def test_duplicate_email_conflicts(client):
    register(client)
    r = client.post("/v1/auth/users", json={"email": "A@example.com", "password": "another pass", "displayName": "B"})
    assert r.status_code == 409 and r.json()["error"]["code"] == "CONFLICT"


def test_wrong_password_and_unknown_email_look_the_same(client):
    register(client)
    a = client.post("/v1/auth/sessions", json={"email": "a@example.com", "password": "nope"})
    b = client.post("/v1/auth/sessions", json={"email": "nobody@example.com", "password": "nope"})
    assert a.status_code == b.status_code == 401
    assert a.json()["error"]["code"] == b.json()["error"]["code"] == "INVALID_CREDENTIALS"
    assert a.json()["error"]["message"] == b.json()["error"]["message"]


def test_validation_envelope(client):
    r = client.post("/v1/auth/users", json={"email": "not-an-email", "password": "short", "displayName": "", "extra": 1})
    assert r.status_code == 422
    err = r.json()["error"]
    assert err["code"] == "VALIDATION_FAILED" and {"email", "password", "displayName", "extra"} <= set(err["fields"]) and err["requestId"]


def test_me_requires_token(client):
    assert client.get("/v1/me").status_code == 401
    assert client.get("/v1/me", headers={"Authorization": "Bearer junk"}).json()["error"]["code"] == "UNAUTHENTICATED"


def test_refresh_rotates_and_reuse_ends_session(client):
    t1 = register(client)["tokens"]
    r = client.post("/v1/auth/sessions/refresh", json={"refreshToken": t1["refreshToken"]})
    assert r.status_code == 200
    t2 = r.json()["data"]
    assert t2["refreshToken"] != t1["refreshToken"]
    assert client.get("/v1/me", headers=auth(t2)).status_code == 200
    replay = client.post("/v1/auth/sessions/refresh", json={"refreshToken": t1["refreshToken"]})
    assert replay.status_code == 401 and replay.json()["error"]["code"] == "TOKEN_REUSED"
    # the whole session is gone: neither the new refresh token nor the access token works
    assert client.post("/v1/auth/sessions/refresh", json={"refreshToken": t2["refreshToken"]}).status_code == 401
    assert client.get("/v1/me", headers=auth(t2)).status_code == 401


def test_sign_out_ends_only_this_session(client):
    first = register(client)["tokens"]
    second = client.post("/v1/auth/sessions", json={"email": "a@example.com", "password": "correct horse"}).json()["data"]["tokens"]
    assert client.delete("/v1/auth/sessions/current", headers=auth(first)).status_code == 204
    assert client.get("/v1/me", headers=auth(first)).status_code == 401
    assert client.get("/v1/me", headers=auth(second)).status_code == 200


def test_delete_account_removes_everything(client):
    t = register(client)["tokens"]
    client.put("/v1/progress", headers=auth(t), json={"records": [{"courseId": "alpha", "kind": "lesson", "itemId": "l1", "done": True, "updatedAt": "2026-11-17T10:00:00Z"}]})
    assert client.delete("/v1/me", headers=auth(t)).status_code == 204
    assert client.get("/v1/me", headers=auth(t)).status_code == 401
    assert client.post("/v1/auth/sessions", json={"email": "a@example.com", "password": "correct horse"}).status_code == 401
    fresh = register(client)["tokens"]  # same email can register again and starts empty
    assert client.get("/v1/progress", headers=auth(fresh)).json()["data"] == []


def test_auth_rate_limit(client):
    codes = [client.post("/v1/auth/sessions", json={"email": "x@example.com", "password": "nope"}).status_code for _ in range(12)]
    assert codes[:10] == [401] * 10 and codes[10:] == [429, 429]

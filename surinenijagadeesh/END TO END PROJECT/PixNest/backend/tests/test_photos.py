"""Tests the CI pipeline runs. S3 is mocked (moto); the DB is in-memory SQLite."""

import io

from .conftest import make_auth_headers


def test_health(client):
    r = client.get("/health")
    assert r.status_code == 200
    assert r.json()["status"] == "ok"


def test_version_endpoint(client):
    assert "version" in client.get("/version").json()


def test_register_login_flow(client):
    r = client.post("/api/auth/register", json={"username": "flow-user", "password": "password-123"})
    assert r.status_code == 201
    assert r.json()["username"] == "flow-user"
    # Duplicate username is rejected.
    dup = client.post("/api/auth/register", json={"username": "flow-user", "password": "password-123"})
    assert dup.status_code == 409
    # Wrong password is rejected.
    bad = client.post("/api/auth/login", data={"username": "flow-user", "password": "wrong-password"})
    assert bad.status_code == 401
    ok = client.post("/api/auth/login", data={"username": "flow-user", "password": "password-123"})
    assert ok.status_code == 200
    assert ok.json()["token_type"] == "bearer"


def test_every_photo_endpoint_requires_auth(client):
    """No anonymous access at all: reading is as protected as writing.

    Reading used to be open, which meant signing out still left the whole gallery, and every
    presigned image URL in it, readable by anyone who could reach the API.
    """
    files = {"file": ("cat.jpg", io.BytesIO(b"img"), "image/jpeg")}
    assert client.post("/api/photos", files=files).status_code == 401
    assert client.delete("/api/photos/some-id").status_code == 401
    assert client.get("/api/photos").status_code == 401
    assert client.get("/api/photos/some-id").status_code == 401


def test_a_junk_token_is_rejected(client):
    """A malformed or forged bearer token must fail closed, not fall through to open access."""
    bad = {"Authorization": "Bearer not-a-real-token"}
    assert client.get("/api/photos", headers=bad).status_code == 401
    assert client.get("/api/photos/some-id", headers=bad).status_code == 401


def test_upload_list_get_delete(client, auth_headers):
    # upload (as the signed-in user)
    files = {"file": ("cat.jpg", io.BytesIO(b"fake-image-bytes"), "image/jpeg")}
    r = client.post("/api/photos", files=files, headers=auth_headers)
    assert r.status_code == 201
    body = r.json()
    photo_id = body["id"]
    assert body["filename"] == "cat.jpg"
    assert body["size_bytes"] == len(b"fake-image-bytes")
    assert body["uploaded_by"] == "tester"  # ownership is stamped from the token
    assert body["url"]  # a presigned S3 URL was returned

    # it appears in the owner's own list
    listed = client.get("/api/photos", headers=auth_headers).json()
    assert any(p["id"] == photo_id for p in listed)

    # fetch it by id
    assert client.get(f"/api/photos/{photo_id}", headers=auth_headers).status_code == 200

    # delete it, then it is gone
    assert client.delete(f"/api/photos/{photo_id}", headers=auth_headers).status_code == 204
    assert client.get(f"/api/photos/{photo_id}", headers=auth_headers).status_code == 404


def test_cannot_delete_someone_elses_photo(client, auth_headers):
    files = {"file": ("mine.jpg", io.BytesIO(b"img"), "image/jpeg")}
    photo_id = client.post("/api/photos", files=files, headers=auth_headers).json()["id"]

    other = make_auth_headers(client, "intruder")
    assert client.delete(f"/api/photos/{photo_id}", headers=other).status_code == 403
    # the owner still can
    assert client.delete(f"/api/photos/{photo_id}", headers=auth_headers).status_code == 204


def test_each_user_sees_only_their_own_photos(client, auth_headers):
    """The core guarantee: one user's vault is invisible to another."""
    alice = make_auth_headers(client, "alice")
    bob = make_auth_headers(client, "bob")

    def upload(headers, name):
        files = {"file": (name, io.BytesIO(b"img"), "image/jpeg")}
        return client.post("/api/photos", files=files, headers=headers).json()["id"]

    alice_photo = upload(alice, "alice.jpg")
    bob_photo = upload(bob, "bob.jpg")

    alice_sees = {p["id"] for p in client.get("/api/photos", headers=alice).json()}
    bob_sees = {p["id"] for p in client.get("/api/photos", headers=bob).json()}

    assert alice_sees == {alice_photo}
    assert bob_sees == {bob_photo}

    # Knowing the id is not enough. The answer is 404, not 403, so the response does not
    # confirm that someone else's photo exists.
    assert client.get(f"/api/photos/{bob_photo}", headers=alice).status_code == 404
    assert client.get(f"/api/photos/{alice_photo}", headers=bob).status_code == 404

    client.delete(f"/api/photos/{alice_photo}", headers=alice)
    client.delete(f"/api/photos/{bob_photo}", headers=bob)


def test_get_unknown_returns_404(client, auth_headers):
    assert client.get("/api/photos/does-not-exist", headers=auth_headers).status_code == 404


def test_reject_non_image(client, auth_headers):
    files = {"file": ("notes.txt", io.BytesIO(b"hello"), "text/plain")}
    assert client.post("/api/photos", files=files, headers=auth_headers).status_code == 415


def test_reject_oversized_upload(client, auth_headers):
    big = io.BytesIO(b"x" * (10 * 1024 * 1024 + 1))
    files = {"file": ("big.jpg", big, "image/jpeg")}
    assert client.post("/api/photos", files=files, headers=auth_headers).status_code == 413


def test_filename_is_sanitized(client, auth_headers):
    files = {"file": ("../we ird/na<me>.jpg", io.BytesIO(b"img"), "image/png")}
    r = client.post("/api/photos", files=files, headers=auth_headers)
    assert r.status_code == 201
    name = r.json()["filename"]
    assert "/" not in name and "<" not in name and " " not in name
    client.delete(f"/api/photos/{r.json()['id']}", headers=auth_headers)


def test_pagination(client, auth_headers):
    ids = [
        client.post(
            "/api/photos",
            files={"file": (f"p{i}.jpg", io.BytesIO(b"img"), "image/jpeg")},
            headers=auth_headers,
        ).json()["id"]
        for i in range(3)
    ]
    assert len(client.get("/api/photos?limit=2", headers=auth_headers).json()) == 2
    assert len(client.get("/api/photos?limit=2&offset=2", headers=auth_headers).json()) >= 1
    assert client.get("/api/photos?limit=1000", headers=auth_headers).status_code == 422
    for pid in ids:
        client.delete(f"/api/photos/{pid}", headers=auth_headers)

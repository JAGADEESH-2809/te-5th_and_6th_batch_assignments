"""Test fixtures: in-memory SQLite + mocked S3 (moto), so tests need no real cloud/DB.

Environment is set BEFORE importing the app, so its settings pick up the test config.
"""

import os

os.environ.setdefault("DATABASE_URL", "sqlite+aiosqlite://")  # in-memory (StaticPool keeps it)
os.environ.setdefault("S3_BUCKET", "test-bucket")
os.environ.setdefault("AWS_REGION", "ap-south-1")
os.environ.setdefault("AWS_ACCESS_KEY_ID", "testing")
os.environ.setdefault("AWS_SECRET_ACCESS_KEY", "testing")
os.environ.setdefault("AWS_DEFAULT_REGION", "ap-south-1")

import boto3  # noqa: E402
import pytest  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402
from moto import mock_aws  # noqa: E402


@pytest.fixture(scope="module")
def client():
    with mock_aws():
        boto3.client("s3", region_name="ap-south-1").create_bucket(
            Bucket="test-bucket",
            CreateBucketConfiguration={"LocationConstraint": "ap-south-1"},
        )
        from app.main import app  # imported here so env is already set

        with TestClient(app) as c:  # context form runs the lifespan (creates tables)
            yield c


def make_auth_headers(client, username: str, password: str = "password-123") -> dict:
    """Register (idempotent) + log in, returning Authorization headers."""
    client.post("/api/auth/register", json={"username": username, "password": password})
    r = client.post("/api/auth/login", data={"username": username, "password": password})
    assert r.status_code == 200, r.text
    return {"Authorization": f"Bearer {r.json()['access_token']}"}


@pytest.fixture(scope="module")
def auth_headers(client):
    """A default signed-in test user."""
    return make_auth_headers(client, "tester")

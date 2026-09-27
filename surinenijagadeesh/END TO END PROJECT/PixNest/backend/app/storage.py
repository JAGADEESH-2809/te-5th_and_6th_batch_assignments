"""S3 access. In the cluster this uses Pod Identity (no keys); locally it points at MinIO.

boto3 is synchronous, so the network calls are pushed to a thread pool - they must never run
inline in an async handler or they stall the event loop (and with it /health and /ready).
"""

from functools import lru_cache

import boto3
from botocore.config import Config
from fastapi.concurrency import run_in_threadpool

from .config import settings


@lru_cache(maxsize=1)
def _client():
    # boto3 clients are thread-safe and expensive to create - build once and reuse.
    return boto3.client(
        "s3",
        region_name=settings.aws_region,
        endpoint_url=settings.s3_endpoint_url,  # None -> real AWS; set -> MinIO/LocalStack
        config=Config(
            signature_version="s3v4",
            connect_timeout=5,
            read_timeout=30,
            retries={"max_attempts": 3, "mode": "standard"},
        ),
    )


def _put_object(key: str, body: bytes, content_type: str) -> None:
    _client().put_object(Bucket=settings.s3_bucket, Key=key, Body=body, ContentType=content_type)


async def put_object(key: str, body: bytes, content_type: str) -> None:
    await run_in_threadpool(_put_object, key, body, content_type)


def _delete_object(key: str) -> None:
    _client().delete_object(Bucket=settings.s3_bucket, Key=key)


async def delete_object(key: str) -> None:
    await run_in_threadpool(_delete_object, key)


@lru_cache(maxsize=1)
def _presign_client():
    return boto3.client(
        "s3",
        region_name=settings.aws_region,
        endpoint_url=settings.s3_endpoint_url,
        config=Config(
            signature_version="s3v4",
            connect_timeout=5,
            read_timeout=30,
            retries={"max_attempts": 3, "mode": "standard"},
        ),
    )


def presigned_url(key: str) -> str:
    # Signing happens locally (no network call), so this is safe to run inline.
    return _presign_client().generate_presigned_url(
        "get_object",
        Params={"Bucket": settings.s3_bucket, "Key": key},
        ExpiresIn=settings.presign_expiry_seconds,
    )

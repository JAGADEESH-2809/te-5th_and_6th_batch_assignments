"""Photo endpoints: upload to S3 + metadata in Postgres, list, get, delete."""

import logging
import re
import uuid
from typing import Annotated

from fastapi import APIRouter, Depends, File, HTTPException, Query, Request, UploadFile
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from .. import storage
from ..auth import CurrentUser
from ..db import get_db
from ..models import Photo
from ..schemas import PhotoOut

logger = logging.getLogger("pixnest.photos")

router = APIRouter(prefix="/api/photos", tags=["photos"])

# Modern FastAPI dependency style: declare the dependency in the type, via Annotated.
DbSession = Annotated[AsyncSession, Depends(get_db)]
UploadedFile = Annotated[UploadFile, File(...)]

ALLOWED_CONTENT_TYPES = {"image/jpeg", "image/png", "image/gif", "image/webp"}
MAX_UPLOAD_BYTES = 10 * 1024 * 1024  # 10 MB
READ_CHUNK_BYTES = 1024 * 1024  # read uploads 1 MB at a time
MULTIPART_OVERHEAD = 64 * 1024  # slack for multipart boundaries in the Content-Length precheck

_UNSAFE_FILENAME_CHARS = re.compile(r"[^A-Za-z0-9._-]")


def _safe_filename(name: str | None) -> str:
    """Client filenames are untrusted: strip any path, collapse odd characters, cap the length."""
    name = (name or "").replace("\\", "/").rsplit("/", 1)[-1]
    name = _UNSAFE_FILENAME_CHARS.sub("_", name).strip("._")
    return name[:200] or "unnamed"


def _to_out(p: Photo) -> PhotoOut:
    out = PhotoOut.model_validate(p)
    out.url = storage.presigned_url(p.s3_key)
    return out


@router.post("", response_model=PhotoOut, status_code=201)
async def upload_photo(request: Request, file: UploadedFile, db: DbSession, user: CurrentUser):
    """Upload an image (requires login): store the file in S3, the metadata in the database."""
    content_type = file.content_type or "application/octet-stream"
    if content_type not in ALLOWED_CONTENT_TYPES:
        raise HTTPException(
            status_code=415,
            detail=f"unsupported content type '{content_type}'; allowed: {sorted(ALLOWED_CONTENT_TYPES)}",
        )

    # Fast reject before reading anything when the client declares an oversized body.
    declared = request.headers.get("content-length")
    if declared and declared.isdigit() and int(declared) > MAX_UPLOAD_BYTES + MULTIPART_OVERHEAD:
        raise HTTPException(status_code=413, detail="file too large (max 10 MB)")

    # Read in chunks and stop at the limit, so an oversized body never sits fully in memory.
    chunks: list[bytes] = []
    size = 0
    while chunk := await file.read(READ_CHUNK_BYTES):
        size += len(chunk)
        if size > MAX_UPLOAD_BYTES:
            raise HTTPException(status_code=413, detail="file too large (max 10 MB)")
        chunks.append(chunk)
    data = b"".join(chunks)
    if not data:
        raise HTTPException(status_code=400, detail="empty file")

    photo_id = str(uuid.uuid4())
    filename = _safe_filename(file.filename)
    key = f"{photo_id}/{filename}"

    await storage.put_object(key, data, content_type)  # file -> S3
    photo = Photo(
        id=photo_id,
        filename=filename,
        content_type=content_type,
        size_bytes=len(data),
        s3_key=key,
        uploaded_by=user,
    )
    db.add(photo)  # metadata -> DB
    try:
        await db.commit()
    except Exception:
        # Do not leave an orphaned object behind if the metadata write fails.
        await db.rollback()
        try:
            await storage.delete_object(key)
        except Exception:
            logger.exception("cleanup of orphaned S3 object failed key=%s", key)
        raise
    await db.refresh(photo)
    logger.info("photo uploaded id=%s size=%d type=%s", photo_id, len(data), content_type)
    return _to_out(photo)


@router.get("", response_model=list[PhotoOut])
async def list_photos(
    db: DbSession,
    user: CurrentUser,
    limit: Annotated[int, Query(ge=1, le=100)] = 50,
    offset: Annotated[int, Query(ge=0)] = 0,
):
    """List the signed-in user's own photos, newest first, paginated.

    A vault is private, so the listing is scoped to the caller. Whose rows come back is
    decided by the token alone. There is deliberately no owner query parameter, because any
    such parameter is client-supplied and could simply be changed to someone else's name.
    """
    stmt = (
        select(Photo)
        .where(Photo.uploaded_by == user)
        .order_by(Photo.uploaded_at.desc(), Photo.id)
        .limit(limit)
        .offset(offset)
    )
    rows = (await db.execute(stmt)).scalars().all()
    return [_to_out(p) for p in rows]


@router.get("/{photo_id}", response_model=PhotoOut)
async def get_photo(photo_id: str, db: DbSession, user: CurrentUser):
    photo = await db.get(Photo, photo_id)
    # Someone else's photo answers 404 rather than 403. A 403 would confirm the id exists,
    # which lets a caller map the whole table by guessing ids. Delete answers 403 instead,
    # because you can only reach it with an id you already own, so the clearer error is safe.
    if not photo or photo.uploaded_by != user:
        raise HTTPException(status_code=404, detail="photo not found")
    return _to_out(photo)


@router.delete("/{photo_id}", status_code=204)
async def delete_photo(photo_id: str, db: DbSession, user: CurrentUser):
    photo = await db.get(Photo, photo_id)
    if not photo:
        raise HTTPException(status_code=404, detail="photo not found")
    # Ownership: only the uploader may delete. (Legacy rows with no owner are deletable by
    # any signed-in user so old demo data can be cleaned up.)
    if photo.uploaded_by and photo.uploaded_by != user:
        raise HTTPException(status_code=403, detail="you can only delete your own photos")
    key = photo.s3_key
    # Remove the DB row first: a failure after this point can only orphan an unreachable S3
    # object (harmless, logged), never leave a row whose image is gone (a broken gallery card).
    await db.delete(photo)
    await db.commit()
    try:
        await storage.delete_object(key)
    except Exception:
        logger.exception("S3 delete failed, object orphaned key=%s", key)
    logger.info("photo deleted id=%s", photo_id)

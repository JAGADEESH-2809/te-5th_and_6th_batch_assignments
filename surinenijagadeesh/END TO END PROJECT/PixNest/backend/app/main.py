"""pixnest backend - FastAPI app. Swagger UI at /docs."""

import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException
from sqlalchemy import text

from .config import settings
from .db import Base, SessionLocal, engine
from .routers import auth, photos

# Structured-ish app logs to stdout (collected by the container runtime / CloudWatch).
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(name)s %(message)s",
)


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Create tables on startup. (In real projects use Alembic migrations instead.)
    async with engine.begin() as conn:
        # With multiple workers, concurrent create_all calls race on Postgres DDL
        # (duplicate pg_type). A transaction-scoped advisory lock serializes them:
        # the first worker creates the schema, the rest wait then see it already exists.
        if conn.dialect.name == "postgresql":
            await conn.execute(text("SELECT pg_advisory_xact_lock(0x5356)"))
        await conn.run_sync(Base.metadata.create_all)
    yield


app = FastAPI(
    title="pixnest",
    description="Photo gallery API - upload images to S3, list metadata from Postgres.",
    version=settings.app_version,
    lifespan=lifespan,
)
app.include_router(auth.router)
app.include_router(photos.router)


@app.get("/", tags=["meta"])
def root():
    return {"app": "pixnest", "version": settings.app_version, "environment": settings.environment}


@app.get("/health", tags=["meta"])
def health():
    # Liveness: the process is up.
    return {"status": "ok", "version": settings.app_version}


@app.get("/ready", tags=["meta"])
async def ready():
    # Readiness: the database is reachable (so we do not send traffic to a broken pod).
    try:
        async with SessionLocal() as session:
            await session.execute(text("SELECT 1"))
    except Exception as err:
        raise HTTPException(status_code=503, detail="database not ready") from err
    return {"status": "ready"}


@app.get("/version", tags=["meta"])
def version():
    return {"version": settings.app_version}


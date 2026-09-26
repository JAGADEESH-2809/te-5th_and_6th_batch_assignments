"""Async SQLAlchemy engine, session factory, and the FastAPI DB dependency."""

from collections.abc import AsyncGenerator

from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine
from sqlalchemy.orm import DeclarativeBase
from sqlalchemy.pool import StaticPool

from .config import settings


class Base(DeclarativeBase):
    pass


# SQLite (used in tests) needs a shared in-memory connection; Postgres uses the normal pool.
_kwargs: dict = {"echo": False}
if settings.database_url.startswith("sqlite"):
    _kwargs["connect_args"] = {"check_same_thread": False}
    _kwargs["poolclass"] = StaticPool
else:
    _kwargs["pool_pre_ping"] = True

engine = create_async_engine(settings.database_url, **_kwargs)
SessionLocal = async_sessionmaker(engine, expire_on_commit=False)


async def get_db() -> AsyncGenerator[AsyncSession, None]:
    async with SessionLocal() as session:
        yield session

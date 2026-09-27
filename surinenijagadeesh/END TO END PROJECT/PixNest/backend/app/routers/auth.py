"""Auth endpoints: register + login with self-issued JWTs (no external IdP)."""

import logging
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException
from fastapi.concurrency import run_in_threadpool
from fastapi.security import OAuth2PasswordRequestForm
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from ..auth import create_access_token, hash_password, verify_password
from ..db import get_db
from ..models import User
from ..schemas import RegisterIn, Token, UserOut

logger = logging.getLogger("pixnest.auth")

router = APIRouter(prefix="/api/auth", tags=["auth"])

DbSession = Annotated[AsyncSession, Depends(get_db)]
LoginForm = Annotated[OAuth2PasswordRequestForm, Depends()]

# Verified against when the username is unknown, so response timing does not
# reveal which usernames exist. Computed once at import.
_DUMMY_HASH = hash_password("invalid-placeholder")


@router.post("/register", response_model=UserOut, status_code=201)
async def register(body: RegisterIn, db: DbSession):
    # bcrypt is CPU-heavy: keep it off the event loop.
    password_hash = await run_in_threadpool(hash_password, body.password)
    user = User(username=body.username, password_hash=password_hash)
    db.add(user)
    try:
        await db.commit()
    except IntegrityError:
        await db.rollback()
        raise HTTPException(status_code=409, detail="username already taken") from None
    await db.refresh(user)
    logger.info("user registered username=%s", user.username)
    return user


@router.post("/login", response_model=Token)
async def login(form: LoginForm, db: DbSession):
    user = (await db.execute(select(User).where(User.username == form.username))).scalar_one_or_none()
    password_hash = user.password_hash if user else _DUMMY_HASH
    ok = await run_in_threadpool(verify_password, form.password, password_hash)
    if not user or not ok:
        raise HTTPException(
            status_code=401,
            detail="incorrect username or password",
            headers={"WWW-Authenticate": "Bearer"},
        )
    logger.info("user logged in username=%s", user.username)
    return Token(access_token=create_access_token(user.username))

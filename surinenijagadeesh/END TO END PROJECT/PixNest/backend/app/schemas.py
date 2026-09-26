"""Pydantic schemas (the API's request/response shapes)."""

from datetime import datetime

from pydantic import BaseModel, Field


class RegisterIn(BaseModel):
    username: str = Field(min_length=3, max_length=64, pattern=r"^[A-Za-z0-9_.-]+$")
    password: str = Field(min_length=8, max_length=72)  # bcrypt operates on the first 72 bytes


class UserOut(BaseModel):
    id: str
    username: str

    model_config = {"from_attributes": True}


class Token(BaseModel):
    access_token: str
    token_type: str = "bearer"


class PhotoOut(BaseModel):
    id: str
    filename: str
    content_type: str
    size_bytes: int
    uploaded_by: str | None = None
    uploaded_at: datetime
    url: str | None = None  # short-lived presigned S3 URL to display the image

    model_config = {"from_attributes": True}

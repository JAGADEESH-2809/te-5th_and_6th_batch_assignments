"""Application settings, loaded from environment variables (12-factor config)."""

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    # Async SQLAlchemy URL. Postgres in real use; SQLite in tests.
    database_url: str = "postgresql+asyncpg://pixnest:pixnest@localhost:5432/pixnest"

    # Object storage
    s3_bucket: str = "pixnest-photos"
    aws_region: str = "ap-south-1"
    s3_endpoint_url: str | None = None  # set for MinIO/LocalStack; None for real AWS
    presign_expiry_seconds: int = 3600

    # Auth: self-issued JWTs (HS256). The secret MUST be overridden outside local dev
    # (Kubernetes Secret / External Secrets), never committed for production.
    jwt_secret: str = "dev-only-change-me"
    jwt_expiry_minutes: int = 60 * 24

    # Reported by the app (CD sets APP_VERSION to the commit SHA)
    app_version: str = "dev"
    environment: str = "local"


settings = Settings()

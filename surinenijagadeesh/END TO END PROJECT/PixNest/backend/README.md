# pixnest backend (FastAPI)

Photo API - upload images to **S3**, store metadata in **Postgres**. Interactive docs (Swagger) at **`/docs`**.

## Endpoints

Every `/api/photos` route needs a bearer token. Photos are private to the account that
uploaded them, so the token decides both whether you get an answer and whose photos it
describes. Without one the answer is 401.

| Method | Path | Auth | Purpose |
|--------|------|------|---------|
| POST | `/api/auth/register` | none | Create an account |
| POST | `/api/auth/login` | none | Exchange username and password for a JWT |
| POST | `/api/photos` | required | Upload an image (file to S3, row to DB) |
| GET | `/api/photos` | required | List **your own** photos (each with a presigned URL) |
| GET | `/api/photos/{id}` | required | One of your photos: metadata + URL |
| DELETE | `/api/photos/{id}` | required | Delete your photo from S3 and DB |
| GET | `/health` `/ready` `/version` `/docs` | none | Liveness, readiness (DB check), version, Swagger |

Asking for a photo belonging to someone else answers **404, not 403**, so the response
does not confirm that the id exists.

## Run the tests (no cloud or DB needed)
Tests mock S3 with **moto** and use an in-memory **SQLite** DB. Deps are pinned in `uv.lock`.
```bash
uv sync                 # creates .venv from the locked versions (dev tools included)
uv run ruff check .     # lint (ruff = the modern all-in-one linter/formatter)
uv run ruff format --check .
uv run pytest -q        # 13 tests
```
No uv? Fall back to `pip install -e . pytest httpx "moto[s3]" ruff` then run the tools directly.

## Run locally with Docker Compose (backend + Postgres + MinIO)
From the **repo root** (needs Docker Desktop running):
```bash
docker compose up --build
# open http://localhost:8000/docs  and try POST /api/photos
```
MinIO is a local, S3-compatible store; a bucket `pixnest-photos` is created automatically. The MinIO console is at http://localhost:9001 (minioadmin / minioadmin).

> Local note: presigned image URLs point at the S3 endpoint. Inside Compose that is `http://minio:9000` (not reachable from your browser). For clicking image links from the host, set `S3_ENDPOINT_URL=http://localhost:9000`. The API itself works either way.

## Config
All via environment variables (see [.env.example](.env.example)): `DATABASE_URL`, `S3_BUCKET`, `S3_ENDPOINT_URL` (set for MinIO, unset for real AWS), `AWS_REGION`, `APP_VERSION`, `ENVIRONMENT`. In the cluster, S3 is reached via **IRSA** (no keys), and DB creds come from a Secret.


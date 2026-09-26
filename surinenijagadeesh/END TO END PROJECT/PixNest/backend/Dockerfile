# Multi-stage build using uv (the fast Python package manager).

# ---- Stage 1: install dependencies into a venv from the locked versions ----
FROM python:3.13-slim AS build
COPY --from=ghcr.io/astral-sh/uv:0.12.10 /uv /bin/uv

# UV_COMPILE_BYTECODE: precompile .pyc for faster startup. UV_LINK_MODE=copy: safe across the cache mount.
ENV UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy \
    UV_PROJECT_ENVIRONMENT=/opt/venv

WORKDIR /app
# Install only third-party deps first (no app code) so this layer is cached until the lockfile changes.
# --frozen: fail if the lockfile is stale (reproducible builds).  --no-dev: skip test/lint tools.
RUN --mount=type=cache,target=/root/.cache/uv \
    --mount=type=bind,source=uv.lock,target=uv.lock \
    --mount=type=bind,source=pyproject.toml,target=pyproject.toml \
    uv sync --frozen --no-dev --no-install-project

# ---- Stage 2: slim runtime ----
FROM python:3.13-slim

# Patch the base image's OS packages. Official images are rebuilt on their own schedule, so a
# few days after a release they lag behind Debian's security updates - which is exactly what the
# Trivy gate catches: fixable CRITICAL/HIGH CVEs in perl-base, libsqlite3, libpcre2, gzip and
# friends, none of them our code. The frontend image does the same thing with `apk upgrade`.
#
# Only the RUNTIME stage needs this: the build stage never ships.
RUN apt-get update \
 && apt-get upgrade -y --no-install-recommends \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/*

COPY --from=build /opt/venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"
WORKDIR /app
COPY app/ ./app/

# The runtime image needs no package manager: the app runs from /opt/venv. Dropping the base
# image's pip and setuptools removes them AND their vendored libraries, which are a recurring
# source of CVE findings (e.g. pip's bundled msgpack, setuptools path traversal), and shrinks
# the attack surface. Nothing in the app imports pkg_resources.
RUN rm -rf /usr/local/lib/python3.*/site-packages/pip* \
           /usr/local/lib/python3.*/site-packages/setuptools* \
           /usr/local/lib/python3.*/site-packages/pkg_resources \
           /usr/local/lib/python3.*/site-packages/_distutils_hack \
           /usr/local/lib/python3.*/site-packages/distutils-precedence.pth \
           /usr/local/bin/pip*

# Non-root user for security. Use a NUMERIC uid so Kubernetes runAsNonRoot can verify it.
RUN useradd --create-home --uid 10001 appuser && chown -R 10001 /app
USER 10001

EXPOSE 8000

# gunicorn with uvicorn workers = production-grade ASGI serving. Access logs to stdout.
CMD ["gunicorn", "app.main:app", \
     "--worker-class", "uvicorn.workers.UvicornWorker", \
     "--bind", "0.0.0.0:8000", \
     "--workers", "2", \
     "--access-logfile", "-", \
     "--graceful-timeout", "30"]

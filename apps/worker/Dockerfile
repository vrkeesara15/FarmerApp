# FarmerApp worker image. Build context: the repository root (shares the farmerapp package in
# apps/api and needs the monorepo rules/ directory; the root .dockerignore admits only those):
#   docker build -f apps/worker/Dockerfile .
FROM python:3.12-slim
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 \
    UV_PROJECT_ENVIRONMENT=/opt/venv UV_LINK_MODE=copy UV_COMPILE_BYTECODE=1 \
    PATH="/opt/venv/bin:$PATH" SERVICE_NAME=worker RULES_DIR=/app/rules
COPY --from=ghcr.io/astral-sh/uv:0.11 /uv /usr/local/bin/uv
RUN groupadd --system app && useradd --system --gid app --uid 10001 --create-home app
WORKDIR /app
COPY apps/api/pyproject.toml apps/api/uv.lock apps/api/.python-version apps/api/README.md ./
RUN --mount=type=cache,target=/root/.cache/uv uv sync --frozen --no-dev --no-install-project
COPY apps/api/farmerapp ./farmerapp
# VA-001: event rules run in the worker; the YAML is read at startup from RULES_DIR.
COPY rules ./rules
RUN --mount=type=cache,target=/root/.cache/uv uv sync --frozen --no-dev
RUN chown -R app:app /app
USER app
EXPOSE 8080
CMD ["uvicorn", "farmerapp.worker.app:app", "--host", "0.0.0.0", "--port", "8080"]

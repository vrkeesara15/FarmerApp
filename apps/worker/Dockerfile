# FarmerApp worker image. Build context MUST be apps/api (shares the farmerapp package):
#   docker build -f apps/worker/Dockerfile apps/api
FROM python:3.12-slim
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 \
    UV_PROJECT_ENVIRONMENT=/opt/venv UV_LINK_MODE=copy UV_COMPILE_BYTECODE=1 \
    PATH="/opt/venv/bin:$PATH" SERVICE_NAME=worker
COPY --from=ghcr.io/astral-sh/uv:0.11 /uv /usr/local/bin/uv
RUN groupadd --system app && useradd --system --gid app --uid 10001 --create-home app
WORKDIR /app
COPY pyproject.toml uv.lock .python-version README.md ./
RUN --mount=type=cache,target=/root/.cache/uv uv sync --frozen --no-dev --no-install-project
COPY farmerapp ./farmerapp
RUN --mount=type=cache,target=/root/.cache/uv uv sync --frozen --no-dev
RUN chown -R app:app /app
USER app
EXPOSE 8080
CMD ["uvicorn", "farmerapp.worker.app:app", "--host", "0.0.0.0", "--port", "8080"]

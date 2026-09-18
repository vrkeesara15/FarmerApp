FROM python:3.12-slim
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 UV_PROJECT_ENVIRONMENT=/opt/venv \
    UV_LINK_MODE=copy PATH="/opt/venv/bin:$PATH"
COPY --from=ghcr.io/astral-sh/uv:0.11 /uv /usr/local/bin/uv
RUN groupadd --system app && useradd --system --gid app --uid 10001 --create-home app
WORKDIR /app
COPY pyproject.toml ./
RUN --mount=type=cache,target=/root/.cache/uv uv sync --no-dev --no-install-project
COPY mockserver ./mockserver
RUN --mount=type=cache,target=/root/.cache/uv uv sync --no-dev
USER app
EXPOSE 8090
CMD ["uvicorn", "mockserver.app:app", "--host", "0.0.0.0", "--port", "8090"]

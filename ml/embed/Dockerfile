# FarmerApp embed service (DX-002) — Cloud Run `embed`, port 8080, CPU torch.
# Build (from ml/embed):  docker build --platform linux/amd64 -t embed:2024-01 .
# The pinned weights are baked in at build time; the container never calls Hugging Face at runtime.

# ---- deps: CPU-only torch + app deps from uv.lock ------------------------------------------------
FROM python:3.12-slim AS deps
COPY --from=ghcr.io/astral-sh/uv:0.11.14 /uv /bin/uv
ENV UV_COMPILE_BYTECODE=1 UV_LINK_MODE=copy UV_PYTHON_DOWNLOADS=never UV_PROJECT_ENVIRONMENT=/opt/venv
WORKDIR /src
COPY pyproject.toml uv.lock .python-version ./
RUN uv sync --frozen --no-dev --no-install-project \
 && find /opt/venv -name "*.pyc" -path "*/tests/*" -delete \
 && rm -rf /opt/venv/lib/python3.12/site-packages/torch/include \
           /opt/venv/lib/python3.12/site-packages/torch/share

# ---- model: pinned revision, sha256-checked, vision tower only -----------------------------------
FROM deps AS model
COPY embed/__init__.py embed/spec.py embed/fetch.py ./embed/
RUN /opt/venv/bin/python -m embed.fetch --out /opt/model \
 && chmod -R a+rX,go-w /opt/model \
 && rm -rf /root/.cache

# ---- runtime -------------------------------------------------------------------------------------
FROM python:3.12-slim
RUN groupadd --system --gid 10001 embed && useradd --system --uid 10001 --gid embed --no-create-home embed
COPY --from=deps /opt/venv /opt/venv
COPY --from=model /opt/model /opt/model
WORKDIR /app
COPY embed ./embed
ENV PATH=/opt/venv/bin:$PATH \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    HF_HUB_OFFLINE=1 \
    TRANSFORMERS_OFFLINE=1 \
    EMBED_MODEL_DIR=/opt/model \
    EMBED_DEVICE=cpu \
    EMBED_THREADS=2 \
    OMP_NUM_THREADS=2 \
    MKL_NUM_THREADS=2 \
    PORT=8080
USER 10001:10001
EXPOSE 8080
# One process: the model is loaded once (lifespan) before the port opens (Cloud Run TCP startup probe).
CMD ["sh", "-c", "exec uvicorn --factory embed.app:app_from_env --host 0.0.0.0 --port ${PORT} --workers 1 --no-access-log"]

# apps/api — FarmerApp backend package

One Python package, `farmerapp`, with three entrypoints:

| Entrypoint | Command | Deployable |
|---|---|---|
| `farmerapp.api.app:app` | `uvicorn farmerapp.api.app:app` | api (Cloud Run) |
| `farmerapp.worker.app:app` | `uvicorn farmerapp.worker.app:app` | worker (Cloud Run, Pub/Sub push) |
| `farmerapp.jobs` | `python -m farmerapp.jobs <job>` | jobs (Cloud Run Jobs) |

`apps/worker` and `apps/jobs` only hold a Dockerfile + README; they build from this directory.

## Layout

```
farmerapp/
  settings.py     pydantic-settings (env vars, see /.env.example)
  logging.py      structlog JSON logging, trace id per request
  api/            FastAPI app factory, /v1/health, RFC 9457 errors
  db/             async engine/session, tenant hook, Base + column mixin, models
  worker/         Pub/Sub push receiver + dispatch table by topic (SPEC 9.2)
  jobs/           typer CLI (hello, seed)
alembic/          async Alembic env + migrations
scripts/          export_openapi.py (writes/checks openapi.yaml)
tests/            pytest (needs the compose db: `make db`)
```

## Everyday commands (from repo root)

```
make up          # db, pubsub, gcs, mockserver
make migrate     # alembic upgrade head
make test-api    # pytest with coverage
make check-api   # ruff, mypy strict, pytest, openapi diff, bandit, pip-audit
make openapi     # regenerate apps/api/openapi.yaml (commit it)
```

Inside this directory: `uv sync`, then `uv run <cmd>`.

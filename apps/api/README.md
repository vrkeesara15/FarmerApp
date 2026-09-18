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
  api/            FastAPI app factory, /v1/health, RFC 9457 errors, CORS, scheduler ticker
  auth/           FA-001 phone + OTP login, JWT access/refresh (SEC-020/021), get_current_user,
                  SMS/WhatsApp provider adapters (fake, mockserver), delayed-task scheduler seam
  db/             async engine/session, tenant + auth bypass hooks, Base + column mixin, models
  worker/         Pub/Sub push receiver + dispatch table by topic (SPEC 9.2)
  jobs/           typer CLI (hello, seed = demo tenant "fcc" + one user per role)
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

## Auth (FA-001)

```
make seed                      # tenant "Future Crop Care" (fcc) + users +91900000000{1..5}, +919000000010
uvicorn farmerapp.api.app:app  # then POST /v1/auth/otp/send {"phone": "+919000000004"}
curl localhost:8090/sms/messages?to=%2B919000000004   # read the code from the mockserver
```

With `OTP_DEV_CODE=123456` in `.env` (local/dev only) the fixed code is accepted as well.
Delayed OTP delivery checks (WhatsApp fallback after 30 s) run in-process locally
(`farmerapp.auth.scheduler.InProcessScheduler`); production will publish `notify.send`
(TODO OPS-004). Tests use `FakeProvider` + `FakeClock`; `pytest -m integration` also talks to
the compose mockserver when it is up.

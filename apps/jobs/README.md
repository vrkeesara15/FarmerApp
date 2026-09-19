# apps/jobs

Batch jobs (SPEC 8.1): nightly validation, evaluation, exports, retention purge, beat
plans. There is no code here: it runs the `farmerapp` package from `apps/api`.

- Entrypoint: `python -m farmerapp.jobs <job>` (typer CLI in `apps/api/farmerapp/jobs/cli.py`).
- Jobs today: `hello` (no-op smoke), `seed` (stub; demo tenant arrives with M1-KICKOFF).
- Build (context is the repo root; the image carries `rules/` with `RULES_DIR=/app/rules`): `docker build -f apps/jobs/Dockerfile . -t farmerapp-jobs`
- Run: `docker run --rm farmerapp-jobs seed`, or locally `cd apps/api && uv run python -m farmerapp.jobs seed`.

The image also carries Alembic so the deploy pipeline can run `alembic upgrade head` as a
Cloud Run Job before rolling out the api.

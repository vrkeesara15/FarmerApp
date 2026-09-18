# apps/worker

The Pub/Sub push worker (SPEC 8.1). There is no code here: it runs the `farmerapp`
package from `apps/api` with a different entrypoint.

- Entrypoint: `uvicorn farmerapp.worker.app:app` (push receiver at `POST /push`).
- Code: `apps/api/farmerapp/worker/` — `topics.py` (SPEC 9.2 topic names),
  `messages.py` (push envelope), `dispatch.py` (topic -> handler table).
- Build (context is `apps/api`): `docker build -f apps/worker/Dockerfile apps/api -t farmerapp-worker`
- Run locally: `cd apps/api && uv run uvicorn farmerapp.worker.app:app --port 8080`

Pub/Sub push subscriptions are named `<topic-with-dashes>-worker` so the topic can be
derived from the subscription; publishers may also set a `topic` message attribute.
2xx acks; 4xx/5xx nacks (retry, then dead-letter).

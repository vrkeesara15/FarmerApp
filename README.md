# FarmerApp

Multi-tenant agri-retail platform for India: a field-agent Android app (with a tablet store mode), a farmer
Android app, and a web console for owners and managers. Field officers register farmers and farms, verify visits
with a proof-of-visit bundle, and sell inputs; farmers get an agronomist-verified crop diagnosis, advisory and
UPI payments; the console gives owners dashboards, validation flags and analytics.
Stack: FastAPI + Postgres (PostGIS, pgvector) on Cloud Run, Next.js console, Flutter apps, Terraform on GCP, dbt on BigQuery.

## Repository layout (SPEC 10.1)

```
farmerapp/
  CLAUDE.md                 # instructions for Claude Code (SPEC 14.2)
  docs/SPEC.md              # the specification — requirement IDs are the scope
  docs/progress.md          # status per requirement ID
  docs/adr/                 # architecture decision records
  docs/runbooks/            # operational runbooks (SPEC 12.5)
  design/                   # tokens.json, screens/, components/, copy.csv
  apps/
    api/                    # FastAPI, SQLAlchemy 2, Alembic, pytest
    worker/                 # shares the api domain package; Pub/Sub handlers
    jobs/                   # batch jobs, validation agents (batch)
    console/                # Next.js 15, TypeScript, Tailwind, shadcn/ui, TanStack Query
    mobile/
      packages/core/        # models, generated API client, sync, design system, i18n
      apps/agent/           # field agent app (+ store mode)
      apps/farmer/          # farmer app
  ml/
    ondevice/               # crop + quality model training, TFLite export
    embed/                  # encoder service
    eval/                   # test sets, evaluation scripts
  rules/                    # validation agent rules (YAML) + fixtures
  dbt/                      # analytics models
  infra/                    # Terraform (SPEC 9)
  .github/workflows/        # CI/CD (SPEC 10.3)
```

## Quick start

```bash
make up       # Postgres 16 + PostGIS 3 + pgvector (native multi-arch image), Pub/Sub emulator, fake GCS, mock SMS/payment servers
make seed     # demo tenant: 5 stores, 5 officers, 200 farmers
make check    # the same lint, type, test and infra checks CI runs — must pass before "done"
```

Other targets: `make test-api`, `make test-console`, `make test-mobile`, `make plan-dev`.

## Where to look

- [docs/SPEC.md](docs/SPEC.md) — product, design and engineering specification (source of truth)
- [docs/progress.md](docs/progress.md) — requirement status (`todo | in-progress | done | blocked`)
- [CLAUDE.md](CLAUDE.md) — working rules, stack lock, human-only gates
- [infra/README.md](infra/README.md) — bootstrap order, plan/apply rules
- [docs/runbooks/](docs/runbooks/README.md) — runbooks to write before pilot

## Delivery

Trunk-based: branch `feat/<ID>-<slug>`, Conventional Commit with the requirement ID, PR template with test
evidence, squash merge. Merge to `main` deploys **dev** automatically; staging and production are human-approved
(`deploy.yml`, SPEC 10.4). Terraform apply to stg/prd, production deploys and Play Console releases are human-only.

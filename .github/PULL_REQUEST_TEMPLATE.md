## Requirement IDs

<!-- e.g. FA-012, SEC-011. PR title: feat(FA-012): capture farm boundary -->

- 

## What changed

<!-- 2–5 lines. Link the screen spec (design/screens/<ID>.md) for UI work. -->

## Screenshots / goldens (UI changes)

<!-- Console: before/after. Mobile: golden or device screenshot, English + one Indic language. -->

## Migration notes

- [ ] No schema change
- [ ] Alembic migration added; backward compatible (expand → migrate → contract)
- [ ] RLS policy + tenant_id on every new table
- [ ] Data backfill / retention impact described below

## Test evidence

<!-- `make check` output summary, coverage, authz matrix result, rule fixtures, e2e run link. -->

## Checklist

- [ ] Tests written first; acceptance criteria covered
- [ ] Role + tenant authorisation tests for every new endpoint (SEC-006, SEC-012)
- [ ] Strings externalised (no hard-coded copy); money in integer paise; timestamps UTC
- [ ] No secrets in code, fixtures or logs (Secret Manager refs, `.env.example` updated)
- [ ] OpenAPI (`apps/api/openapi.yaml`) and `docs/progress.md` updated in this PR
- [ ] Logs / metrics / alerts added where the requirement has an OPS or SLO link
- [ ] Runbook updated if operational behaviour changed
- [ ] `infra/`, `rules/`, payments or auth code: 2 reviewers (CODEOWNERS)

### Mobile releases only

- [ ] VV-009: location disclosure screen, demo video and privacy text unchanged or re-approved
- [ ] Prominent-disclosure / background-location copy matches design/copy.csv
- [ ] versionCode from CI run number; obfuscation on; MobSF scan attached (SEC-008)
- [ ] Release notes in English + Telugu/Hindi

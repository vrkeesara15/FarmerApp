# Progress by requirement ID

Status values: `todo` | `in-progress` | `done` | `blocked (reason)`.
Milestone column follows SPEC §14.1. Each row records files changed when done.

## M0 — Foundations (target 2026-10-09)
| ID | Requirement | Status | Notes |
|---|---|---|---|
| M0-KICKOFF | Scaffold monorepo, docker compose, Makefile, Terraform dev+bootstrap, CI skeletons, design system in Flutter + React | done | 2026-09-17. apps/api (FastAPI, Alembic 0001 extensions+tenant, worker/jobs entrypoints, 24 tests), docker/ + docker-compose.yml + Makefile, apps/console (Next.js 15, 23 DS components, 78 vitest + 4 Playwright), apps/mobile (pub workspace, farmerapp_core with 29 widgets + 5 ARB + 62 goldens, agent/farmer apps), infra/ (bootstrap + 11 modules + dev/stg/prd), .github/ (9 workflows). `make check` green. |
| FA-001 | Phone + OTP login | done | 2026-09-17. API: `farmerapp/auth/` (models user/otp_challenge/refresh_token, otp.py, tokens.py, deps.py get_current_user + tenant binding, providers fake/mockserver, scheduler seam, router `/v1/auth/otp/send|verify`, `/v1/auth/refresh|logout`, `/v1/me`), Alembic 0002, settings (OTP_*, JWT_*, CORS, prd guard rails), `jobs seed` (tenant fcc + 6 users), db `set_bypass_rls`, mockserver `/sms/status`, openapi.yaml; 62 75 pytest added under tests/auth (fake clock/provider, 1 `integration`) + 3 elsewhere; 102 total. Console: `lib/api.ts` auth+session, `app/api/session*` httpOnly refresh cookie, mock API in sync, LoginForm error states, +20 vitest, Playwright smoke green. Mobile: `HttpAuthApi`, `TokenStore` (secure storage, device_id), `AuthFailure` states, A03/A04 + F02/F03 wired, ARB en+te, +23 tests. PR: docs/prs/FA-001.md. Deferred: real SMS/WhatsApp adapters (human: DLT), Pub/Sub delayed check (OPS-004), phone in several tenants (WC-014). |
| FA-002 | Role-based access | done | 2026-09-17. `apps/api/farmerapp/auth/policy.py`: `Role` (= `UserRole`, 10 roles), `require_roles(*roles, self_param=)` dependency, `PUBLIC` marker, `install_policies()` startup check (app refuses to start if any route lacks a policy) that also writes `x-roles` / `x-public` / `x-self` and the 401/403 problems into `openapi.yaml`; 403 is problem+json `forbidden`, logged WARNING `authz_forbidden` (actor id, role, tenant, method, route template; no PII). `auth/scope.py`: SPEC 2.6 matrix as SQLAlchemy filters (`scope_filters`, `user_scope`; reusable for farmers/visits/khata). Policies: health + `/v1/auth/*` public, `/v1/me` all roles, new `farmerapp/users/` (`GET /v1/users` owner/director/cluster_head/auditor/tenant_admin with cluster scope + cursor pagination `api/pagination.py`; `GET /v1/users/{id}` same roles + self; `PATCH /v1/users/{id}` owner/director/tenant_admin: name/role/status/store_id/cluster_id). Disabled account with a valid access token is now 401 `user_disabled` (login stays 403). Seed: second tenant "Green Fields" (`gfl`), 10 users per tenant. `apps/api/README.md` section. PR: docs/prs/FA-002.md. |
| FA-003 | Tenant isolation (RLS) | done | 2026-09-17. Alembic `0003_rls_roles` (roles `farmerapp_app` DML-only / `farmerapp_migrate` owner / `farmerapp_auth` lookup owner; `app_current_tenant()`; ENABLE+FORCE RLS with `tenant_isolation` + `maintenance` policies on tenant/user/otp_challenge/refresh_token; `auth_find_user_by_phone` / `auth_find_refresh_token` SECURITY DEFINER id lookups; `app.bypass_rls` removed). `farmerapp/db/rls.py` (`enable_rls` for migrations, `rls_violations` meta-check), `db/session.py` (`tenant_scope`, `job_session`, `clear_tenant`), auth otp/tokens resolve the tenant via the lookups, seed with fixed tenant ids as the app role, settings `MIGRATION_DATABASE_URL`, `docker/postgres/initdb/10-roles.sql` + `make db-roles`, compose/CI/.env.example. 49 tests in `tests/rls/` (SQL as app role, API 404/401, catalogue meta-test incl. negative case, DDL denied, pool reuse); 262 total, 96.1% cov. ADR `docs/adr/0003-rls-design.md`; PR `docs/prs/FA-003.md`. Follow-ups: WC-014 tenant picker for a phone in several tenants. |
| FA-004 | Localisation, ARB files, no hard-coded strings | done | 2026-09-17. Mobile: `packages/core/lib/l10n/app_{te,kn,hi,mr}.arb` complete (196 keys each; `tool/check.sh` fails on any untranslated message), `state/settings.dart` (`SettingsStore`, `KvSettingsStore` over Drift `kv`, `settingsOverrides` loaded before first frame, `SettingsNotifier` persists), `db/open_database.dart`, `widgets/language_picker.dart` (tiles in their own language, Listen label, explicit a11y nodes, 144 dp), `widgets/language_setting_tile.dart`, A63/F70 `settings_screen.dart` shells + routes, `lib/string_lint.dart` + `tool/lint_strings.dart` (Text/label/tooltip/hintText/helperText/errorText/semanticsLabel, i18n-ignore, self-tested), tests: core 140 (+25: settings, ARB completeness, picker x5 locales, setting tile, Indic theme), agent 9 (+4), farmer 9 (+4), root lint 13. Console: `lib/i18n.ts` locale store + `useT()`/`useLocale()` (live switch, localStorage, `<html lang>` + init script), TopBar profile menu with 5 languages + sign out, all client components on `useT`, `PlaceholderPage`/`LoginHeader`/`SkipLink` client, `messages/{te,kn,hi,mr}.json` complete (142 keys), `scripts/lint-strings.mjs` takes paths + `lint-strings.test.ts`, vitest 114 (+16), Playwright +1 (5). Design: `design/screens/A02.md`, `F01.md`, `components/LanguagePicker.md`. PR: docs/prs/FA-004.md. Human gate: native-speaker review of translations (NF-008). |
| FA-006 | Audit trail | done | 2026-09-18. `apps/api/farmerapp/db/audit.py`: `Actor` ContextVar (bound by `get_current_user` from the request: ip = first `X-Forwarded-For` hop, `X-Device-Id` or the user's bound device, user agent, trace id; jobs/worker via `actor_scope(system_actor(tenant_id))`; unattributed writes = `system`), `before_flush` listener on every session writing an `audit_log` row in the same flush for each create/update/delete of any model with `tenant_id` (`__audit__ = False` opts out), diffs = changed columns + id, soft delete (`deleted_at`) = `<entity>.delete`, redaction in one place (`code_hash`/`token_hash` never, `phone` masked, `updated_at`/`version` excluded), `audit.record()` for explicit events (`auth.login`, `auth.logout` in `auth/router.py`). `db/models/audit_log.py` on lean `TenantRow` mixin (`db/base.py`); Alembic `0004_audit_log` (RLS, **append-only** grants for the app role, indexes; NF-012 retention note); `db/rls.py` `APPEND_ONLY_TABLES` + meta-check; `GET /v1/audit-logs` (`farmerapp/audit/`, owner/director/auditor/tenant_admin, filters entity/entity_id/actor_id/action/from/to, newest-first cursor via `PageRequest.before`); `jobs purge-audit-logs` dry run (400-day default, refuses < 365). 38 tests in `tests/audit/` (+ RLS matrix rows and the generated authz matrix for the new route); 315 total, 95% cov. PR: docs/prs/FA-006.md. Left: real purge/archive under OPS/NF-012, console viewer WC-103. |
| SEC-001 | Secret scanning (gitleaks) | done | 2026-09-17. security.yml: gitleaks on PR + nightly. GitHub-side secret scanning with push protection is a repo setting (human, once remote exists). CI not yet exercised: no GitHub remote configured. |
| SEC-002 | Static analysis (Semgrep, bandit) | done | 2026-09-17. security.yml semgrep p/python p/typescript p/owasp-top-ten; ci-api.yml bandit (also in `make check-api`). CI not yet exercised: no GitHub remote configured. |
| SEC-003 | Dependency vulnerabilities | done | 2026-09-17. ci-api pip-audit --strict; ci-console npm audit --audit-level=high; security.yml osv-scanner + trivy fs; dependabot.yml weekly for pip/npm/pub/actions/terraform. CI not yet exercised: no GitHub remote configured. |
| SEC-004 | Container image scanning (Trivy) | done | 2026-09-17. deploy.yml trivy image scan on built images; api/worker/jobs Dockerfiles python:3.12-slim with non-root USER app. CI not yet exercised: no GitHub remote configured. |
| SEC-005 | IaC misconfiguration (checkov, tflint) | done | 2026-09-17. ci-infra.yml tflint + checkov (infra/.tflint.hcl, infra/.checkov.yaml); security.yml trivy config on Terraform/Dockerfiles. CI not yet exercised: no GitHub remote configured. |
| SEC-006 | Authz test matrix per endpoint/role | done | 2026-09-17. `apps/api/tests/authz/test_matrix.py` is generated from `apps/api/openapi.yaml`: every non-public operation × 10 roles (allowed → not 401/403, denied → 403 `forbidden`), `x-self` access for every role, cross-tenant id → 404/403 with no tenant-B data in the body, collections never contain other tenants, no token → 401, unknown / disabled user → 401, forbidden call logged without PII (caplog); public operations need no token; `ROUTE_FIXTURES` table supplies path params/bodies for new routes. Plus `test_policy.py` (startup check, OpenAPI extensions), `test_scope.py`, `test_users.py`; fixtures seed both tenants and mint tokens directly. 110 tests (213 total, 97% coverage). |
| SEC-010 | One SA per deployable, no keys | done | 2026-09-17. infra/modules/iam: one `google_service_account` per deployable (api, console, worker, embed, jobs, scheduler…), bound to Cloud Run services/jobs; no default compute SA referenced. infra/bootstrap: `iam.disableServiceAccountKeyCreation` org policy on ops + env projects; CI uses WIF only. Apply is human-gated. |
| SEC-011 | Cloud SQL private IP, IAM auth, no DDL for app user | done | 2026-09-17. Terraform `infra/modules/sql` verified: `ipv4_enabled=false` + `private_network`, `ssl_mode=ENCRYPTED_ONLY`, `cloudsql.iam_authentication=on`, `google_sql_user` CLOUD_IAM_SERVICE_ACCOUNT for api/worker/jobs; SEC-011 notes + grant procedure in `main.tf`, `infra/README.md`. DDL separation by migration 0003 (`farmerapp_app` DML only, tested: 12 DDL/privilege statements denied, `alembic_version` unreadable); runtime `DATABASE_URL` vs Alembic `MIGRATION_DATABASE_URL` (prd refuses the same role). Human/one-off per env: `GRANT farmerapp_app TO <api,worker,jobs IAM users>`, `GRANT farmerapp_migrate TO <migrate SA>` after the first upgrade. Follow-up: dedicated migrate SA (migrate job runs as the jobs SA), IAM-token DB credentials in Cloud Run (`DB_IAM_AUTH` placeholder). |
| SEC-012 | Postgres RLS keyed on app.tenant_id, tested in CI | done | 2026-09-17. Transaction-local `set_config('app.tenant_id', ..., true)` per request (`get_session` + `get_current_user` before loading the user), `tenant_scope`/`job_session` for jobs/worker; policies fail closed when unset. `ci-api.yml` runs the suite as `farmerapp_app` (initdb role in the `docker/postgres` image) with the owner only for Alembic; `tests/rls/test_meta.py` fails any future table without `enable_rls`. See FA-003. |
| SEC-013 | Secrets in Secret Manager | done | 2026-09-17. infra/modules/secrets: secrets created empty with per-SA accessor bindings; values added via `gcloud secrets versions add` by an admin; `rotation_days`/`rotation_topic` inputs for 90-day rotation notifications (age alert tracked under OPS-014). No secrets in code: settings read env from Secret Manager `value_source`. |

## M1 — Farmers and farms (target 2026-10-30)
| ID | Requirement | Status | Notes |
|---|---|---|---|
| M1-KICKOFF | Alembic models for M1 entities, RLS, demo seed | todo | |
| FA-012 | Farmer registration | todo | |
| FA-013 | Multiple farms / crop plots | todo | |
| FA-025 | Offline-first sync engine | todo | |
| FM-002 | Consent data model | todo | |
| NF-002 | Offline 72 h | todo | |
| NF-003 | Sync outbox, idempotency, resumable uploads | todo | |
| NF-004 | Image budget | todo | |

## M2 — Duty, location and visits (target 2026-11-20)
| ID | Requirement | Status | Notes |
|---|---|---|---|
| M2-KICKOFF | Alembic models for M2 entities | todo | |
| FA-010 | Duty toggle, foreground service | todo | |
| FA-011 | First-run disclosure | todo | |
| FA-014 | Visit check-in geofence | todo | |
| FA-015 | Visit capture | todo | |
| FA-016 | Farmer confirmation | todo | |
| FA-017 | Check-out and duration | todo | |
| FA-028 | Mock-location / root / time-tamper detection | todo | |
| VV-001 | On-duty sampling | todo | |
| VV-002 | Point metadata | todo | |
| VV-003 | Geofence per farm / meeting point | todo | |
| VV-004 | Visit score | todo | |
| VV-005 | Visit status | todo | |
| VV-007 | Auto end of duty | todo | |
| VV-009 | Play Store background-location declaration | todo | |
| VV-010 | Employee location policy version | todo | |

## M3 — Catalogue, store mode, orders, payments, khata (target 2026-12-04)
| ID | Requirement | Status | Notes |
|---|---|---|---|
| M3-KICKOFF | Alembic models for M3 entities | todo | |
| FA-020 | Order capture | todo | |
| FA-021 | Payment collection | todo | |
| FA-022 | Khata view | todo | |
| ST-001 | Point of sale + GST invoice | todo | |
| ST-002 | Payment modes | todo | |
| ST-003 | Stock movements | todo | |
| ST-005 | Order queue | todo | |
| ST-006 | Day close | todo | |
| ST-007 | Credit approval | todo | |
| WC-005 | Product master + label claims | todo | |
| SEC-023 | Webhook HMAC + replay window | todo | |

## M4 — Console v1 and validation agents v1 (target 2026-12-11)
| ID | Requirement | Status | Notes |
|---|---|---|---|
| M4-KICKOFF | Rules engine (YAML), inline/event/batch modes, fixtures | todo | |
| WC-001 | Owner home | todo | |
| WC-002 | Field team | todo | |
| WC-003 | Farmers directory + 360 | todo | |
| WC-004 | Stores | todo | |
| WC-010 | Validation agent inbox | todo | |
| WC-011 | Users, roles, device binding, forced logout | todo | Minimal `/v1/users` list/get/patch (name, role, status, store_id, cluster_id) exist since FA-002 (2026-09-17) in `apps/api/farmerapp/users/`. Left: create/invite, device binding UI, forced logout (revoke refresh family when disabled; access tokens are already rejected on the next call), re-auth for role change (SEC-028), console screen. Audit rows for every change land automatically since FA-006 (2026-09-18). |
| WC-012 | Settings | todo | |
| WC-103 | Audit log viewer | todo | `GET /v1/audit-logs` (tenant-scoped, filters entity/entity_id/actor_id/action/from/to, cursor pagination, roles owner/director/auditor/tenant_admin) exists since FA-006 (2026-09-18) in `apps/api/farmerapp/audit/`; the console screen (C103) is left. |
| AN-001 | Owner home dashboard | todo | |
| AN-002 | Field team scorecard | todo | |
| AN-003 | Officer day replay | todo | |
| AN-011 | Dashboard filters in URL | todo | |
| VA-001 | Rules as versioned YAML | todo | |
| VA-002 | Flag contents | todo | |
| VA-003 | Routing | todo | |
| VA-007 | Golden fixtures per rule | todo | |
| VA-F01 | Phone format / OTP / staff blocklist | todo | |
| VA-F02 | Duplicate farmer | todo | |
| VA-F03 | Farm polygon sanity | todo | |
| VA-F06 | Registration burst | todo | |
| VA-F08 | Photo reuse | todo | |
| VA-E01 | Mock location / root / clock drift | todo | |
| VA-E02 | Impossible travel | todo | |
| VA-E03 | Clustered visits | todo | |
| VA-E04 | Short visits | todo | |
| VA-E05 | Confirmation anomalies | todo | |
| VA-E08 | Photo integrity | todo | |

## M5 — Pilot hardening (target 2026-12-18)
| ID | Requirement | Status | Notes |
|---|---|---|---|
| OPS-001 | Uptime checks | todo | |
| OPS-002 | Error rate / crash-free | todo | |
| OPS-003 | Cloud SQL alerts | todo | |
| OPS-004 | Pub/Sub age / DLQ | todo | |
| OPS-005 | Job failures | todo | |
| OPS-006 | Officer sync silence | todo | |
| OPS-007 | Store zero sales / not closed | todo | |
| OPS-008 | Payment reconciliation | todo | |
| OPS-009 | Diagnosis queue age | todo | |
| OPS-010 | Flags past SLA | todo | |
| SEC-014 | Cloud Armor | todo | |
| SEC-015 | Ingress from LB only | todo | |
| SEC-016 | Private buckets, signed URLs | todo | |
| SEC-017 | Audit logs export | todo | |
| SEC-018 | Org policies | todo | |
| SEC-019 | SCC | todo | |
| SEC-024 | Mobile local DB encryption, pinning, Play Integrity | todo | |
| SEC-025 | Remote wipe | todo | |
| SEC-026 | PII field-level encryption | todo | |
| NF-005 | Performance | todo | |
| NF-006 | Availability | todo | |

## M6 — Diagnosis engine + farmer app v1 (target 2027-02-26)
| ID | Requirement | Status | Notes |
|---|---|---|---|
| M6-KICKOFF | Diagnosis pipeline, pluggable encoder/LLM, HNSW index, eval script | todo | |
| DX-001 | On-device TFLite model | todo | |
| DX-002 | Server embedding, pgvector HNSW | todo | |
| DX-003 | Decision rule | todo | |
| DX-004 | LLM fallback | todo | |
| DX-005 | Result provenance | todo | |
| DX-006 | Agronomist review SLA | todo | |
| DX-007 | Treatment engine with label-claim filter | todo | |
| DX-008 | Ranking | todo | |
| DX-009 | Dosage and safety | todo | |
| DX-010 | Out-of-scope handling | todo | |
| FM-001 | Farmer login | todo | |
| FM-002 | Consent screen | todo | |
| FM-003 | Profile | todo | |
| FM-004 | Crop doctor camera | todo | |
| FM-005 | Diagnosis result | todo | |
| FM-006 | One-tap actions | todo | |
| FM-010 | Orders, khata, pay dues | todo | |
| FM-011 | Visit confirmation + rating | todo | |
| FM-014 | App size < 25 MB | todo | |
| FM-015 | Delete account | todo | |
| FA-019 | Scouting | todo | |
| WC-006 | Agronomist review queue | todo | |
| WC-007 | Corpus manager | todo | |

## M7 — Analytics and growth (target 2027-05-14)
| ID | Requirement | Status | Notes |
|---|---|---|---|
| M7-KICKOFF | Datastream → BigQuery, dbt staging + marts | todo | |
| AN-004 | Farmer 360 and segments | todo | |
| AN-005 | Store performance | todo | |
| AN-006 | Crop health map | todo | |
| AN-007 | Diagnosis quality | todo | |
| AN-008 | Campaign ROI | todo | |
| AN-009 | Data quality | todo | |
| AN-010 | CDC latency | todo | |
| AN-012 | dbt tests | todo | |
| AN-013 | BigQuery RLS | todo | |
| AN-014 | PII minimisation in marts | todo | |
| AN-015 | Weekly owner email | todo | |
| WC-008 | Campaigns | todo | |
| WC-009 | Targets and incentives | todo | |
| WC-013 | Exports and scheduled reports | todo | |
| FM-007 | Crop calendar | todo | |
| FM-008 | Weather | todo | |
| FM-009 | Pest alerts | todo | |
| FA-018 | Beat plan | todo | |
| FA-023 | Travel allowance | todo | |
| FA-024 | My performance | todo | |
| FA-026 | Demo plots | todo | |
| FA-027 | Farmer meeting | todo | |
| DX-011 | Nightly evaluation | todo | |
| DX-012 | Retraining pipeline | todo | |
| DX-013 | Outbreak detection | todo | |
| VA-004 | Review agent summary | todo | |
| VA-005 | Employee sees own flags | todo | |
| VA-006 | Precision tracking | todo | |
| VA-F04 | Farm location plausibility | todo | |
| VA-F05 | Crop plausibility | todo | |
| VA-F07 | Ghost farmer | todo | |
| VA-F09 | Consent missing in segment | todo | |
| VA-F10 | Credit risk | todo | |
| VA-E06 | Duty with no activity | todo | |
| VA-E07 | TA claim vs km | todo | |
| VA-E09 | Sales anomalies | todo | |
| VA-E10 | Cash variance | todo | |
| VA-E11 | Performance drift | todo | |
| FA-005 | Voice input | todo | |
| FA-007 | Push notifications + inbox | todo | |
| ST-004 | Low-stock / expiry alerts | todo | |
| ST-008 | Tally/Zoho export | todo | |
| VV-006 | Track processing | todo | |
| VV-008 | Officer day timeline | todo | |
| SEC-007 | License compliance | todo | |
| SEC-008 | MobSF scan | todo | |
| SEC-020 | JWT lifetimes, rotation, reuse detection | todo | Partly done with FA-001 (2026-09-17): HS256 access 15 min, refresh 30 days rotated on every use, reuse revokes the family (`refresh_reused`), refresh bound to `device_id` for mobile clients, logout revokes the family; tests in apps/api/tests/auth/test_tokens.py. Left: RS256 + JWKS, key rotation, forced logout (WC-011). |
| SEC-021 | OTP hashing, velocity | todo | Partly done with FA-001 (2026-09-17): HMAC-SHA256 with server pepper bound to the challenge id, constant-time compare, single use, 5-attempt lockout (15 min), 3 resends / 15 min per phone, no code or full phone in logs. Left: per-country block, IP/ASN velocity (Cloud Armor SEC-014), provider-side SMS pumping controls. |
| SEC-022 | Input validation, CSP | todo | |
| SEC-027 | LLM calls: no PII | todo | |
| SEC-028 | Admin re-auth | todo | `PATCH /v1/users/{id}` (FA-002) changes roles without re-auth yet. The "audited" half is done with FA-006 (2026-09-18): every role/status change writes an `audit_log` row with actor, device, ip and old/new values; login/logout are audited too. Left: re-auth (fresh OTP) before role change, export and settings changes. |
| OPS-011 | Datastream lag / dbt failure | todo | |
| OPS-012 | Cost alerts | todo | |
| OPS-013 | Security alerts | todo | |
| OPS-014 | Cert / secret age | todo | |
| NF-001 | Devices | todo | |
| NF-008 | Localisation formats | todo | Indian number grouping, DD-MM-YYYY dates, acre/litre units done in M0 (`packages/core/lib/src/utils/format.dart`, console `lib/format.ts`). Five languages populated with FA-004 (2026-09-17). Left: review of all farmer-facing text by a native speaker per language (human gate) before pilot. |
| NF-009 | Accessibility | todo | |
| NF-010 | Literacy | todo | |
| NF-011 | Data residency | todo | |
| NF-012 | Retention | todo | Audit logs: 1 year minimum documented in Alembic 0004 (FA-006, 2026-09-18); `python -m farmerapp.jobs purge-audit-logs` is a dry run (400-day default, refuses < 365) — the real purge (archive to the exports bucket, delete as the migrate role) is still to do. Other retention classes untouched. |
| NF-013 | DPDP | todo | |
| NF-014 | Observability | todo | |
| NF-015 | Cost | todo | |
| NF-016 | Maintainability | todo | |

## M8 — SaaS readiness (target FY28 Q1)
| ID | Requirement | Status | Notes |
|---|---|---|---|
| FA-008 | Tenant branding | todo | |
| WC-014 | Tenant admin | todo | |
| NF-007 | Scale target | todo | |
| AN-016 | NL questions over marts | todo | |
| FM-012 | Mandi prices | todo | |
| FM-013 | Referral | todo | |

## Open questions (SPEC §0.3) — not resolved; assumptions used
- Languages: all five (en, te, kn, hi, mr) populated (FA-004); native-speaker review pending (NF-008).
- Pilot crops: paddy, cotton, chilli, maize, tomato, groundnut (proposal accepted as default).
- TA rate: placeholder ₹4/km in tenant settings; incentive rules TBD.
- Payments: Razorpay test mode, Cashfree adapter interface only.
- Accounting sync: CSV export (ST-008) only.
- Product master ownership and CIB&RC source: seeded from a fixture; human to replace.
- Legal text for location policy / consent: placeholder copy marked TODO-LEGAL, versioned.

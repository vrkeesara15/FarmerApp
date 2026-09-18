# Progress by requirement ID

Status values: `todo` | `in-progress` | `done` | `blocked (reason)`.
Milestone column follows SPEC §14.1. Each row records files changed when done.

## M0 — Foundations (target 2026-10-09)
| ID | Requirement | Status | Notes |
|---|---|---|---|
| M0-KICKOFF | Scaffold monorepo, docker compose, Makefile, Terraform dev+bootstrap, CI skeletons, design system in Flutter + React | done | 2026-09-17. apps/api (FastAPI, Alembic 0001 extensions+tenant, worker/jobs entrypoints, 24 tests), docker/ + docker-compose.yml + Makefile, apps/console (Next.js 15, 23 DS components, 78 vitest + 4 Playwright), apps/mobile (pub workspace, farmerapp_core with 29 widgets + 5 ARB + 62 goldens, agent/farmer apps), infra/ (bootstrap + 11 modules + dev/stg/prd), .github/ (9 workflows). `make check` green. |
| FA-001 | Phone + OTP login | todo | |
| FA-002 | Role-based access | todo | |
| FA-003 | Tenant isolation (RLS) | todo | |
| FA-004 | Localisation, ARB files, no hard-coded strings | todo | |
| FA-006 | Audit trail | todo | |
| SEC-001 | Secret scanning (gitleaks) | done | 2026-09-17. security.yml: gitleaks on PR + nightly. GitHub-side secret scanning with push protection is a repo setting (human, once remote exists). CI not yet exercised: no GitHub remote configured. |
| SEC-002 | Static analysis (Semgrep, bandit) | done | 2026-09-17. security.yml semgrep p/python p/typescript p/owasp-top-ten; ci-api.yml bandit (also in `make check-api`). CI not yet exercised: no GitHub remote configured. |
| SEC-003 | Dependency vulnerabilities | done | 2026-09-17. ci-api pip-audit --strict; ci-console npm audit --audit-level=high; security.yml osv-scanner + trivy fs; dependabot.yml weekly for pip/npm/pub/actions/terraform. CI not yet exercised: no GitHub remote configured. |
| SEC-004 | Container image scanning (Trivy) | done | 2026-09-17. deploy.yml trivy image scan on built images; api/worker/jobs Dockerfiles python:3.12-slim with non-root USER app. CI not yet exercised: no GitHub remote configured. |
| SEC-005 | IaC misconfiguration (checkov, tflint) | done | 2026-09-17. ci-infra.yml tflint + checkov (infra/.tflint.hcl, infra/.checkov.yaml); security.yml trivy config on Terraform/Dockerfiles. CI not yet exercised: no GitHub remote configured. |
| SEC-006 | Authz test matrix per endpoint/role | todo | |
| SEC-010 | One SA per deployable, no keys | todo | |
| SEC-011 | Cloud SQL private IP, IAM auth, no DDL for app user | todo | |
| SEC-012 | Postgres RLS keyed on app.tenant_id, tested in CI | todo | |
| SEC-013 | Secrets in Secret Manager | todo | |

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
| WC-011 | Users, roles, device binding, forced logout | todo | |
| WC-012 | Settings | todo | |
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
| SEC-020 | JWT lifetimes, rotation, reuse detection | todo | |
| SEC-021 | OTP hashing, velocity | todo | |
| SEC-022 | Input validation, CSP | todo | |
| SEC-027 | LLM calls: no PII | todo | |
| SEC-028 | Admin re-auth | todo | |
| OPS-011 | Datastream lag / dbt failure | todo | |
| OPS-012 | Cost alerts | todo | |
| OPS-013 | Security alerts | todo | |
| OPS-014 | Cert / secret age | todo | |
| NF-001 | Devices | todo | |
| NF-008 | Localisation formats | todo | |
| NF-009 | Accessibility | todo | |
| NF-010 | Literacy | todo | |
| NF-011 | Data residency | todo | |
| NF-012 | Retention | todo | |
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
- Languages: all five (en, te, kn, hi, mr) scaffolded; en + te populated first.
- Pilot crops: paddy, cotton, chilli, maize, tomato, groundnut (proposal accepted as default).
- TA rate: placeholder ₹4/km in tenant settings; incentive rules TBD.
- Payments: Razorpay test mode, Cashfree adapter interface only.
- Accounting sync: CSV export (ST-008) only.
- Product master ownership and CIB&RC source: seeded from a fixture; human to replace.
- Legal text for location policy / consent: placeholder copy marked TODO-LEGAL, versioned.

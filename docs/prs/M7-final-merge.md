# M7 — final merge: security and privacy, observability, cost, accessibility, campaign replication

Lands the last two M7 branches on `main` and closes the one follow-up the analytics workstream
left behind.

* `merge(M7): feat/M7-security-privacy` — SEC-007, SEC-008, SEC-020, SEC-021, SEC-022, SEC-027,
  NF-011, NF-012, NF-013, NF-016 (`docs/prs/M7-security-privacy.md`).
* `merge(M7): feat/M7-ops-device` — OPS-011..014, NF-001, NF-008, NF-009, NF-010, NF-014,
  NF-015 (`docs/prs/M7-ops-device.md`).
* `feat(M7): …replicate campaign tables` — the AN-008 / AN-014 allowlist follow-up, plus the
  five things the merge itself broke.

---

## The merge

Security first, then ops-device. The two branches turn out to touch **no source file in
common** — only `docs/progress.md` and `docs/runbooks/README.md` — so the accessibility-corrected
design tokens and their regenerated goldens land untouched, and no golden had to be
re-recorded for a cross-branch reason.

| Conflict | Resolution |
|---|---|
| `docs/progress.md` (both merges) | Row union, keeping the more advanced status per requirement id. |
| `apps/console/messages/{en,hi,kn,mr,te}.json` | Deep JSON union of ours and theirs, not a text merge: 75 top-level keys each, key sets **identical across all five locales** afterwards. The writer round-trips the existing formatting byte for byte, so the diff is only the added keys. |
| `apps/api/openapi.yaml` | Not hand-merged. Regenerated with `make openapi`; both sides' operations are present (8 privacy paths, the analytics paths) and `export_openapi.py --check` is clean at the end. |

### Alembic

The merge left two heads — `0036` (AN-004 `saved_segment`) and `0040` (SEC-021 / NF-013) — both
branched from `0035`. `0041_merge_security_privacy.py` rejoins them: an empty up/down, because
the two branches are expand-only over disjoint objects.

Verified on a scratch database (`alembic_roundtrip`, dropped afterwards): `alembic heads` is a
single `0041`, `upgrade head` → `downgrade base` → `upgrade head` all succeed, and `current`
ends at `0041 (head) (mergepoint)`.

---

## AN-008 / AN-014 — campaign tables replicated

`campaign` (15 columns) and `campaign_recipient` (14) are now in
`infra/modules/analytics/replicated_columns.json`, following the existing pattern: ids, the
tenant, the foreign keys, the enums, the timestamps — and **none of the PII or free text**. No
`name`, no `segment` (the audience definition stays in Postgres), no message body, no notes,
no phone. `dbt/scripts/check_replication.py` validates them exactly as it does every other
table, and its `PENDING_REPLICATION` escape hatch is now **empty**, which is the state that
script is written to keep: all 28 replicated tables are declared in one place.

The escape hatch and its "now replicated — drop it from `PENDING_REPLICATION`" error are kept
for the next table that needs them; the comment says so. `dbt/README.md` was updated to match.
The `terraform test` that pins the stream's table count reads the JSON, so it followed on its
own.

**Remaining human gate:** after the Terraform apply, re-run
`python3 infra/scripts/datastream_sql.py --part owner` on the instance (grants, policy,
publication) and update the Datastream stream — otherwise the BigQuery targets have no
`farmerapp_raw.public_campaign*` to read. `docs/runbooks/datastream-cdc-setup.md`.

---

## What the merge broke, and the fixes

Five things, every one of them a branch not having run a surface it did not own. None was
fixed by relaxing an assertion, a budget or a rule.

| # | Break | Fix |
|---|---|---|
| 1 | `tests/test_migrations.py::test_0002_auth_tables` — the 0002 schema assertion did not know about `otp_challenge.request_ip` (added by 0040 for the SEC-021 per-IP velocity rule). | `request_ip` added to `OTP_COLUMNS` with the migration that introduced it named in a comment. |
| 2 | `tests/deploy/test_terraform_env.py::test_every_setting_is_documented` — 11 new settings (7 × `OTP_*` abuse and cost guards, 4 × `GRIEVANCE_*`) had no row in `docs/deploy/configuration.md`. | Five rows added to the "Auth and API edge" table with each default and what it does. The grievance officer's real name and contact are marked as what they are: a human gate before pilot. |
| 3 | `tests/authz/test_matrix.py` — 37 failures. The SEC-006 matrix is generated from `openapi.yaml`, so NF-013's three new staff endpoints appeared in it with no `RouteFixture`, and its collection check assumed every list is enveloped. | Fixtures added for `GET {id}/export`, `POST {id}/apply-correction` and `POST {id}/erase` (unknown id → 404 for every allowed role; the two writes carry a step-up token, or every role would 401 before reaching the authz decision). The collection check now walks a **bare JSON array** as well as `{"items": […]}` — `GET /v1/me/data-requests` and `.../retention-exceptions` are the only two endpoints that return one, and they were previously crashing the check rather than being inspected. That is strictly more coverage, not less. |
| 4 | `bandit` — 4 **medium** B608 findings, from SQL the security branch builds by interpolating identifiers: `farmerapp/privacy/export.py` (the NF-013 access export) and `farmerapp/retention/sweep.py` (the NF-012 sweep). The branch reported bandit clean; on the merged tree it fails the gate. | Not suppressed wholesale. Both sites interpolate **only** identifiers from a declarative module constant — `SECTIONS` and the `policy.py` retention classes, a closed set that no request value reaches — each through `_quote`, with the principal's id and the cutoff as bound parameters. That is the same case, and now carries the same per-line `# nosec B608` markers with a written justification, as `farmerapp/mlops/reembed.py`, which the repo already reviewed and annotated this way. The `[tool.bandit]` config is untouched: no rule is disabled globally. |
| 5 | Console design tokens. `design/tokens.json` is shared with the console (`scripts/tokens-to-css.mjs` → `app/tokens.css`), so NF-009 splitting `border` into `border.default` / `border.strong` would have left `--color-border` undefined the next time anyone rebuilt — an invisible break, since CSS drops an unknown variable silently. | `app/tokens.css` regenerated; Tailwind's `border` colour became a scale. `border-border` (143 uses) keeps the decorative hairline at **exactly its previous hex**, so nothing in the console changes appearance, and `border-border-strong` is available for control boundaries. The one raw `var(--color-border)` (the chart grid) now names `--color-border-default`, which is what a grid line is. |

The other predictions did not materialise: the console CSP needed no change for the new
analytics screens (Recharts' inline style *attributes* are covered by the documented
`style-src 'unsafe-inline'` relaxation, and nothing new loads script or opens a socket), no
mobile golden needed re-recording, and the Terraform drift tests passed because the new
settings are app-side defaults rather than Cloud Run env.

---

## Checks

Run serially on a quiet database, one surface at a time, on the final tree.

| Surface | Result |
|---|---|
| `SKIP_AUDIT=1 make check-api` | **green** — ruff 664 files, `ruff format` clean, **mypy strict 663 source files / 0 errors**, `validate-rules` 21 rules, **pytest 5 198 passed + 2 serial, 10 skipped** (29m27s parallel + 1m09s serial), coverage gate ≥ 80 % met, `export_openapi.py --check` up to date, **bandit 0 high / 0 medium / 0 low**. |
| `make check-dbt` | **green** — replication allowlist **28 tables** (sources and fixtures agree), `dbt_run.py --self-test` 20 assertions, `dbt build --target ci`: 28 seeds, 22 tables, 43 views, **509 data tests**, **PASS 602 / WARN 0 / ERROR 0**. |
| `cd apps/console && npm run check` | **green** — eslint + the two repo-local lint scripts, `tsc --noEmit`, **402 vitest in 61 files**, `next build`. |
| `cd apps/console && npm run test:e2e` | **49/49 green at `--workers=2`.** At the default worker count one pre-existing race fails on this machine — see below. |
| `cd apps/mobile && ./tool/check.sh` | **green** — l10n complete in five languages, `dart format`, `flutter analyze` zero issues, workspace tooling 34, **core 725 (1 skipped), agent 259, farmer 210**. |
| `cd apps/mobile && APK_SIZE_CHECK=1 ./tool/check.sh` | **green** — **armeabi-v7a 17.01 MB, arm64-v8a 17.66 MB** against the 25 MB budget; release manifest verified (not debuggable, no backup, extraction rules, TLS only). |
| `cd infra && ./scripts/check.sh` | **green** — `fmt -check` clean, `validate` ×4, **`terraform test` 35 passed / 0 failed** (analytics 7, cost 5, db_budget 9, monitoring 6, run_job 4, run_service 4), tflint clean, **checkov 115 passed / 0 failed / 6 skipped**. |
| `make openapi` afterwards | no diff. |

### The one red: `inbox-admin.spec.ts` C71 under full parallelism

`C71: the officer adds an explanation to a flag about them` fails at the default worker count
and passes at `--workers=2`, at `--workers=1`, and with any five of the nine spec files.

It is **not this merge**. `git diff a3472bb..HEAD` shows the failing test, `FlagDetailView.tsx`,
`lib/hooks/flags.ts` and `lib/mock/flags.ts` are byte-identical to pre-merge `main`; the only
change to that spec file is the C103 audit-filters selector the security branch scoped. What
the merge did was add ten e2e tests (39 → 49), which pushes parallel load past the threshold on
this machine. `docs/prs/M7-security-privacy.md` recorded the same test as a pre-existing flake.

The mechanism, from the failure snapshot: the textarea holds the typed text but React's `body`
state is empty at submit, so the form's own `Required` validation fires and no comment is
posted. That is an interaction landing before the controlled input is live — a test-robustness
defect in the console e2e suite, not a product bug and not something to paper over with a
retry. **It is left failing rather than patched**, because a correct fix needs the console
owner to decide how these specs wait for interactivity. CI already runs `retries: 1`, so CI is
green today.

---

## Remaining human gates

Everything below is inherited from the two branches and from the analytics workstream; nothing
here was closed by this merge.

| Gate | Blocks | Where |
|---|---|---|
| Re-run the Datastream stream update after the Terraform apply | the `farmerapp_raw.public_campaign*` sources, so `mart_campaign_roi` | docs/runbooks/datastream-cdc-setup.md |
| Billing admin enables the Cloud Billing export (`billing_export_table`) and sets `billing_account` | the OPS-012 cost views, the daily anomaly watch, the NF-015 budget | docs/runbooks/cost-and-budget.md |
| Org owner points SCC at the `scc.findings` topic | OPS-013 SCC findings | the alert's own documentation |
| Firebase projects and `google-services.json` per flavour | Crashlytics, Performance, Remote Config, the OPS-002 crash-free number | docs/runbooks/bad-mobile-release-rollback.md |
| `roles/cloudtrace.agent` on the api / worker SAs | traces reaching Cloud Trace | docs/runbooks/observability.md |
| Play Console promotion and release signing; reading the first real CI run to confirm the 25 % short-class-name threshold matches R8's actual output | SEC-008 | docs/runbooks/mobile-security-scan.md |
| The privacy notice, consent copy, and the grievance officer's real name, e-mail and phone (`GRIEVANCE_OFFICER_*`) | NF-013 sign-off | docs/dpdp.md, TODO-LEGAL |
| DPAs with the SMS gateway, Razorpay and any e-mail provider; a DPIA before `ROAD_SNAPPER=google` | NF-011 | docs/dpdp.md |
| The annual breach-notification drill (recorded in the rehearsal log) and the external penetration test before pilot | SPEC 11.4 | docs/runbooks/suspected-data-breach.md |
| Re-dating the three licence exceptions each quarter | SEC-007 | docs/licence-policy.md |
| The three reference devices and a device-C pass per release | NF-001 | docs/device-matrix.md |
| Native-speaker review per language (the CSV pack is ready) | NF-008 | `tool/translations.dart export` |
| TalkBack walk and an outdoor Sunlight pass | NF-009 | docs/device-matrix.md §5 |
| Product owner's decision on the pilot Cloud SQL shape | NF-015 pilot budget | docs/cost-model.md |
| Agronomist-labelled held-out set uploaded to the corpus bucket | DX-011 real numbers | docs/prs/M7-analytics-finish.md |
| Vertex AI training image and the monthly pipeline schedule | DX-012 (the one M7 row still `in-progress`) | docs/prs/M7-farmer-p1-api.md |
| AN-004 working definitions (churn window, acreage and spend bands) confirmed by the owner | AN-004 sign-off | docs/prs/M7-analytics-finish.md |

## Follow-ups (engineering, not gates)

* **Console e2e interactivity**, as above — the C71 race. The suite is green at `--workers=2`.
* **SEC-022 leftovers for the analytics owner**: `GET /v1/analytics/farmers?sort` and `?cursor`
  are still the only two entries in `ALLOWED_UNBOUNDED_QUERY`. Bounding `sort` with a `Literal`
  and `cursor` with a length empties that dict the way `PENDING_REPLICATION` was emptied here.
* **Console control contrast.** NF-009 raised the control boundary to 5.51:1 in the shared
  tokens, and `border-border-strong` now exists in the console, but the console's ~30 text
  fields and outlined controls still use the decorative `border-border` — the same 1.35:1 the
  mobile apps just fixed. Moving them is a visual change across every form and wants a design
  review, so it is deliberately not in this merge.
* **`llm_call_log` / `otp_challenge` replication** would let `v_cost_daily_by_tenant` carry
  rupees rather than alert thresholds (an AN-014 allowlist decision).
* **Agent-app accessibility walk**: the 48 dp and label gates should cover it even though
  NF-010 does not apply to officers.

# M7 API integration: the three parallel branches on one main

Requirements touched: FM-007, FM-008, FM-009, DX-011, DX-012, DX-013, AN-006, AN-007 (the
farmer P1 half), plus the merge wiring the field P1 and growth halves asked for.

PR title: `feat(M7): integrate calendar, weather, outbreaks and ML operations; merge migration
heads, widen the connection budget and document new settings`

Three M7 API branches were cut from the same base and developed concurrently:

| Branch | Merge commit | What it brought |
|---|---|---|
| `feat/M7-field-p1-api` | `c6b421e` | push + inbox (FA-007), track processing and gap reasons (VV-006, VV-008), travel claims (FA-023), beat plans (FA-018), my performance (FA-024), demo plots (FA-026), farmer meetings (FA-027) |
| `feat/M7-growth-api` | `3c9a7ff` | campaigns and ROI (WC-008, AN-008), targets and incentives (WC-009), exports and scheduled reports (WC-013, ST-008), weekly owner PDF (AN-015), stock alerts (ST-004) |
| `feat/M7-farmer-p1-api` | `e43e86f` | crop calendar (FM-007), weather and spray windows (FM-008), outbreak alerts (FM-009, DX-013), diagnosis quality and evaluations (DX-011, AN-007), model releases and re-embedding (DX-012), crop health (AN-006) |

## 1. The merge (`merge(M7): feat/M7-farmer-p1-api`)

Twelve files conflicted, every one of them a shared registry the three branches appended to.
All were resolved as the **union of both sides**, never by taking a side:

| File | Resolution |
|---|---|
| `api/app.py` | both imports, both router blocks: `advisory` and `mlops` next to `notifications`, `meetings`, the field P1 routers and the growth routers. `mlops` stays registered before `diagnosis` so `/v1/diagnoses/quality` and `/evaluations` are not read as diagnosis ids. |
| `db/models/__init__.py` | every model imported and exported: `CropPlotTask`, `CropTaskTemplate`, `OutbreakAlert`, `CorpusEmbedding`, `EncoderActivation`, `EvaluationRun`, `ModelRelease` alongside `FarmerMeeting`, `MeetingAttendance`, `PushToken`, `ExportJob` …; `install_feed_listener()` kept. |
| `jobs/cli.py` | every command on one `cli`: the field P1 jobs (`deliver-notifications`, `process-tracks`, `generate-beat-plans`), the farmer P1 jobs (`calendar-reminders`, `outbreak-detection`, `diagnosis-evaluate`, `export-training-set`, `register-model-candidate`, `reembed-corpus`, `activate-encoder`) and the growth jobs, whose module import moved to the bottom of the file so it registers after all of them. |
| `notifications/models.py` | `NotificationKind` is the union: the FA-007 / field P1 kinds **and** `crop_task_reminder`, `outbreak_alert`, `diagnosis_eval_drop`, `model_release_candidate`. `DeliveryStatus` / `PushPlatform` kept. |
| `sync/models.py`, `sync/schemas.py`, `sync/service.py` | `SYNC_ENTITIES` and the `Entity` literal carry the eight field P1 entities **and** `crop_plot_task`; `CONFLICT_RULES` gets both `field_p1.STRATEGIES` and `crop_plot_task: merge_fields`; `_create` / `_update` dispatch to both (`crop_plot_task` create is `unsupported_action`); the feed has both sets of clauses. `tests/sync/test_m2_rules.py` derives its set from `SYNC_ENTITIES`, so the coverage assertion follows the entity list rather than either side's number. |
| `tenants/settings.py` | the docstring table, `SETTINGS_KEYS`, the model classes, the `TenantSettings` fields and `__all__` are the union: `campaigns`, `stock_alerts`, `reports`, `accounting` **and** `quiet_hours`, `calendar_reminders`, `weather`, `outbreak`, `diagnosis_evaluation`. |
| `tests/admin/test_step_up.py` | the step-up route set is the union: the growth four (`POST /v1/exports`, `POST /v1/report-schedules`, `PATCH /v1/report-schedules/{id}`, `POST /v1/incentives/close`) **and** `POST /v1/models/releases/{id}/decision`. |
| `tests/authz/test_matrix.py` | both fixture blocks kept, so every new route of both branches has a row. |
| `openapi.yaml` | not hand-merged: one side taken, then regenerated with `make openapi` once the code compiled. |
| `docs/progress.md` | rows merged per requirement id, keeping the further-along status of each. |

**Alembic**: `0032_farmer_p1` (branch label `farmer_p1`, on `0029`) and the existing head
`0034` were rejoined by **`0035_merge_farmer_p1`** (revision `0035`, `down_revision =
("0034", "0032")`, no DDL — every branch is expand-only and they touch disjoint tables).
`alembic heads` reports one head; a full `upgrade head` -> `downgrade base` -> `upgrade head`
round trip on a scratch database is clean.

## 2. Connection budget (docs/deploy/configuration.md)

With the farmer P1 jobs there are **17 Cloud Run jobs** in every environment, and stg sat at
79 of an 80 ceiling — one job from failing `terraform plan`. The pools stay at the validated
minimum (`pool_size + max_overflow >= 2`: a tenant-bound session plus the PII key load need
both connections), so the headroom came from the `max_connections` flag:

| env | max_connections | total | 80% ceiling | more jobs that fit |
|---|---|---|---|---|
| dev | 100 (unchanged) | 67 | 80 | 6 |
| stg | 100 -> **125** | 79 | **100** | 10 |
| prd | 200 -> **250** | 154 | **200** | 23 |

Every environment now has room for at least four more jobs. **HUMAN GATE**: the flag change
restarts the Cloud SQL instance (in prd the primary *and* the read replica, which carries the
same flag), so the stg and prd applies are human-only and belong in a maintenance window.
Nothing else moves — the rendered env of api / worker / jobs is unchanged and no service is
redeployed. The `module.db_budget` precondition is untouched; its `terraform test` suite grew
from 5 to 9 runs (the real prd shape, "four more jobs still fit" for dev / stg / prd, and the
old stg shape failing) and `tests/deploy/test_terraform_env.py` still recomputes each env from
its tfvars and checks the table.

## 3. `.env.example`

Twenty-five settings `settings.py` reads were missing. Added with comments, grouped:
`CORPUS_BUCKET` (next to the other buckets); `FLAG_SUMMARY_LLM` / `_MODEL` / `_MAX_TOKENS`
(VA-004); `WEATHER_PROVIDER` / `WEATHER_BASE_URL` / `WEATHER_TIMEOUT_S` /
`WEATHER_CACHE_TTL_SECONDS` (FM-008, with the grid-cell privacy note);
`DIAGNOSIS_EVAL_MANIFEST` (DX-011, with the human gate); `PUSH_PROVIDER`, `FCM_PROJECT`,
`NOTIFY_MAX_ATTEMPTS`, `ROAD_SNAPPER`, `GOOGLE_MAPS_API_KEY`, `MEETING_QR_TTL_SECONDS`
(field P1); and the nine `EMAIL_*` settings (WC-013 / AN-015 / ST-008). The note that the
crop calendar, outbreak rule and evaluation threshold are **tenant** settings, not env, is in
the same block. A check against `Settings.model_fields` now finds nothing missing.

## 4. WC-001 owner home crop-health card (AN-006)

The card was rendering an empty state with `notes.crop_health_alerts = "pending_an006"`.
`analytics/owner_home.crop_health_alerts()` now reads the tenant's active `outbreak_alert`
rows (`advisory.outbreaks.active_alerts`, newest week first, at most five) and returns each as
the fields of `OutbreakAlertOut` plus a composed `title` and `problem`.

**No console change was needed**: `OwnerHomeView.tsx` already renders the list when it is
non-empty, reading `a.title ?? a.problem` out of `Array<Record<string, unknown>>`, and the
console's own mock still returns `[]` so the e2e empty-state assertion stays valid. AN-014
holds: district, crop, problem, week and counts only — no farm location and no farmer
identity. The `pending_an006` note is gone. Test:
`tests/advisory/test_outbreaks.py::test_owner_home_crop_health_card_lists_the_active_alerts`.

## What remains

* **Console** — the crop-health *map* screen (AN-006), the C62 quality dashboard (AN-007), the
  model-release screen (DX-012), C80-C82 campaigns (WC-008 / AN-008), C90 targets and
  incentives (WC-009), C100 exports (WC-013). The owner-home card above is the only console
  surface the API could fill without console work.
* **Mobile** — the farmer app calendar (FM-007), weather (FM-008) and alert (FM-009) screens;
  the field app screens for the field P1 features; the new notification kinds need ARB entries
  (`notification.<kind>.title|body`) in both apps.
* **Human gates**, unchanged from the branch PR docs: the stg / prd `terraform apply` of the
  `max_connections` flag (above); TODO-LEGAL on the DPDP basis for FM-009 farmer advisories;
  agronomist and translator review of the seeded calendars (FM-007); the agronomist-labelled
  held-out set at `gs://<corpus>/eval/heldout/manifest.csv` (DX-011); the `ml/ondevice`
  training image and the Vertex AI pipeline wiring (DX-012); the Open-Meteo licence for
  commercial use (FM-008); the Firebase project for `PUSH_PROVIDER=fcm`; an email provider for
  `EMAIL_PROVIDER`.
* **Follow-ups**: SMS / WhatsApp calendar reminders for farmers without an app login; a
  log-based monitoring policy on `diagnosis_eval_accuracy_drop` and `outbreak_alert_raised`
  (the log events exist, `modules/monitoring` has no policy yet); wiring the console dashboards
  to the dbt views.

## Checks

One fix was needed to get the merged tree green: bandit flags the two re-embedding statements
in `farmerapp/mlops/reembed.py` (B608, Medium / Low confidence) because they concatenate the
module-level `_LIVE` literal. Nothing user-supplied reaches the SQL — tenant, encoder name and
version are bound parameters — so each carries a `# nosec B608` marker and the reason is on
`_LIVE` itself.

`SKIP_AUDIT=1 make check-api` (ruff, ruff format, mypy strict, rule validation, the full
pytest suite in two phases: **4,622 passed + 2 serial, 2 skipped**, coverage >= 80%,
`export_openapi.py --check`, bandit) and
`cd infra && ./scripts/check.sh` (fmt, validate, `terraform test` in `db_budget`, `run_job`
and `run_service`, tflint, checkov) both pass. `make openapi` leaves `apps/api/openapi.yaml`
unchanged afterwards.

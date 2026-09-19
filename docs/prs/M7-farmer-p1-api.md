# M7 — crop calendar, weather, outbreak alerts, diagnosis ML operations (API half)

Branch `feat/M7-farmer-p1-api` (from main `c78a532`). Requirements: FM-007, FM-008, FM-009
(SPEC 2.4), DX-011, DX-012, DX-013 (SPEC 3), AN-006, AN-007 (SPEC 5.1). Migration
`0032_farmer_p1` (down_revision `0029`, branch label `farmer_p1`; the parallel M7 branches are
`0030 field_p1` and `0031 growth`, the parent merges the heads).

## Contracts for mobile and the console

### FM-007 crop calendar

| Method | Path | Roles | Notes |
|---|---|---|---|
| GET | `/v1/me/calendar` | farmer | every active crop plot with its tasks; `today` is the IST date |
| GET | `/v1/farmers/{id}/calendar?crop_plot_id=` | staff in SPEC 2.6 scope + the farmer | same body |
| PATCH | `/v1/calendar/tasks/{id}` | farmer, field officer | `{status?: pending\|done, reminder_enabled?: bool, version?: int}`; 409 `version_conflict` |
| GET | `/v1/calendar/templates?crop_id=&include_inactive=` | agronomist, owner, director, tenant admin, cluster head, store manager, field officer | |
| POST | `/v1/calendar/templates` | agronomist | 201; 409 `template_exists`; an `en` title is required |
| PATCH / DELETE | `/v1/calendar/templates/{id}` | agronomist | DELETE is a soft delete (204) |

```jsonc
// GET /v1/me/calendar
{"farmer_id": "…", "today": "2026-09-21", "plots": [{
  "crop_plot_id": "…", "farm_id": "…", "crop_id": "…", "crop_code": "paddy",
  "crop_names": {"en": "Paddy", "te": "వరి"}, "season": "kharif", "sowing_date": "2026-07-01",
  "tasks": [{
    "id": "…", "task_key": "paddy.top_dress_1", "task_type": "fertilise", "stage": "vegetative",
    "due_date": "2026-07-22", "end_date": "2026-07-24",
    "titles": {"en": "First top dressing", "te": "…", "hi": "…", "kn": "…", "mr": "…"},
    "instructions": {"en": "Apply the first split of nitrogen …", "te": "…"},
    "product_category": "fertiliser", "sort_order": 40, "status": "pending", "done_at": null,
    "reminder_enabled": true, "reminded_at": null, "basis_sowing_date": "2026-07-01", "version": 1
  }]}]}
```

* **Templates** (`crop_task_template`, agronomist-maintained): task key, type (`sow`,
  `irrigate`, `fertilise`, `spray`, `harvest`), day offset from sowing, duration, stage,
  localized titles and one-line instructions per language, optional `product_category` (a
  category, never a SKU — DX-007 keeps product advice with the diagnosis engine), `season`
  (NULL = every season; a season row overrides the season-less one with the same key).
  Seeded for the six pilot crops (`farmerapp/advisory/templates.py`).
* **Generation**: `due_date = sowing_date + day_offset`, `end_date = due_date + duration - 1`.
  Materialised on read, after a crop plot write and by the daily job. A change of the sowing
  date, the crop or the crop's templates updates the **pending** tasks in place (ids stay stable
  for the app, `reminder_enabled` survives, `reminded_at` resets when the date moves), removes
  tasks whose template is gone and adds new ones; **done tasks are never touched**. Deleting the
  plot soft-deletes its pending tasks.
* **Reminders**: `calendar-reminders` (07:00 IST) writes one `crop_task_reminder` notification
  per due task to the farmer's login (`title_key` / `body_key` +
  `data{task_id, crop_plot_id, farmer_id, task_key, task_type, due_date}`), once
  (`reminded_at`), never inside the tenant's `quiet_hours` and not before
  `calendar_reminders.local_time`. Farmers without an app login are counted (`no_login`), not
  messaged — SMS reminders are a follow-up.
* **Offline**: sync entity `crop_plot_task` (feed + `update` ops with `status` /
  `reminder_enabled`; `merge_fields`, every other field is server-owned, `create` / `delete`
  are `unsupported_action`).

### FM-008 weather and spray windows

`GET /v1/farms/{id}/weather` (staff in scope + the farmer):

```jsonc
{"farm_id": "…", "latitude": 18.0, "longitude": 79.6, "location_source": "farm",
 "provider": "open_meteo", "fetched_at": "…", "cached": true, "timezone": "Asia/Kolkata",
 "daily": [{"date": "2026-09-21", "temperature_max_c": 31.2, "temperature_min_c": 22.9,
            "precipitation_mm": 3.4, "precipitation_probability_pct": 70, "wind_max_kmh": 18.5,
            "weather_code": 61}],                       // 7 days
 "hourly": [{"time": "2026-09-21T06:00:00+05:30", "temperature_c": 24.1,
             "relative_humidity_pct": 88, "precipitation_probability_pct": 20,
             "precipitation_mm": 0.0, "wind_kmh": 6.5, "wind_gust_kmh": 12.0}],  // next 72 h
 "spray": {"windows": [{"start": "…", "end": "…", "advice": "good", "reasons": [],
                        "cautions": ["heat"], "max_precipitation_probability_pct": 10,
                        "precipitation_mm": 0.0, "max_wind_kmh": 8.0, "max_temperature_c": 37.0,
                        "min_relative_humidity_pct": 25, "max_relative_humidity_pct": 40}],
           "avoided": [{"advice": "avoid", "reasons": ["rain_likely"], …}],
           "thresholds": {"max_rain_probability_pct": 30, "max_rain_mm": 0.5,
                          "max_wind_kmh": 15, "caution_max_temperature_c": 35,
                          "caution_max_humidity_pct": 90, "caution_min_humidity_pct": 30}}}
```

* `spray.windows` holds only the **good** 3-hour windows (aligned on IST 00, 03, … 21, from the
  current one to +72 h): a window whose rain probability, rain or wind reaches a threshold is
  hidden and listed in `avoided` with its `reasons` (`rain_likely`, `rain`, `wind_high`).
  Cautions (`heat`, `humidity_high`, `humidity_low`) never hide a window. Reason and caution
  codes are i18n keys for the app; nothing is translated server-side.
* **Data residency / privacy**: the server alone calls Open-Meteo (free, no key), and sends only
  the coordinates of the 0.1-degree grid cell the farm falls in — no polygon, farmer, id or
  header. Forecasts are cached per cell for `WEATHER_CACHE_TTL_SECONDS` (3 h) per instance, so a
  village costs one call. The port (`WeatherProvider`) has a fake for tests and offline dev
  (`WEATHER_PROVIDER`; Terraform never sets it, so deployments use Open-Meteo).
* Location: the farm centroid, else its farmer's village (`location_source`). Provider outage:
  503 `weather_unavailable`.

### FM-009 alerts and AN-006 crop health

| Method | Path | Roles |
|---|---|---|
| GET | `/v1/alerts?district=&crop_id=` | farmer (their district, `grows_crop` per alert), staff in the tenant |
| GET | `/v1/analytics/crop-health?weeks=&district=&crop_id=` | owner, director, tenant admin, auditor, agronomist |

`/v1/alerts` returns the active alerts (this week and the previous `outbreak.active_weeks`) with
district, crop (code + names), problem (code, type, names), `week_start`, `iso_year`, `iso_week`,
`case_count`, `farmers_affected`, `baseline_mean`. `/v1/analytics/crop-health` returns one cell
per district x crop x problem x ISO week with `confirmed_cases`, `farmers_affected`,
`prior_mean`, `outbreak` and the `alert_id` when one was raised — **district level only**, no
farm location or farmer identity (AN-014).

### DX-011 / AN-007 quality and evaluations

| Method | Path | Roles |
|---|---|---|
| GET | `/v1/diagnoses/quality?days=30` | owner, director, tenant admin, auditor, agronomist |
| GET | `/v1/diagnoses/evaluations?limit=` and `/v1/diagnoses/evaluations/{id}` | same |

`quality` replaces the console's client-side computation (C62): `requests`,
`answered_by_corpus` / `corpus_share`, `escalated` / `escalation_rate`, `llm_share`,
`by_source`, `by_status`, `review{sla_hours, reviewed, reviewed_within_sla, sla_rate,
avg_review_hours, median_review_hours, open_queue, open_overdue}`, `top_unknowns[{crop_id,
crop_code, reason, cases}]` and `latest_evaluation`. An evaluation run carries `cases`,
`top1_accuracy`, `corpus_answer_share`, `escalation_rate`, `hallucinated_out_of_scope`,
`top1_delta_points`, `alerted` and (in the detail) `totals`, `per_crop`, `per_problem`.

### DX-012 model releases

| Method | Path | Roles |
|---|---|---|
| GET | `/v1/models/on-device/current` | every signed-in role (both apps) |
| GET | `/v1/models/releases?status=` and `/v1/models/releases/{id}` | agronomist, owner, director, tenant admin |
| POST | `/v1/models/releases/{id}/decision` | agronomist, owner (**step-up**, audited) |

`current` answers `{release_id, model_name, model_version, sha256, size_bytes, url,
url_expires_at, labels, thresholds, input, output, approved_at}` — a 15-minute signed URL; the
app verifies the sha256 before using the file, and 404 `no_approved_model` simply means "keep the
bundled model". `decision` takes `{"decision": "approve"|"reject"|"retire", "note": "…"}`;
approving a candidate without evaluation numbers is 409 `evaluation_missing`, a wrong transition
409 `invalid_transition`.

## What changed

* **Migration `0032_farmer_p1`** (expand-only, every table under RLS): `crop_task_template`,
  `crop_plot_task`, `outbreak_alert`, `evaluation_run`, `model_release`, `corpus_embedding`,
  `encoder_activation` (append-only).
* **`farmerapp/advisory/`** — templates + seed, calendar generation / reminders, the weather
  port and spray advice, outbreak detection and the alert / crop-health reads, the routes and the
  `crop_plot_task` sync ops. Hook: `farmers.service.update_crop_plot` / `delete_crop_plot`
  regenerate an existing calendar.
* **`farmerapp/mlops/`** — the DX-011 evaluation (now shared with `ml/eval/evaluate.py`, which
  became its CLI), AN-007 quality, DX-012 releases, training export and re-embedding, and their
  routes. `diagnosis/knn.py` falls back to staged vectors while an encoder rollout is in flight.
* **Tenant settings** (additive, PATCH-able): `quiet_hours`, `calendar_reminders`, `weather`,
  `outbreak`, `diagnosis_evaluation`.
* **Deployment settings**: `WEATHER_PROVIDER` / `WEATHER_BASE_URL` / `WEATHER_TIMEOUT_S` /
  `WEATHER_CACHE_TTL_SECONDS`, `CORPUS_BUCKET`, `DIAGNOSIS_EVAL_MANIFEST`
  (docs/deploy/configuration.md).
* **Notifications**: `crop_task_reminder`, `outbreak_alert`, `diagnosis_eval_drop`,
  `model_release_candidate` (i18n keys for the apps and the console).
* **ml/**: `ml/ondevice/ondevice/field.py` + `finetune.py` (monthly fine-tune on the exported
  field images; `export.py` gained `--model-version` / `--source` / `--training-manifest-uri`),
  `ml/pipelines/` (KFP v2 pipelines as code + compiled YAML: `ondevice-monthly-finetune`,
  `encoder-reembed`), README updates in `ml/eval`, `ml/embed` (switch procedure) and
  `ml/ondevice`.
* **infra/**: `flag.created` topic (push subscription + DLQ come from the module), Cloud
  Scheduler entries for `flags-summarise`, `rules-quality-report`, `calendar-reminders`,
  `outbreak-detection`, `diagnosis-evaluate` and `export-training-set`, `FLAG_SUMMARY_LLM`
  (`var.flag_summary_llm`: off in dev, claude in stg / prd) on worker and jobs,
  `ANTHROPIC_API_KEY` + `CORPUS_BUCKET` on jobs, the api reading the corpus bucket (signed model
  URLs). The connection budget moved to 17 jobs (dev 67/80, stg 79/80, prd 154/160) — **stg has
  room for one more job only**; the next one needs a bigger `sql_max_connections` or smaller
  pools.

## Assumptions and gates for review

* **TODO-LEGAL (FM-009 / DPDP)**: outbreak advisories are sent to farmers of the district
  growing the crop **without marketing consent**, as crop-protection advisories tied to the
  service the farmer registered for (not promotion; no product is named in the notification).
  A tenant can switch them off (`outbreak.farmer_alerts_enabled`). Legal to confirm the basis
  and the copy before the pilot.
* **TODO-HUMAN (FM-007)**: the seeded calendars are from the generally published PJTSAU / ICAR
  guides; the tenant agronomist reviews offsets and wording, and a translator the non-English
  texts, through `/v1/calendar/templates`.
* **TODO-HUMAN (DX-011)**: the held-out, agronomist-labelled field set must be uploaded to
  `gs://<corpus>/eval/heldout/manifest.csv`; until then the nightly job records a failed run
  (real field images are never committed).
* **TODO-HUMAN (DX-012)**: building the `ml/ondevice` training image and wiring the Vertex AI
  pipelines / schedule (`ml/pipelines/README.md`); the approval gate itself is in the API.
* **TODO-HUMAN (FM-008)**: Open-Meteo's free tier has no SLA and its terms are
  non-commercial-ish for heavy use — confirm the licence or move to a paid provider before the
  pilot scales (the port makes it a one-adapter change).
* **Follow-ups**: WC-001 owner home still shows an empty crop-health card — it can read
  `outbreak_alert` now (`farmerapp/analytics/owner_home.py`, left to the analytics loop);
  SMS / WhatsApp reminders for farmers without an app login; a log-based
  monitoring alert on `diagnosis_eval_accuracy_drop` and `outbreak_alert_raised` (the log events
  exist, `modules/monitoring` has no policy yet); console screens (C62 quality dashboard, crop
  health map, model releases) and the farmer app screens (calendar, weather, alerts).

## Tests

`tests/advisory/test_calendar.py` (22: seeded templates, generation, regeneration on sowing
date / crop / template change with done tasks kept, task updates and scope, template CRUD,
reminders incl. quiet hours and the once-only rule, sync feed + ops),
`tests/advisory/test_weather.py` (16: spray window rules on fixture forecasts, thresholds from
settings, Open-Meteo parsing and the privacy of the call, cache per grid cell and TTL, the
endpoint incl. 503 and scope), `tests/advisory/test_outbreaks.py` (13: the rule table, fires on
seeded cluster data, quiet on a baseline, notification audience and idempotency, the alerts and
crop-health APIs), `tests/mlops/test_evaluation.py` (6: run recorded, drop alert, failed run,
AN-007 API), `tests/mlops/test_releases.py` (4), `tests/mlops/test_training_and_reembed.py`
(4: export shape and split parity with `ml/ondevice`, staging, kNN during a rollout, the atomic
flip and its rollback), `ml/ondevice/tests/test_field.py` (3), authz matrix rows for the ten new
routes. OpenAPI regenerated.

# M7 field P1 — API half (FA-007, VV-006, VV-008, FA-023, FA-018, FA-024, FA-026, FA-027)

Branch `feat/M7-field-p1-api`. Alembic `0030_field_p1` (down_revision `0028`, branch label
`field_p1`; the parent merges the M7 heads). Contracts below are for the mobile agent (officer
app A-screens, farmer app F-screens) and the console (day replay gap reasons, claims).

## What changed

| ID | API |
|---|---|
| FA-007 | Push tokens, `PushSender` port (FCM HTTP v1 with the runtime service account's OAuth token — no server key; `FakePushSender`; `off`), delivery of `notification` rows on the existing `notify.send` topic + the `deliver-notifications` sweeper job, retries with back-off, delivered / failed / no_device states, deep-link data payloads, inbox endpoints, notifications as a sync entity. New notification rows for the visit confirmation prompt (FA-016 `app_push`, to the farmer) and credit approval decisions (ST-007, to the requesting officer). |
| VV-006 | `duty/processing.py`: km through a `RoadSnapper` port (`FilterSnapper` = haversine + accuracy / speed / jitter filter, the default; `GoogleRoadsSnapper` = Roads API `snapToRoads?interpolate=true`, `ROAD_SNAPPER=google`, off by default), stops (>= 5 min within 100 m), gaps (> 30 min without a kept point while on duty) stored per duty session (`duty_session.km`, `km_raw`, `km_source`, `processed_at`, `stops`; `track_gap`). Runs at duty end (filter only, no network in the request) and in the `process-tracks` job (re-processes with the configured snapper). |
| VV-008 | `GET /v1/me/day?date=` (the console day replay of the caller + the day's TA) and `POST /v1/me/gaps/{gap_id}/reason`; the console replay payload's gaps gain `id` and `note` and carry the stored `reason`. |
| FA-023 | Daily km = processed km of the officer's ended sessions that started that IST day, capped at `ta_daily_km_cap` (new tenant setting, default 150); TA = capped km x `ta_rate_per_km_paise`. Expense claims with receipt photo, cluster head approval, monthly statement; `TravelClaimSubmitted` event with the computed km (VA-E07 is wired by the rules agent). |
| FA-018 | Beat plan per officer and IST day, generated at 06:00 IST (`generate-beat-plans`) or on first read of today / tomorrow; reasons: follow-up due, pest alert in the district, credit due within 7 days, demo plot stage due; capped at `beat_daily_target` (default 10); `GET/PUT /v1/me/beat`; sync entity. |
| FA-024 | `GET /v1/me/performance?from=&to=` computed by the console's own `officer_profile` (so equal by construction; asserted in `tests/performance/`); `incentive_earned_paise` from an `IncentivePort` (null until WC-009). The console officer profile gains `sales_net_paise` / `sales_orders`. |
| FA-026 | Demo plots with lifecycle `created -> active -> harvested -> reported`, stage observations with photos (upload purpose `demo_plot`), yield demo vs farmer practice; sync entities. |
| FA-027 | Farmer meetings geofenced at the village meeting point (evaluated like a `meeting` visit, VV-003); attendance by farmer OTP (purpose `meeting_attendance`) or the farmer app's signed QR (`GET /v1/me/attendance-qr`); attendance list linked to farmers; sync entities. |

## Endpoints (all under `/v1`; `x-roles` in `openapi.yaml`)

| Route | Roles | Body / query -> response |
|---|---|---|
| `POST /devices/me/push-token` | every role | `{token, platform: android\|ios\|web, device_id?, app_version?}` -> `PushTokenOut {id, platform, device_id, token_suffix, last_registered_at, active}`. The device id defaults to the access token's device (or `X-Device-Id`). Call after login and on every FCM token refresh. |
| `POST /devices/me/push-token/remove` | every role | `{token}` -> `{removed}` (on logout). |
| `GET /notifications` | every role | `?cursor&limit&unread_only` -> `{items: NotificationOut[], next_cursor, unread}` newest first. |
| `POST /notifications/{id}/read` | every role (own rows; else 404) | -> `NotificationOut` |
| `POST /notifications/read-all` | every role | -> `{marked}` |
| `GET /me/day?date=YYYY-MM-DD` | field officer, cluster head | -> `MeDayOut {date, officer_id, duty_sessions[], km, track, stops[], gaps[{id, start, end, duration_s, duty_session_id, reason, note}], visits[], timeline[], travel: TravelDayOut}` |
| `POST /me/gaps/{gap_id}/reason` | field officer, cluster head | `{reason: network\|personal_break\|vehicle\|other, note?}` -> `GapOutRow`. 404 for an unknown / someone else's gap. |
| `POST /travel/claims` | field officer, cluster head | `{id?, claim_date, type: fuel\|bus\|other, amount_paise, receipt_uri, note?}` -> 201 `TravelClaimOut` (`km_computed`, `status: submitted`). 422 `claim_date_invalid` (future or > 90 days), `invalid_blob`. Idempotency-Key honoured. |
| `GET /travel/claims` | + owner, director, tenant admin, auditor, accountant | `?status&officer_id&cursor` (scoped: own / own cluster / tenant) |
| `GET /travel/claims/{id}` | same | |
| `POST /travel/claims/{id}/approve\|reject` | cluster head (own cluster), owner, director, tenant admin | `{note?}`; 409 `claim_not_pending`; 403 on one's own claim. |
| `GET /travel/statement?month=YYYY-MM&officer_id=` | field officer, cluster head (default: self), owner, director, tenant admin, auditor, accountant (`officer_id` required: 422 `officer_required`) | `{days: TravelDayOut[], km_total, km_capped_total, ta_total_paise, claims[], claims_*_paise, payable_paise}` |
| `GET /me/beat?date=` | field officer | `BeatPlanOut {id, plan_date, status: generated\|edited, target, items[{id, kind: farmer\|village, farmer_id, farmer_name, village_id, village_name, reasons[{code, detail}], priority, source: system\|officer, note}], villages[], version}`; 404 `beat_plan_not_found` for a day other than today / tomorrow without a plan. |
| `PUT /me/beat?date=` | field officer | `{items: [{id} \| {kind: farmer, farmer_id} \| {kind: village, village_id}, note?], version?}` — the whole ordered list (reorder = order, remove = omit, add = no id). 422 `beat_item_unknown`, 409 `version_conflict`. |
| `GET /me/performance?from=&to=` | field officer | `PerformanceOut {from, to, duty_days, visits, verified_visits, verified_visits_per_day, unique_farmers_reached, farmers_added, confirmation_rate, time_on_farm_s, conversion_rate, sales_net_paise, sales_orders, collections_paise, km_per_day, rank, incentive_earned_paise (null)}` |
| `POST /demo-plots` | field officer | `{id?, farmer_id, crop_plot_id, baseline: farmer_practice\|comparison_plot, comparison_crop_plot_id?, product_id?, treatment}` -> 201 `DemoPlotOut` |
| `GET /demo-plots`, `GET /demo-plots/{id}` | field officer (own), cluster head, owner, director, tenant admin, auditor, agronomist | detail has `observations[]`; `yield_gain_pct` |
| `POST /demo-plots/{id}/observations` | field officer (own demo) | `{id?, stage: sown\|vegetative\|flowering\|fruiting\|maturity\|harvest, side: demo\|practice\|both, observed_at, note?, photo_uris[] (upload purpose demo_plot)}` |
| `POST /demo-plots/{id}/transition` | field officer | `{to: active\|reported}`; 409 `demo_plot_transition_invalid` |
| `POST /demo-plots/{id}/yield` | field officer | `{demo_yield_kg_per_acre, practice_yield_kg_per_acre?, harvested_at?, note?}` -> status `harvested` |
| `POST /meetings` | field officer | `{id?, village_id, topic, held_at, checkin_point {lat, lon, accuracy_m}}` -> 201 `MeetingOut` (`geofence_result: meeting_point`); 422 `outside_geofence` with `distance_m`, `target`, `radius_m` (as a visit check-in). |
| `GET /meetings`, `GET /meetings/{id}` | field officer, cluster head, owner, director, tenant admin, auditor | detail: `attendance[{farmer_id, farmer_name, method, recorded_at}]` |
| `POST /meetings/{id}/attendance/otp` | field officer | `{farmer_id}` -> `{phone_masked, expires_in, resend_after, resends_left}` |
| `POST /meetings/{id}/attendance` | field officer | `{id?, method: otp, farmer_id, code}` or `{id?, method: qr, token, recorded_at?}` -> 201 `AttendanceOut`; 401 `otp_invalid`, 422 `attendance_token_invalid`, 409 `meeting_closed`. A farmer attends once (a repeat returns the first row). |
| `POST /meetings/{id}/close` | field officer | -> `MeetingDetailOut` |
| `GET /me/attendance-qr` | farmer | `{token, farmer_id, expires_at}` (HS256, `typ meeting_attendance`, 5 min, `MEETING_QR_TTL_SECONDS`); show as a QR, refresh before expiry. |

## Push payload (FCM data message) and deep links

Every push carries string values only: the row's `data` ids plus `notification_id`, `kind`,
`title_key`, `body_key` and `route`. Android shows `title_loc_key` / `body_loc_key` (the app's
i18n keys; no text from the server). `route` by kind:

| kind | route | data |
|---|---|---|
| `visit_confirm_request` (farmer app) | `/visits/{visit_id}/confirm` | `visit_id, confirmation_id, officer_id, token, expires_at` (post `token` to `/v1/visits/{id}/farmer-confirm`) |
| `diagnosis_ready`, `diagnosis_reviewed`, `diagnosis_expert_requested` | `/diagnoses/{diagnosis_id}` | |
| `order_status` | `/orders/{order_id}` | `status`, `store_id` |
| `credit_approval_decided` | `/credit-approvals/{approval_id}` | `status`, `order_id`, `farmer_id`; body key `notification.credit_approval_decided.body.<approved\|rejected>` |
| `flag_assigned`, `flag_escalated` | `/flags/{flag_id}` | |
| `duty_auto_ended` | `/duty` | `duty_session_id, end_reason, end_at` |
| `travel_claim_submitted` (cluster head) / `travel_claim_decided` (officer) | `/travel/claims/{claim_id}` | body key `.body.<approved\|rejected>` for decided |
| `beat_plan_ready` | `/beat/{date}` | `beat_plan_id, items` |
| anything else | `/inbox` | |

New i18n keys the apps need: `notification.<kind>.title` / `.body` for
`visit_confirm_request`, `credit_approval_decided` (+ `.body.approved|rejected`),
`travel_claim_submitted`, `travel_claim_decided` (+ `.body.approved|rejected`),
`beat_plan_ready`.

## Sync (`POST /v1/sync`)

| entity | device ops | conflict | feed |
|---|---|---|---|
| `notification` | update (`{read_at}`) | last_writer_wins | the user's own |
| `track_gap` | create / update (`{reason, note}`; entity id = the gap id from `/me/day`) | a later reason wins | the officer's own |
| `beat_plan` | update (`{items}` as in `PUT /me/beat`) | last_writer_wins | the officer's own |
| `travel_claim` | create (body of `POST /travel/claims`; receipt uploaded first) | server_wins | own; managers in scope |
| `demo_plot` | create; update `{status: active\|reported}` and / or the yield fields | last_writer_wins | own; managers; agronomists |
| `demo_observation` | create (`demo_plot_id` + observation body) | server_wins | as its demo plot |
| `farmer_meeting` | create; update `{status: closed}` | last_writer_wins | own; managers in scope |
| `meeting_attendance` | create (`meeting_id` + attendance body; `client_ts` is the scan time for a QR) | server_wins | as its meeting |

OTP attendance needs connectivity (like FA-016); QR attendance works offline and is validated
when the op syncs, against the scan time.

## Settings

Tenant (`PATCH /v1/settings`): `ta_daily_km_cap` (150), `beat_daily_target` (10),
`beat_follow_up_days` (14); `ta_rate_per_km_paise` (300) already existed.
Deployment: `PUSH_PROVIDER=fcm|fake|off` (default off; prd refuses fake), `FCM_PROJECT`
(default `GCP_PROJECT`), `NOTIFY_MAX_ATTEMPTS` (5), `ROAD_SNAPPER=off|google` (off),
`GOOGLE_MAPS_API_KEY` (Secret Manager), `MEETING_QR_TTL_SECONDS` (300). None is required by
the Cloud deployment contract, so Terraform is unchanged here.

## Jobs (Cloud Scheduler wiring is infra work)

- `python -m farmerapp.jobs deliver-notifications --tenant <id|slug>` — every minute (or a
  Scheduler -> Pub/Sub `notify.send` message `{"tenant_id"}` per tenant: the worker drains).
- `python -m farmerapp.jobs process-tracks --tenant …` — every 30 minutes.
- `python -m farmerapp.jobs generate-beat-plans --tenant … [--date]` — daily 06:00 IST.

## Tests

`tests/notifications` (acceptance: delivered and listed in the inbox with `FakePushSender`;
retries / failure / unregistered / lost device / no device; FCM adapter on a mocked transport;
sync feed), `tests/duty/test_processing.py` (synthetic tracks with a stop and a gap; fixture
routes with known road distance: km within 10 % with the filter, 2 % with snapping; Roads API
adapter on a mocked transport and its fallback), `tests/duty/test_timeline.py` (day, gap
reasons shown to the cluster head, open-session gaps, re-processing), `tests/travel`,
`tests/beat`, `tests/performance` (equality with `/v1/analytics/officers/{id}`),
`tests/demo_plots`, `tests/meetings`; SEC-006 matrix fixtures for the new routes; RLS
meta-test covers the new tables.

## Edits to shared files (additive)

- `sync/service.py`, `sync/models.py`, `sync/schemas.py`: the eight entities (dispatch to
  `sync/field_p1.py`, feed clauses, current state, conflict rules).
- `analytics/replay.py` + `schemas.py`: gap `id` / `note` / stored `reason`; processed km for
  ended sessions inside the day. `analytics/field_team.py`: profile `sales_net_paise` /
  `sales_orders`.
- `duty/service.py`: duty end runs the VV-006 processing (one update of the session row).
- `visits/service.py` (app_push notification), `khata/credit.py` (decision notification),
  `worker/dispatch.py` (`notify.send` handler), `tenants/settings*.py` (3 settings),
  `uploads/models.py` (`demo_plot` purpose), `settings.py`, `jobs/cli.py`, `api/app.py`.
- Tests: SEC-006 matrix fixtures; `tests/test_telemetry.py` uses `order.created` (still a
  no-op handler) for the trace test; `tests/duty/test_auto_end.py` resets the cached engine
  before the job wrappers (the engine built at import pointed at the local dev database);
  `tests/catalog/test_models.py` counts `travel_claim.amount_paise`; `tests/visits/
  test_flow.py` asserts the push prompt. `docs/deploy/configuration.md`: the new settings.

## Human gates

- Real FCM delivery to a device (Firebase project, service account with
  `cloudmessaging.messages.create`, the app's `google-services.json`).
- FA-023 acceptance on real roads: drive the test routes with the officer app and compare the
  processed km with the Google Maps route distance (within 10 %); enabling `ROAD_SNAPPER=google`
  needs a Maps Platform key in Secret Manager and billing.
- Cloud Scheduler entries for the three jobs (stg / prd apply is human-only).

## Assumptions

- Meetings do not create `visit` rows (a visit is per farmer); the meeting check-in is evaluated
  exactly like a `meeting` visit (meeting point radius) and stored on the meeting.
- The accountant reads travel claims and statements (payroll); km figures only, never tracks.
- The daily km cap (150 km) is a placeholder until the owner sets it.

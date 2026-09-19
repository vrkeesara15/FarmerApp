# rules/ — validation agent rules (SPEC 6)

Rules are versioned YAML config (VA-001): thresholds change through a config PR, never a code
change. The engine (`apps/api/farmerapp/rules/`) loads every `rules/<rule_id>.yaml` at API,
worker and job startup, validates it with Pydantic and refuses to start on an invalid file.
The check itself is a small Python function registered under the same id; it receives the
resolved parameters, so tuning a threshold is a YAML-only change.

## Layout

```
rules/
  README.md
  VA-F01.yaml                 # one file per rule; the file name is the rule id
  VA-F02.yaml
  ...
  fixtures/                   # VA-007 golden fixtures, one directory per rule
    VA-F02/
      positive.yaml           # must raise the expected flag(s)
      negative.yaml           # must raise nothing
    VA-F08/
      positive-farm-photo.yaml  # optional extra scenarios: positive-<name> / negative-<name>
```

Implementations live in `apps/api/farmerapp/rules/checks/va_<id>.py` (one module per rule,
imported by `checks/__init__.py`).

## Rule file

```yaml
id: VA-F06                    # VA-F.. (farmer data) or VA-E.. (employee); = file name
version: 1                    # bump on ANY change; every flag stores rule id + version (VA-002)
title: Registration burst
subject: employee             # farmer | employee | visit | store (who the flag is about)
mode: [event, batch]          # inline (API write path) | event (bus / Pub/Sub) | batch (nightly)
triggers: [farmer.registered] # event rules only: the topics that run the rule
severity: high                # high | medium | low (high also notifies every auditor)
owner_role: cluster_head      # routing hint (VA-003): cluster_head | store_manager | auditor
sla_hours: 48                 # SLA of the flag; OPS-010 escalates one level when it passes
enabled: true
params:                       # thresholds the implementation reads (ctx.param("..."))
  max_registrations: 8
  window_minutes: 30
tenant_overrides:             # optional, keyed by tenant slug
  fcc:
    params: {max_registrations: 12}   # only keys that exist in params, same type
  gfl:
    enabled: false
```

The model is strict: an unknown key, a wrong type, an event rule without triggers, an override
of a parameter that does not exist, or a file name that does not match the id fails the
loader — and therefore CI (`make check-api` runs `python -m farmerapp.jobs validate-rules`,
and `tests/rules/test_loader.py`).

## How rules run (SPEC 6.1)

| Mode   | Entry point                                                    | When                                    |
|--------|----------------------------------------------------------------|-----------------------------------------|
| inline | `engine.run_inline(session, tenant, subject, ids)`             | FA-012 registration / farm edits, same transaction |
| event  | `engine.emit(session, tenant, topic, ids)`; bus subscribers in `rules.events`; worker `rules.events.handle_event_message` | see the topic table below |
| batch  | `python -m farmerapp.jobs run-rules --mode batch --tenant fcc` | nightly 02:00 IST (Cloud Scheduler)     |

### Event topics

| Topic                | Raised by (in-process)                                   | Pub/Sub (worker) | Subject ids        | Rules                    |
|----------------------|----------------------------------------------------------|------------------|--------------------|--------------------------|
| `farmer.registered`  | FA-012 registration (`engine.emit`)                      | yes              | farmer             | VA-F06                   |
| `farm.photo`         | farm add / edit with new photos (`engine.emit`)          | —                | farm               | VA-F08                   |
| `visit.created`      | check-in: `VisitCheckedIn` on the visits bus             | yes              | visit              | VA-E01, VA-E08, VA-F08   |
| `visit.photo`        | photo upload: `VisitPhotoAdded`                          | —                | visit              | VA-E08, VA-F08           |
| `visit.confirmed`    | FA-016 confirmation: `VisitConfirmed`                    | —                | visit              | (none yet)               |
| `visit.checked_out`  | check-out: `VisitCheckedOut`                             | —                | visit              | VA-E08                   |
| `duty.started`       | duty start: `DutyStarted` on the location bus            | —                | duty session       | VA-E01                   |
| `location.batch`     | batch ingest (REST + sync): `LocationBatchIngested`      | yes              | duty session       | VA-E01, VA-E02           |
| `payment.captured`   | payments bus: `PaymentCaptured`                          | —                | payment            | (none yet)               |
| `payment.webhook`    | —                                                        | yes              | payment            | (none yet)               |
| `day_close.variance` | ST-006 day close: `CashVarianceDetected` (payments bus, `dispatch`) | —          | day close          | VA-E10                   |
| `ta.claim.submitted` | FA-023 claim submit: `rules.events.on_travel_claim_submitted` | (topic TBD) | TA claim         | VA-E07                   |

The visits and location buses are synchronous for plain subscribers; database work hangs off
`subscribe_async` + `await bus.dispatch(session, event)`, which runs each subscriber in the
write path's transaction inside its own savepoint. A topic nobody subscribes to costs no query.
The in-process run and a later Pub/Sub redelivery of the same event are both safe (dedupe).

Each rule runs in its own savepoint: a failing rule is logged (`rule_failed`) and never breaks
the write or the other rules. Findings become flags through `flags.service.raise_flag`:
dedupe key `<rule>:<subject_type>:<subject_id>:<finding key>` (an unresolved flag is never
raised twice; a finding already reviewed under the same rule version is not raised again),
routing (VA-003), SLA, a `created` history event and `flag_assigned` notifications.

## Writing a rule

1. `rules/VA-XNN.yaml` as above.
2. `apps/api/farmerapp/rules/checks/va_xnn.py`:

   ```python
   @rule("VA-XNN")
   async def check(ctx: RuleContext) -> list[Finding]:
       limit = int(ctx.param("limit"))
       # read through ctx.session (bound to ctx.tenant_id under RLS); never write
       # ctx.subject_ids: the records of the write / event (None in batch = whole tenant)
       return [Finding(subject_type=Subject.EMPLOYEE, subject_id=..., key="day:2026-09-18",
                       title="...", evidence=Evidence(records=[record("visit", vid)],
                                                      points=[...], photos=[...],
                                                      metrics={"reason": "..."}))]
   ```

   `key` makes the finding unique within the rule and subject (a day, a farm, a pair).
   Evidence is all a reviewer (and the VA-004 review agent) sees: cite every record id.
3. Import the module in `checks/__init__.py`.
4. `rules/fixtures/VA-XNN/positive.yaml` and `negative.yaml` (below). A rule without both
   fails CI (VA-007). Further scenarios go in `positive-<name>.yaml` / `negative-<name>.yaml`
   and run like the required pair (any other file name in the directory fails the tests).

## Fixtures (VA-007)

`tests/rules/test_fixtures.py` seeds each fixture into a fresh tenant and runs the rule
through the real engine (batch fixtures twice, to prove re-runs are idempotent). Every
fixture gets a base world: cluster `c1`, store `s1`, villages `v1` / `v2`, users `owner`,
`auditor`, `cluster_head`, `store_manager`, `officer`, `officer2`.

```yaml
description: Why this case must (not) flag.
mode: batch                  # inline | event | batch (default batch)
trigger: farmer.registered   # event only
subjects: [f2]               # inline / event: refs of the records the write touched
now: "2026-09-18T06:30:00Z"  # optional clock (default 2026-09-18 12:00 IST)
seed:
  users:   [{ref: sm2, role: store_manager, cluster: c1, store: s1, phone: "+919100000001"}]
  farmers: [{ref: f1, name: Mallesh Goud, village: v1, registered_by: officer,
             phone_verified: true, at: -2h, device: D1}]
  farms:   [{ref: farm1, farmer: f1, area_acres: 1.0, square: {east_m: 0, north_m: 0, side_m: 64}},
            {ref: farm2, farmer: f1, area_acres: 1.0, ring: [[0, 0], [64, 64], [64, 0], [0, 64]]}]
expect:
  flags:                     # [] for the negative case
    - {subject: f1, severity: medium, owner: store_manager, watchers: [], reasons: [area_mismatch]}
```

Times (`at`) are `-<n>s|m|h|d` relative to `now`; positions are metres east / north of the
village centre; `device` records the registration in the audit trail with that
`X-Device-Id`.

Field data for the employee rules (see `tests/rules/harness.py` for every key):

```yaml
seed:
  villages: [{ref: v1, meeting_point: {east_m: 0, north_m: 0}, radius_m: 150}]
  duty:     [{ref: d1, officer: officer, start: -4h, integrity: {is_rooted: true}}]
  points:   [{duty: d1, at: -3h, east_m: 0, north_m: 0, accuracy_m: 8, is_mock: true}]
  visits:   [{ref: visit1, officer: officer, farmer: f1, farm: farm1, at: -2h, minutes: 20,
              east_m: 1000, geofence: inside, purpose: advisory, integrity: {clock_drift_s: 400}}]
  photos:   [{ref: p1, visit: visit1, sha256: "...", phash: "c3a5f00f12345678",
              flags: [exif_time_mismatch]}]
  farm_photos: [{ref: fp1, farm: farm1, sha256: "...", phash: "d4392bd4730f9472"}]
  confirmations: [{ref: c1, visit: visit1, channel: sms_otp, at: -1h,
                   phone: "+919876500001", device: OFFICER-PHONE}]
```

M7 records (`tests/rules/harness_m7.py` has every key):

```yaml
seed:
  tenant_settings: {service_area: {districts: [{code: TG-WGL, name: Warangal,
                    bbox: [79.2, 17.7, 79.9, 18.4]}]}, discount_policy_max_bps: 1000}
  crop_calendar: [telangana, {district: Warangal, crop: tomato, season: kharif,
                              start: "05-01", end: "05-31"}]
  crop_plots: [{ref: plot1, farm: farm1, crop: paddy, season: kharif, sown: 2026-06-20}]
  consents:   [{farmer: f1, purpose: marketing, granted: -60d}, {farmer: f1, withdrawn: -2d}]
  farmer_logins: [{farmer: f1, at: -70d}]
  orders: [{ref: o1, placed_by: officer, farmer: f1, at: -3h, subtotal: 100000, discount: 20000,
            cancelled: -1d}]
  khata:  [{ref: d1, farmer: f1, type: debit, amount: 500000, at: -60d, due: -10d}]
  day_closes: [{ref: dc1, closed_by: store_manager, at: -2h, expected: 1000000, counted: 900000}]
  duty: [{ref: d1, start: -30h, end: -22h, km: 40.0}]            # km for VA-E07
  visits: [{ref: v1, farmer: f1, at: -3d, minutes: 20, status: verified}]   # VA-E11
  # port fakes (farmerapp.rules.ports), installed for the run:
  segment_members: [{farmer: f1, segment: paddy-growers, campaign: cmp-1}]  # VA-F09
  travel_claims: [{ref: claim1, officer: officer, day: -26h, km: 60.0}]    # VA-E07
  land_cover: [{farm: farm1, class: water}]                                 # VA-F04
```

## Ports (data the rules cannot read yet)

Three M7 rules read data through `farmerapp.rules.ports` (null adapter = no rows = no flag,
until the owning package registers a real adapter with `set_ports(...)` at startup):

| Port | Rule | Real adapter | Until then |
|------|------|--------------|------------|
| `SegmentMembershipPort` | VA-F09 | WC-008 campaigns (segment members) | no members: nothing flagged |
| `TravelClaimPort` | VA-E07 | FA-023 TA claims (travel package), which also calls `on_travel_claim_submitted` | no claims |
| `LandCoverPort` | VA-F04 (road / water / built-up half) | **human gate**: ESA WorldCover (plus a road layer) loaded into PostGIS | only the service-district check runs |

## Runtime switch (VA-006)

`rule_tenant_override` switches one rule off for one tenant at runtime, on top of the YAML
(which still wins: an override never turns on a rule the YAML disabled). The weekly
`python -m farmerapp.jobs rules-quality-report` job disables a rule whose four-week
precision (confirmed / resolved) is under 30 % with at least 5 resolutions, pending review;
an owner or tenant admin re-enables it with `POST /v1/flags/rules/{id}/enable` (step-up,
audited). Tune the rule through a config PR (bump `version`) before re-enabling it.

Fixtures never read the wall clock: `now` is fixed and every time is relative to it. Location
points live in daily partitions keyed by the **UTC** day; the harness creates the partitions
of the days a fixture touches before inserting its points. Quote pHash values (a hex string
of digits only would otherwise parse as a number).

## Rules in this directory

| Rule   | Check                                                                 | Modes          | Owner         |
|--------|-----------------------------------------------------------------------|----------------|---------------|
| VA-F01 | phone format, OTP verified after 72 h, staff / blocklisted phone      | inline, batch  | store manager (+ auditors) |
| VA-F02 | duplicate farmer: same phone digits, or similar name + village + farms within 50 m | inline, batch | store manager |
| VA-F03 | farm polygon: area ±30 %, self-intersection, > 20 % overlap           | inline, batch  | store manager |
| VA-F06 | > 8 registrations in < 30 min by one officer; a device shared by officers | event, batch | cluster head (+ auditors) |
| VA-F08 | farm or visit photo whose pHash is within 6 bits of another farmer's farm or visit photo (re-encoded, resized, slightly cropped), or with the same bytes (sha256) | event (`visit.photo`, `visit.created`, `farm.photo`) | store manager (+ auditors) |
| VA-E01 | mock location, rooted device or clock drift > 300 s at duty start, in a location batch or at check-in; one flag per officer-day | event (`duty.started`, `location.batch`, `visit.created`) | cluster head (+ auditors) |
| VA-E02 | > 90 km/h between consecutive points (accuracy ≤ 100 m, jumps within the combined accuracy ignored); one flag per officer-day | event (`location.batch`) | cluster head (+ auditors) |
| VA-E03 | ≥ 5 farms' visits pairwise within 200 m on one IST day, away from any village meeting point | batch | cluster head (+ auditors) |
| VA-E04 | > 40 % of an officer-day's checked-out visits (≥ 3) under the tenant `min_visit_duration_s` | batch | cluster head |
| VA-E05 | one OTP phone confirming ≥ 3 farmers, or one farmer-side device (push / QR) confirming ≥ 3 farmers, in 7 days | batch | cluster head (+ auditors) |
| VA-E08 | photo EXIF time / GPS inconsistent with the check-in (`photo_flags`), or the same sha256 / pHash on another visit; one flag per visit | event (`visit.photo`, `visit.checked_out`, `visit.created`) | cluster head (+ auditors) |

| VA-F04 | farm centroid outside the tenant's `service_area` districts, or on water / built-up / road (`LandCoverPort`) | batch | store manager |
| VA-F05 | crop and sowing date vs season and the district crop calendar (`crop_calendar`, district row else state row; ±15 days) | batch | store manager |
| VA-F07 | ghost farmer: registered ≥ 60 days ago, never a confirmed visit, purchase or app login | batch | store manager |
| VA-F09 | in a campaign segment (`SegmentMembershipPort`) without marketing consent, or withdrawn | batch | store manager (+ auditors) |
| VA-F10 | khata debit overdue > 90 days, or a new credit sale while a debit was overdue | batch | store manager |
| VA-E06 | > 3 h of a duty session without a visit, a stop boundary or movement ≥ 100 m | batch | cluster head |
| VA-E07 | TA claim km vs the duty track's km differ by > 15 % (`TravelClaimPort`) | event (`ta.claim.submitted`) | cluster head |
| VA-E09 | discount above `discount_policy_max_bps`, sale to a staff phone (hash), ≥ 3 cancellations after the `incentive_cutoff_day` of orders placed in the period | batch | cluster head (+ auditors) |
| VA-E10 | day close variance above `day_close_variance_threshold_paise`; ≥ 3 small variances in 14 days by one closer | event (`day_close.variance`), batch | cluster head |
| VA-E11 | verified visits down > 30 % week on week for two complete IST weeks (coaching) | batch | cluster head |

All 21 rules of SPEC 6.2 / 6.3 are in place (eleven P0 rules of M4, ten of M7);
`tests/rules/test_fixtures.py::test_rules_exist` lists them and fails on any other set.

## Review agent (VA-004)

Every new flag gets a three-line plain summary and a suggested action written by an LLM from
the flag's evidence bundle **only** (`farmerapp/flags/review_agent.py`): rule, severity,
subject, record ids, scrubbed metrics (no names, phones masked, no coordinates, no photos,
not the flag title). The answer must cite record ids of the bundle and nothing else
(rejected and retried once otherwise). So write evidence that stands on its own: cite every
record id in `records`, put the numbers a reviewer needs in `metrics`, and never put names
or phone numbers in `metrics` (they are dropped from the prompt, and the reviewer sees the
record summaries anyway).

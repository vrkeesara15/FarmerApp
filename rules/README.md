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
| event  | `engine.emit(session, tenant, topic, ids)`; worker `rules.events.handle_event_message` | `farmer.registered`, `visit.created`, `payment.webhook`, in-process `payment.captured` |
| batch  | `python -m farmerapp.jobs run-rules --mode batch --tenant fcc` | nightly 02:00 IST (Cloud Scheduler)     |

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
   fails CI (VA-007).

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

Times (`at`) are `-<n>m|h|d` relative to `now`; positions are metres east / north of the
village centre; `device` records the registration in the audit trail with that
`X-Device-Id`.

## Rules in this directory

| Rule   | Check                                                                 | Modes          | Owner         |
|--------|-----------------------------------------------------------------------|----------------|---------------|
| VA-F01 | phone format, OTP verified after 72 h, staff / blocklisted phone      | inline, batch  | store manager (+ auditors) |
| VA-F02 | duplicate farmer: same phone digits, or similar name + village + farms within 50 m | inline, batch | store manager |
| VA-F03 | farm polygon: area ±30 %, self-intersection, > 20 % overlap           | inline, batch  | store manager |
| VA-F06 | > 8 registrations in < 30 min by one officer; a device shared by officers | event, batch | cluster head (+ auditors) |

Next: VA-F08, VA-E01–E05, VA-E08 (M4 loop).

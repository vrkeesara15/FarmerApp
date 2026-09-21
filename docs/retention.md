# Data retention policy (NF-012)

SPEC NF-012 in one sentence:

> Raw location points 180 days; visit records 7 years; photos 3 years then archived;
> audit logs 1 year minimum; financial records 8 years.

That sentence is implemented once, in `apps/api/farmerapp/retention/policy.py`. This document
explains the five classes; the code is the authority, and `apps/api/tests/retention/` fails if
the two disagree.

## The classes

| Class | Window | Action | Tables | Who does it |
|---|---|---|---|---|
| `location_points` | 180 days | purge | `location_point` | `python -m farmerapp.jobs purge-location-points` (daily; aggregates into `location_daily_agg`, drops whole partitions) |
| `photos` | 3 years | archive | `farm_photo`, `visit_photo` | GCS lifecycle rule on the photos bucket — `SetStorageClass ARCHIVE` at 1095 days (NEARLINE at 90). **The rows stay**: a seven-year visit record must still name its photo. |
| `audit_logs` | 400 days (min 365) | purge | `audit_log` | `python -m farmerapp.jobs purge-audit-logs`, then the real delete as the **migrate role** (the app role cannot delete from an append-only table) |
| `visit_records` | 7 years | purge | `visit_confirmation`, `visit_photo`, `visit` | `retention-sweep --apply` |
| `financial_records` | 8 years | **retain** | `invoice`, `payment`, `order_line`, `order`, `khata_entry`, `day_close` | nobody — the window is a floor, not a deadline |

"Retain" is the important row. Eight years is a **minimum** imposed by section 128 of the
Companies Act and the GST rules, not a deletion deadline. Nothing in this codebase deletes a
financial record, and an erasure request does not either — see
[docs/dpdp.md](dpdp.md#the-erasure-exception).

## The sweep

```bash
# Report every class for a tenant. Dry run: nothing is deleted.
python -m farmerapp.jobs retention-sweep --tenant-id <uuid>

# Only one class.
python -m farmerapp.jobs retention-sweep --tenant-id <uuid> --class visit_records

# Actually delete what the runtime role may delete.
python -m farmerapp.jobs retention-sweep --tenant-id <uuid> --class visit_records --apply
```

Output, one line per class:

```
retention-sweep (dry-run): tenant=0f1e…
  location_points    purge      180d due=0       deleted=0 -> purged by python -m farmerapp.jobs purge-location-points
  photos             archive   1095d due=12      deleted=0 -> archived by GCS lifecycle rule on the photos bucket
  audit_logs         purge      400d due=310     deleted=0 -> needs the migrate role: run python -m farmerapp.jobs purge-audit-logs
  visit_records      purge     2555d due=4       deleted=0
  financial_records  retain    2920d due=51      deleted=0 -> retained: 2920 days is a floor, not a deadline
```

Rules the job obeys, all covered by tests:

* **Dry run is the default**, everywhere, including the scheduled Cloud Run Job. Turning a
  sweep into a delete is a deliberate act (`--apply`, and in prd a Terraform variable — the
  same shape `purge-location-points` already uses with `location_purge_apply`).
* **The tenant is bound before anything is counted** (`set_tenant`), so a sweep can never
  reach another tenant's rows even if the caller left a session bound elsewhere (SEC-012).
* **`RETAIN` never deletes**, with or without `--apply`.
* **`ARCHIVE` never deletes**: the bucket moves the object to a colder class; the row stays.
* **Append-only classes are reported, not swept**: the runtime role has no `DELETE` grant on
  `audit_log` (migration 0004). The report says which job and which identity does the work.

## Scheduling

`location_points` and `audit_logs` already have their own Cloud Run Jobs (see
`infra/envs/*/main.tf`). The sweep is meant to run **daily, per tenant, as a dry run**, so the
numbers land in Cloud Logging and OPS-005 can alert when a class stops being swept or a count
grows without bound. Enabling `--apply` for `visit_records` in prd is a human decision and a
Terraform change, not a code change.

## Adding a table

Every table that holds personal data belongs to a class. Add it to the right
`RetentionClass.tables` in `policy.py`; child tables come first, because the sweep deletes in
that order and a parent first would trip a foreign key.

**This is a review responsibility, not a gate.** The tests check that every class names a real
table and that this document covers every class — but nothing fails when a *new* personal-data
table is added and nobody puts it in a class. Automating that would mean first agreeing which
tables hold personal data, which is a judgement call rather than a property of the schema.
Until someone makes that call, a new table that holds anything about a person needs a line
here and in `policy.py` as part of its own change.

If the table is append-only, mark the class `migrate_role=True` — `test_append_only_classes_are_marked_migrate_role`
checks that against `farmerapp.db.rls.APPEND_ONLY_TABLES` and fails otherwise.

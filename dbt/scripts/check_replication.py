"""AN-014 guard: the Datastream column allowlist, the dbt sources and the fixtures agree.

  1. infra/modules/analytics/replicated_columns.json (what Datastream replicates) must list
     exactly the tables and columns of models/staging/_sources.yml (what dbt reads), plus the
     tables of PENDING_REPLICATION below, whose allowlist entry lands with their Terraform
     change (they are checked like any other table).
  2. The allowlist never contains a PII column (names of people, phones, landmarks, points,
     notes, token hashes, device ids, evidence).
  3. Every fixture seed (seeds/raw/public_<t>.csv) has the allowlisted columns plus the
     Datastream metadata; the only extra columns allowed are the fake name / phone of
     public_farmer and public_user, kept on purpose so the staging tests prove PII is dropped
     even if the allowlist were misconfigured.
  4. seeds/_seeds.yml is up to date with the seed headers (scripts/gen_seed_types.py).

Usage (from dbt/): uv run python scripts/check_replication.py
"""

from __future__ import annotations

import csv
import json
import subprocess
import sys
from pathlib import Path

import yaml

DBT = Path(__file__).resolve().parents[1]
ALLOWLIST = DBT.parent / "infra" / "modules" / "analytics" / "replicated_columns.json"
SOURCES = DBT / "models" / "staging" / "_sources.yml"
SEEDS = DBT / "seeds" / "raw"

FORBIDDEN = {
    "contact": {"phone", "phone_enc", "phone_hash", "landmark", "landmark_enc", "email"},
    "location": {"location", "geofence", "boundary", "centroid", "home_point", "checkin_point",
                 "checkout_point", "start_point", "end_point", "meeting_point", "stops", "point"},
    "free_text": {"notes", "note", "override_note", "title", "evidence", "resolution_note",
                  "expert_note", "reason_text", "description"},
    "secrets": {"token_hash", "code_hash", "device_id", "device_integrity", "qr_payload"},
}
# Tables whose `name` is a person's name (other tables' names are places, crops, pests).
PERSON_TABLES = {"user", "farmer"}
SEED_TEST_PII = {"farmer": {"name", "phone"}, "user": {"name", "phone"}}
DS_META = {"_ds_uuid", "_ds_source_timestamp"}

# Tables dbt already reads whose entry in replicated_columns.json lands with the Terraform
# change that adds them to the stream (AN-008 campaigns, WC-008). They are checked here exactly
# like a replicated table -- same columns in _sources.yml and in the fixture seed, no PII column
# -- but they are not yet expected in the allowlist. Move a table into replicated_columns.json
# (removing it from here) with the Datastream stream update; this dict must end up empty.
PENDING_REPLICATION = {
    "campaign": [
        "id", "tenant_id", "channel", "status", "template_key", "scheduled_at", "started_at",
        "finished_at", "attribution_days", "holdout_pct", "audience_size", "created_by",
        "created_at", "updated_at", "deleted_at",
    ],
    "campaign_recipient": [
        "id", "tenant_id", "campaign_id", "farmer_id", "arm", "language", "status",
        "skip_reason", "sent_at", "delivered_at", "opened_at",
        "created_at", "updated_at", "deleted_at",
    ],
}


def main() -> int:
    errors: list[str] = []
    allow = {k: v for k, v in json.loads(ALLOWLIST.read_text()).items() if not k.startswith("_")}
    for t, cols in PENDING_REPLICATION.items():
        if t in allow:
            errors.append(f"{t}: now replicated -- drop it from PENDING_REPLICATION in this script")
        else:
            allow[t] = cols

    sources = yaml.safe_load(SOURCES.read_text())
    tables = {
        t["name"].removeprefix("public_"): [c["name"] for c in t.get("columns", [])]
        for s in sources["sources"]
        if s["name"] == "farmerapp_raw"
        for t in s["tables"]
    }
    for t in sorted(set(allow) | set(tables)):
        if t not in allow:
            errors.append(f"{t}: in _sources.yml but not replicated (replicated_columns.json)")
        elif t not in tables:
            errors.append(f"{t}: replicated but not declared in _sources.yml")
        elif sorted(allow[t]) != sorted(tables[t]):
            errors.append(f"{t}: columns differ: allowlist {sorted(allow[t])} vs sources {sorted(tables[t])}")

    forbidden = set().union(*FORBIDDEN.values())
    for t, cols in allow.items():
        for c in cols:
            if c in forbidden or (c == "name" and t in PERSON_TABLES):
                errors.append(f"{t}.{c}: PII column in the replication allowlist (AN-014)")

    for path in sorted(SEEDS.glob("public_*.csv")):
        t = path.stem.removeprefix("public_")
        with path.open(newline="") as fh:
            header = next(csv.reader(fh))
        expected = set(allow.get(t, [])) | DS_META
        extra = set(header) - expected - SEED_TEST_PII.get(t, set())
        missing = expected - set(header)
        if t not in allow:
            errors.append(f"seed {path.name}: table is not replicated")
        if extra:
            errors.append(f"seed {path.name}: columns not replicated by Datastream: {sorted(extra)}")
        if missing:
            errors.append(f"seed {path.name}: missing columns {sorted(missing)}")

    gen = subprocess.run(
        [sys.executable, str(DBT / "scripts" / "gen_seed_types.py"), "--check"],
        capture_output=True, text=True, check=False,
    )
    if gen.returncode != 0:
        errors.append(gen.stdout.strip() or "seeds/_seeds.yml check failed")

    for e in errors:
        print(f"FAIL: {e}")
    if not errors:
        print(f"replication allowlist OK: {len(allow)} tables, sources and fixtures agree")
    return 1 if errors else 0


if __name__ == "__main__":
    raise SystemExit(main())

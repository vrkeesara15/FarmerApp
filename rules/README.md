# rules/ — validation agent rules (SPEC 6)

Rules are versioned YAML config (VA-001): thresholds change via a config PR, never a code
change. The engine that loads them arrives in M4 (`farmerapp.rules`); until then this
directory holds the layout contract and, from M4 on, one file per rule plus fixtures.

## Layout

```
rules/
  README.md
  farmer/                  # VA-F01 .. VA-F10 (SPEC 6.2)
    VA-F02-duplicate-farmer.yaml
    fixtures/VA-F02/
      positive.json        # must raise a flag
      negative.json        # must not
  employee/                # VA-E* (SPEC 6.3)
    VA-E01-....yaml
    fixtures/VA-E01/{positive,negative}.json
  tenants/                 # per-tenant threshold overrides (VA-001)
    <tenant-slug>.yaml
```

## Rule file

```yaml
id: VA-F02
version: 3                      # bump on any change; flags store rule id + version (VA-002)
name: duplicate_farmer
subject: farmer                 # farmer | employee | visit
mode: [inline, batch]           # inline (API write path) | event (Pub/Sub worker) | batch (nightly job)
severity: medium                # low | medium | high
enabled: true
route:                          # VA-003
  owner: store_manager          # cluster_head | store_manager | auditor
  escalate_high_to: auditor
sla_hours: 72
params:                         # tunable thresholds; tenants may override any key
  centroid_distance_m: 50
  name_similarity: 0.85
evidence:                       # records included in the flag evidence bundle (VA-004)
  - farmer
  - farm.centroid
  - matched_farmer
```

## Fixtures (VA-007)

Every rule ships a positive and a negative fixture; CI fails a rule that has no fixtures.
A fixture is the minimal set of records the rule reads plus the expected outcome:

```json
{ "records": { "farmers": [...], "farms": [...] }, "expect": { "flag": true, "severity": "medium" } }
```

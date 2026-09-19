# M4 — remaining P0 validation rules

Branch `feat/M4-p0-rules` (on `feat/M4-rules-engine-flags` d3868bd; merge after that branch
lands on `main`). Requirement IDs: VA-F08, VA-E01, VA-E02, VA-E03, VA-E04, VA-E05, VA-E08
(done). With VA-F01 / F02 / F03 / F06 from the kickoff, all eleven P0 rules of SPEC 6.2 / 6.3
are in place. The branch itself has no migration; the farm-photo pHash follow-up on `main`
adds `0023` (below). **Merged into `main`** — see "Merge into main" and "Follow-up done".

## Rules

Each is one `rules/<id>.yaml` (params + SLA), one module `farmerapp/rules/checks/va_<id>.py`
registered with `@rule`, and a positive + negative golden fixture in `rules/fixtures/<id>/`.

| Rule   | Mode / triggers                                         | Severity, routing          | Check |
|--------|---------------------------------------------------------|----------------------------|-------|
| VA-F08 | event: `visit.photo`, `visit.created`, `farm.photo`     | high, store manager + auditors | visit photo pHash within `max_hamming_distance` (6) bits of another farmer's visit photo (`bit_count` of the XOR in SQL); farm photo with the same sha256 as another farmer's farm / visit photo. One flag per photo pair about the farmer of the new photo; evidence: both blob URIs, both farmer ids, distance. |
| VA-E01 | event: `duty.started`, `location.batch`, `visit.created` | high, cluster head + auditors | mock location, rooted device or clock drift > 300 s from the duty-start integrity, location points and check-in integrity. The event names the officer-days; the flag gathers every signal of that IST day; key `integrity:<day>` = one flag per officer per day. |
| VA-E02 | event: `location.batch`                                 | high, cluster head + auditors | > 90 km/h between consecutive points of the duty session; points with accuracy > 100 m dropped; a leg no longer than the two points' combined accuracy is jitter. One flag per officer-day, fastest leg as evidence (both points on the map, speed, distance, seconds). |
| VA-E03 | batch                                                   | high, cluster head + auditors | ≥ 5 distinct farms' visits of one officer-day pairwise within 200 m (a clique, not a chain), excluding meeting-point / meeting-purpose visits and check-ins inside any village's meeting-point radius. Evidence: centroid, visits, map. |
| VA-E04 | batch                                                   | medium, cluster head       | > 40 % of an officer-day's checked-out visits (≥ 3) under the tenant `min_visit_duration_s`. |
| VA-E05 | batch                                                   | high, cluster head + auditors | within 7 days: one OTP-receiving phone confirming visits for ≥ 3 farmers; one farmer-side device (push / QR) confirming for ≥ 3 farmers. Masked phone only; key per ISO week. |
| VA-E08 | event: `visit.photo`, `visit.checked_out`, `visit.created` | high, cluster head + auditors | `photo_flags` EXIF time / GPS mismatch (missing EXIF only with `flag_missing_exif`), or the same sha256 / pHash on another visit. One flag per visit. |

Routing is the engine's (VA-003); each positive fixture asserts owner and watchers, so every
rule has a routing test.

## Event wiring (SPEC 6.1)

- `farmerapp/visits/events.py`: the bus gains `subscribe_async` / `unsubscribe_async` and
  `await bus.dispatch(session, event)` (same contract as the payments bus): async subscribers
  run in the write path's transaction, each in a savepoint, failures logged and isolated;
  then the plain synchronous subscribers. New events `VisitCheckedIn`, `VisitPhotoAdded`,
  `VisitConfirmed`, `VisitCheckedOut`; `IntegrityEvent` is now dispatched the same way.
- `farmerapp/location/events.py` (new): `DutyStarted`, `LocationBatchIngested` on a bus of the
  same class.
- Write paths: check-in, photo, confirmation, check-out (`visits/service.py`), duty start
  (`duty/service.py`), batch ingest when at least one point was accepted
  (`location/ingest.py`; REST and sync op), farm add / edit with new photos
  (`farmers/service.py` -> `engine.emit("farm.photo")`). Replays publish nothing.
- `farmerapp/rules/events.py`: `register()` subscribes the topic runners; `SUBJECT_KEYS` for the
  new topics. The worker's `location.batch` handler (was a no-op) now runs the event rules
  (`tenant_id` + `duty_session_id`); `visit.created` already did.
- `engine.run_rules` returns before any query when no rule subscribes to the topic.

## Decisions and assumptions

- **No migration on the branch.** `farm_photo` had no pHash column, so the branch matched
  farm photos by sha256 only. Done on `main` as `0023_farm_photo_phash` (see "Follow-up done").
- **Event-only rules need their subjects**: VA-E01 / E02 / E08 / F08 return nothing when run
  without subject ids, so they never scan a tenant.
- **VA-E01 day** is the IST day; points of a session crossing midnight count for both days.
  Location queries use `ts` ranges, so only the partitions of those UTC days are touched.
- **VA-E05**: `sms_otp` codes are typed on the officer's phone by design (FA-016), so the
  device branch looks only at `app_push` / `qr` confirmations (the farmer-side device). Farmer
  phones are unique per tenant: the phone branch catches codes delivered to a number shared
  by several farmers' confirmation challenges.
- **VA-E08 vs VA-F08**: reuse on another visit of the same farmer is an employee flag (E08);
  across farmers both fire (E08 about the officer, F08 about the farmer).
- **Fixtures** are clock-free (fixed `now`); the harness now seeds duty sessions, points
  (creating the UTC-day partitions first), visits, photos, farm photos, confirmations with
  OTP challenges and village meeting points; `-<n>s` offsets; multiple flags about one
  subject are matched by reason.
- `tests/location/test_partitions.py` compared DB (UTC) partitions with the machine's local
  date; it now uses the UTC date (it failed whenever local and UTC dates differed).

## Tests

- `tests/rules/test_fixtures.py` — `test_rules_exist` lists all eleven P0 rules
  (`harness.P0_RULES`); 22 golden fixtures, batch ones run twice.
- `tests/rules/test_field_rules.py` — a YAML-only threshold change flips each negative
  fixture; VA-E04 follows the tenant minimum; VA-F08 farm-photo sha256 branch and the
  per-photo cap; VA-E01 duty-start signal; event rules without subjects; E02 / E03 helpers;
  worker `location.batch` / `visit.created` runs, redelivery idempotent.
- `tests/visits/test_rules_events.py` — through the API: check-in integrity -> one VA-E01
  per officer-day, EXIF GPS mismatch and photo reuse -> VA-E08, the same photo for another
  farmer -> VA-F08 (store manager), confirmation / check-out events.
- `tests/location/test_rules_events.py` — duty start with a rooted phone -> VA-E01; a batch
  with a 12 km jump and a mock point -> VA-E02 + VA-E01, replay and a later batch deduped; a
  failing rule never breaks the ingest; async subscriber isolation.

ruff, ruff format, mypy strict, `validate-rules` (11 rules), pytest with coverage, OpenAPI
check (unchanged) and bandit green.

## Merge into main (2026-09-19)

`merge(M4): feat/M4-p0-rules` (--no-ff, branch at 7b11a6d, on top of the M4 integration
1a4c118: analytics / admin merges, `0021_merge_m4_heads`, `0022` `farmer.captured_at`, VA-F06
on capture time, rules baked into the images).

| File | Resolution |
|---|---|
| `tests/location/test_partitions.py` | main's version kept (its own host-time-zone fix, 9f93f9b) |
| `tests/rules/harness.py` | both: `captured:` (VA-F06 capture time) and the field-data seeding (duty, points, visits, photos, farm photos, confirmations, villages) |
| `docs/progress.md` | newest status per row: VA-F06 keeps the integration note (capture time), the seven rules take the branch's `done` rows |
| auto-merged | `rules/README.md`, worker dispatch (`location.batch`), visits events, `location/ingest.py`, `farmers/service.py` (`farm.photo` emit next to `captured_at`), `visits/service.py`, `test_fixtures.py` (`P0_RULES` = all eleven) |

`apps/api/README.md` and `openapi.yaml` did not conflict; `make openapi` leaves `openapi.yaml`
unchanged (no endpoint or schema changed). `alembic heads` was still `0022` after the merge.
The worktree `.claude/worktrees/agent-a5d20757823866aec` and its branch were removed; the
feature branch is kept.

## Follow-up done: perceptual hash for farm photos (VA-F08)

- **Alembic `0023_farm_photo_phash`** (down 0022; expand-only): nullable `farm_photo.phash`
  (16 hex chars) and `ix_farm_photo_tenant_phash (tenant_id, phash)`. Verified on a scratch
  database: `upgrade 0022` (no column) -> `upgrade head` (column + index) -> `downgrade 0022`
  (both gone) -> `upgrade head`. `alembic heads` -> `0023 (head)`.
- **Write path**: `farmers/photo_hash.py::farm_photo_phash` reads the blob and hashes it with
  the visit-photo helper (`visits.photos.phash`, Pillow + imagehash). Registration, farm add
  and farm edit take the blob store (routers: `get_blob_store(request)`; sync `farmer` /
  `farm` create and `farm` update: `ctx.blobs`). A missing or undecodable blob leaves `phash`
  NULL (the photo is still stored, as before).
- **VA-F08** now compares all farm and visit photos of other farmers in one query: a match is
  identical bytes (sha256) or both pHashes within `max_hamming_distance`; the evidence metric
  `match` is `phash` whenever both photos have a hash (distance reported), else `sha256`.
  Visit-vs-visit reuse with a missing pHash but identical bytes is now caught as well.
- **Backfill**: `python -m farmerapp.jobs backfill-farm-photo-phash --tenant <id|fcc|gfl>
  [--batch-size 200] [--no-run-rules]` — per tenant, as the system actor, keyset-paged over
  live farm photos with `phash IS NULL`; afterwards VA-F08 runs (`farm.photo`) on the farms
  that got a hash so near-duplicates already on file are flagged. Idempotent: hashed rows
  are skipped, the dedupe key never repeats an open flag; missing / undecodable blobs are
  counted (`unhashable`) and retried on the next run. Run once per tenant after deploying
  0023 (manual; not scheduled).
- **Fixtures**: `rules/fixtures/VA-F08/positive-farm-photo.yaml` (f2's farm photo is f1's
  re-encoded and resized: different sha256, pHash 2 bits away; hashes computed from real
  images) and `negative-farm-photo.yaml` (a different field 34 bits away, and a cropped copy
  on the same farmer's other farm). The original positive / negative pair is unchanged. The
  harness runs extra `positive-<name>` / `negative-<name>` cases with the required pair; an
  unrecognised file in a fixture directory fails the tests.
- **Tests**: `tests/visits/test_farm_photo_phash.py` — real JPEGs (re-encoded, cropped, a
  different field) within / beyond 6 bits; registration stores the hash and a re-encoded copy
  for another farmer raises VA-F08 (`match: phash`); farm add (cropped copy) and farm edit
  (re-encoded copy; a non-image and a missing blob stored with NULL); backfill (3 scanned, 2
  hashed, 1 unhashable, 2 flags; second run hashes nothing and raises nothing; `run_rules`
  off); CLI.

## Rules in the images

The CI `images` job (`ci-api.yml`) and the deploy workflow now compare the
`validate-rules` output inside each image with the number of `rules/*.yaml` in the checkout
(11 today), so an image carrying a stale rule set fails. Verified locally: `docker compose
build api`; `docker run farmerapp/api:local` logs `{"event": "rules_loaded", "rules_dir":
"/app/rules", "count": 11, ...}`; `validate-rules` in the image: 11 rules OK.


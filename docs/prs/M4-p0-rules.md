# M4 — remaining P0 validation rules

Branch `feat/M4-p0-rules` (on `feat/M4-rules-engine-flags` d3868bd; merge after that branch
lands on `main`). Requirement IDs: VA-F08, VA-E01, VA-E02, VA-E03, VA-E04, VA-E05, VA-E08
(done). With VA-F01 / F02 / F03 / F06 from the kickoff, all eleven P0 rules of SPEC 6.2 / 6.3
are in place. No migration.

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

- **No migration.** `farm_photo` has no pHash column, so VA-F08 matches farm photos by sha256
  (identical bytes). Adding `farm_photo.phash` needs the farm write path to read the blob;
  follow-up (would be `0022_p0_rules`).
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

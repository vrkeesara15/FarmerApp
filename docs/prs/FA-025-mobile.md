## Requirement IDs

- FA-025 (P0) Offline-first: all capture works offline for 3 days; sync queue with conflict resolution — mobile half done (API half: `POST /v1/sync`, uploads endpoints, by the API loop against the same contract)
- NF-002 Offline 72 h — field agent half done (72-hour test); farmer-app caching is M6
- NF-003 Outbox with idempotency keys, resumable 256 KB uploads, retry with backoff — mobile half done
- SEC-024 — `DatabaseOpener` seam only (SQLCipher opener lands in M5)
- FA-012 / FA-013 — the typed local tables and the `Outbox` API the A21 wizard will write through; the wizard itself is next

PR title: `feat(FA-025): offline-first sync engine with outbox, resumable uploads and 72-hour offline test (NF-002, NF-003)`

## What changed

All under `apps/mobile`, `design/`, `docs/` (nothing in apps/api, apps/console, infra, .github).

### Drift schema v2 — `packages/core/lib/src/db/app_database.dart`
- `SyncedRow` mixin (`id`, `version`, `updated_at`, `dirty`, `deleted`) on the typed tables `farmers`, `farms` (boundary GeoJSON as text, `photos` JSON list), `crop_plots`, `consent_records` (`consent_version` text = payload `version`; the row `version` is the envelope's int).
- `outbox` (`OutboxTable`, data class `OutboxRow`): `op_id` PK, `seq` FIFO, entity, action, entity_id, base_version, payload JSON, client_ts ISO-8601 UTC, state `queued|sending|applied|duplicate|conflict|rejected`, attempts, last_error JSON, next_attempt_at, depends_on_upload_id; indexes `(state, seq)`, `(entity_id)`.
- `uploads` (local id, server `upload_id` null until init, file path, sha256, size, chunk_size, received chunks JSON, state `pending|uploading|complete|failed`, blob_uri, purpose, content_type, attempts, last_error, expires_at, created_at).
- `sync_states` (single row: cursor, last_sync_at, last_error, attempts, next_attempt_at) and `synced_refs` (`(entity, ref_id)` PK, version, JSON data) for villages, crops and anything the server sends that this app version does not know.
- `MigrationStrategy`: v1 → v2 creates the eight tables + two indexes; `test/db/migration_test.dart` builds a real v1 file with `sqlite3`, opens it through `AppDatabase`, checks the kv rows survive, `user_version` = 2, tables and indexes exist and the new tables accept writes.
- `db/open_database.dart`: `DatabaseOpener` interface (`NativeDatabaseOpener`, `InMemoryDatabaseOpener`); `openAppDatabase({opener})`. SEC-024 swaps in an encrypted opener here.

### Sync module — `packages/core/lib/src/sync/`
- `sync_models.dart`: `SyncOp`, `SyncOpResult`, `SyncChange`, `SyncRequest`, `SyncResponse`, `UploadSession`, `UploadResult`, `SyncError`, enums `SyncAction`, `OutboxState`, `UploadState`, `SyncResultStatus`; `SyncTransportException` / `SyncAuthException`; `maxOpsPerSync = 200`; `upload:<id>` placeholder convention.
- `sync_api.dart`: `SyncApi` (sync, initUpload, uploadChunk, getUpload, completeUpload) and `FakeSyncApi`, an in-memory server: idempotent by `op_id` (rejected ops are not recorded so a resend after an edit is processed), optimistic versions, create-on-existing / stale base_version → `conflict` with the server row, `validate` hook → `rejected`, `script` override, change feed with `addChange` + `pageSize` paging, uploads with per-chunk and whole-file hash checks, `offline`, `failNext`, `loseResponseNext` (applied but reply lost), `failChunk`, `expiredUploads`.
- `http_sync_api.dart`: `HttpSyncApi` over `package:http` — bearer from `TokenStore`, refresh before the call when expired and once on 401 (`HttpAuthApi.refresh`), non-2xx / `ClientException` / `SocketException` / timeout → `SyncTransportException(statusCode, code, detail)`; chunk `PUT` as `application/octet-stream` with `X-Chunk-Sha256`; `GET` 404/410 → null.
- `local_entities.dart`: `LocalEntities` read / write / merge / setFlags / delete for the four typed tables from and to wire JSON, `writeRef`/`readRef`/`deleteRef` for `synced_refs`; conflict rule table (`last_writer_wins` farmer/farm/crop_plot, `append_only` consent_record, `server_wins` reserved for khata_entry/payment) — documentation of the server rules; the client applies the response.
- `sync_store.dart`: `SyncStore` DAO (`insertOp` with `seq = max + 1` in a transaction, `nextBatch` = queued ops in seq order, at most one per entity, none behind a sending/rejected/waiting op of the same entity, ≤ limit; `markSending`, `setResult`, `requeue`, `requeueSending` for crash recovery, `setPayload`, `discard`, `activeOpsFor`, `purgeTerminal`, upload rows, `counts()`, `state()` normalised to UTC).
- `outbox.dart`: `Outbox.enqueueCreate/enqueueUpdate/enqueueDelete(entity, id, payload)` — typed row written optimistically (`dirty`, version kept) and the op appended in one transaction, uuid `op_id`, `client_ts` from the injected clock; `enqueueUpload(filePath, bytes, purpose)` hashes and queues a photo; payload placeholders `Outbox.uploadRef(id)` set `depends_on_upload_id`; an update on a row whose earliest open op is `rejected` folds into that op and requeues it under the same `op_id` (A64 "retry after edit"). `uploadRefsIn` / `substituteUploadRefs` helpers.
- `backoff.dart`: `Backoff(base 1 s, cap 5 min, jitter 0.5)`: ceilings 1, 2, 4 … 256, 300, 300 s; delay drawn from `[ceiling/2, ceiling]` with an injectable `Random`.
- `chunked_uploader.dart`: `ChunkedUploader.upload(row)` — read file (injectable `FileReader`), verify sha256 (mismatch / missing → `failed`), `GET` to resume or `POST` to init, plan with `ChunkedUploadPlanner`, `PUT` only chunks not in `received_chunks` persisting after each, `complete` → `blob_uri`. Transport errors propagate for the engine's backoff with progress already saved.
- `sync_engine.dart`: `SyncEngine(db, api, deviceId, clock, random, backoff, readFile, batchSize)`. `syncNow({force})`: skip when `next_attempt_at` is in the future and not forced; requeue anything left in `sending`; run pending uploads; drain ops whose uploads completed (placeholders → `blob_uri`, local row updated), fail ops whose upload failed; loop: `nextBatch` → refresh `base_version` from the local row for update/delete → `sending` → `/v1/sync` with the stored cursor → results: `applied`/`duplicate` set version and clear `dirty` unless more ops are queued for the row (delete → hard delete), `conflict` replaces the row with `server` (null → delete), `rejected` stores the error and stops that entity; changes: known entities upsert/delete unless the local row is dirty, others → `synced_refs`; cursor stored after every call; continue while ops remain or `has_more`; guard against a server that returns no results. Success resets attempts / next window and purges terminal ops older than 7 days; a `SyncTransportException` records `last_error`, `attempts + 1` and `next_attempt_at = now + backoff`. `watchStatus()` / `watchDetails()` via Drift `tableUpdates` merged with the running flag (`package:async` `StreamGroup`); `SyncStatus {synced | pending(n) | failed(n) | syncing}` with `pillState`; `SyncDetails` for A64; `retry`, `retryUpload`, `retryAll`, `discard`; `SyncReport`.
- `sync_scheduler.dart`: `ConnectivityMonitor` (`FakeConnectivityMonitor`, `PlusConnectivityMonitor` over `connectivity_plus`), `BackgroundWorkScheduler` (`FakeBackgroundWorkScheduler`, `WorkmanagerSyncScheduler`: periodic `in.farmerapp.sync.periodic` every 15 min with `NetworkType.connected`, keep policy, exponential backoff; one-off `in.farmerapp.sync.now` replace policy), `SyncScheduler.start()` (register periodic, sync once if online, on offline→online: forced `syncNow` + one-off job), `SyncScheduler.runBackgroundTask(taskName, buildEngine)` for the app's `callbackDispatcher`.
- `sync_providers.dart`: `syncApiProvider` (default `FakeSyncApi`), `connectivityMonitorProvider`, `backgroundWorkSchedulerProvider`, `syncEngineProvider` (db + api + `tokenStoreProvider.deviceId`), `syncSchedulerProvider`, `syncStatusProvider`, `syncDetailsProvider`, `offlineStreamProvider` + `offlineProvider` (bool, false until the monitor answers).

### Widgets and copy
- `SyncStatusPill`: new `SyncState.syncing` (info colour, cloud-sync icon, `syncSyncing`).
- `widgets/sync_live.dart`: `SyncStatusPillLive({onTap})` over `syncStatusProvider`; `OfflineBannerLive` over `offlineProvider`.
- `widgets/sync_details_screen.dart`: A64 `SyncDetailsScreen` (status card with pill, last sync in IST, transport error + next attempt, "Sync now" with spinner; empty state; "Needs attention (n)" with Retry all, per-item error detail, Retry / Discard; "Waiting to sync (n)" with photo-upload caption and per-item "Waiting for the photo to upload"). Keys `sync-now`, `sync-retry-all`, `sync-retry-<opId>`, `sync-discard-<opId>`.
- ARB: +26 keys in en/te/kn/hi/mr (`syncSyncing`, `syncDetailsTitle`, `syncNow`, `syncLastSync`, `syncNeverSynced`, `syncAllDone`, `syncAllDoneHelp`, `syncPendingSection`, `syncFailedSection`, `syncWaitingForPhoto`, `syncPhotoUploads`, `syncTransportError`, `syncNextAttempt`, `syncItemTitle`, `syncAction*`, `syncEntity*`, `syncSavedAt`, `syncRejectedDefault`, `syncRetryAll`, `syncDiscard`).

### Agent app
- `router.dart`: `AppRoutes.syncDetails = '/settings/sync'` nested under settings → `SyncDetailsScreen`.
- `screens/settings_screen.dart` (A63): sync row with `SyncStatusPillLive`, tertiary "Sync now", chevron to A64.
- `main.dart`: `Workmanager().initialize(callbackDispatcher)` (top-level `@pragma('vm:entry-point')` running `SyncScheduler.runBackgroundTask` over `openAppDatabase()` + `SecureTokenStore` + `HttpSyncApi`), overrides `syncApiProvider` (`HttpSyncApi` with `HttpAuthApi.refresh`), `connectivityMonitorProvider` (`PlusConnectivityMonitor`), `backgroundWorkSchedulerProvider` (`WorkmanagerSyncScheduler`), starts `syncSchedulerProvider` before `runApp` via a `ProviderContainer` + `UncontrolledProviderScope`.
- `pubspec.yaml`: `workmanager`. Core `pubspec.yaml`: `async`, `connectivity_plus`; dev `sqlite3` (migration test).

### Design
- `design/screens/A64.md` (new), `design/components/SyncStatusPill.md` (syncing variant, live wrapper), `design/components/OfflineBanner.md` (live wrapper).

## Decisions and assumptions

- **One op per entity per `/v1/sync` call.** The contract allows 200 ops per call, but a create followed by an update of the same row in one batch would need the client to guess the version the server assigns. Sending the earliest queued op per entity per call and refreshing `base_version` from the local row after each `applied` keeps the server's optimistic check meaningful with any server implementation; FIFO per entity is guaranteed by `seq`. A 300-op backlog after 72 h drains in three or four calls.
- **Blocking behind a rejection.** Later queued ops for an entity whose earlier op was rejected are held (not sent) until the user edits (the edit folds into the rejected op) or discards it; otherwise the server would see an update on a row it never created.
- **`duplicate` = success**, including after a lost response (`loseResponseNext` in the fake): the resend is answered `duplicate`, the row is marked clean, nothing is applied twice.
- **Pull vs dirty rows.** A pulled change never overwrites a row with queued ops; the push settles it (`conflict` → server wins, local replaced).
- **Rule table.** `LocalEntities.conflictRules` mirrors the server (`last_writer_wins` farmer/farm/crop_plot, `append_only` consent, `server_wins` khata/payment for M3) but the client does not arbitrate: it applies the response. Kept as documentation and for future UI hints.
- **Pill semantics.** `failed` only when the user has to act (rejected op, locally failed upload). A transport failure keeps `pending`: the OfflineBanner explains the network and the engine retries on its own; A64 shows the error and the next attempt.
- **Consent `version`** in the payload is the consent text version (string) and is stored as `consent_version`; the int row version comes from the envelope.
- **Timestamps.** Drift `dateTime()` returns local-time values; `SyncStore.state()` normalises to UTC so the engine, tests and A64 compare instants consistently. `client_ts` is stored as ISO-8601 text.
- **`sqlite3` dev dependency** lets the migration test create a genuine v1 file (Drift's schema-verifier tooling would need generated schema snapshots for every version; this is simpler for a two-version history).
- **Encryption**: not in this change (SEC-024, M5). The `DatabaseOpener` seam is the only touch point.
- **Photo file lifecycle**: the uploader re-reads and re-hashes the file; a missing or changed file fails the upload and rejects the dependent op with `upload_failed` so the officer sees it on A64. Deleting the local file after `complete` is left to the screens that own the photo (FA-012 / FA-015).

## Screenshots / goldens (UI changes)

New: `packages/core/test/goldens/goldens/a64_sync_details_{light,sunlight}.png` (failed pill, last sync, transport error + next attempt, one rejected item with Retry / Discard, two pending items incl. one waiting for a photo), `a64_sync_details_empty_{light,sunlight}.png`. Regenerated: `sync_status_pill_{light,sunlight}.png` (fourth pill "Syncing…"). Other 64 goldens unchanged.

## Migration notes

- [x] Drift migration v1 → v2 (additive: new tables and indexes; `kv` untouched) with a test from a real v1 file
- [ ] Alembic migration — n/a here (API loop)
- [ ] RLS policy + tenant_id — n/a (device-local DB; rows are already tenant-scoped by the signed-in user)
- [x] Data backfill / retention: terminal outbox rows purged after 7 days; uploads rows kept until the app deletes the photo (owner screens)
- [x] Dependencies: `connectivity_plus` (Android plugin), `async` (pure Dart), `sqlite3` (dev only), `workmanager` in the agent app (already in core)

## Test evidence

`cd apps/mobile && ./tool/check.sh` — green: pub get, tokens/l10n/drift codegen, no untranslated messages, `dart format` clean, `flutter analyze` zero issues in core/agent/farmer, string lint clean (13 self-tests), `flutter test`: core **283 passed** (202 before; +81), agent **11** (+2), farmer 9.

New tests:
- `test/db/migration_test.dart` (3) — v1 file → v2 keeps settings, adds tables + indexes, accepts writes; fresh DB at v2; re-open does not re-run.
- `test/sync/outbox_test.dart` (10) — create → dirty row + queued op with seq/clientTs/payload; update merges and orders; base_version from the server version; delete tombstone; unknown entity refused; farm boundary/photos round trip; crop plot + consent fields; op waits for a queued photo and not for a completed one; edit after rejection folds into the same op_id; placeholder helpers.
- `test/sync/sync_engine_push_test.dart` (14) — applied; duplicate after a lost response (exactly once); conflict replaces the row / deletes when server is null; rejected kept with error, no auto-retry, retry after edit; `retry()` / `discard()`; FIFO per entity with batch cap 4 (base_version 0,1,2 seen by the server); never more than 200 ops per call (250 → 200 + 50); op waits for its upload and carries the `blob_uri`; upload transport failure holds the op; locally failed upload rejects the op; `sending` rows recovered after a crash; empty results do not loop; delete removes the row; terminal ops purged.
- `test/sync/sync_engine_pull_test.dart` (5) — upsert / update / delete known entities with cursor persistence; `has_more` loop (250 changes, 3 calls, cursors null/100/200); dirty rows not clobbered; village / crop / unknown → `synced_refs` (+ update, delete); no-op pull keeps the cursor.
- `test/sync/backoff_test.dart` (9) — ceilings 1…256, 300; jitter range; reproducible with a seed; custom base/cap; engine records error + next window; automatic runs skip inside the window, manual runs do not; schedule 1, 2, 4 … 300 s across 12 failures; success resets; rejected ops do not trigger backoff.
- `test/sync/chunked_uploader_test.dart` (6) — 700 KB in three chunks; resume after restart with `[0, 1]` received (only 2, 3 sent again, same session); expired session re-init; missing file / changed file → failed; default file reader.
- `test/sync/offline_72h_test.dart` (1) — the NF-002 scenario described in progress.md (300 ops, 3 days, 2 restarts, backoff-bounded ticks, lost first response, all applied exactly once in order, local rows clean).
- `test/sync/http_sync_api_test.dart` (7) — request body / headers, response parsing incl. rejected + conflict, 401 → refresh → retry, expired token refreshed up front, auth failures, 5xx / network → transport, upload endpoints.
- `test/sync/sync_scheduler_test.dart` (5) — periodic registration + sync when online; offline start then reconnect → sync + one-off; no re-trigger while staying online; reconnect ignores the backoff window; `runBackgroundTask` outcomes.
- `test/widgets/sync_status_pill_test.dart` (+1 syncing), `test/widgets/sync_live_test.dart` (5) — engine round trip synced → pending → syncing (gated API) → synced, failed after rejection + tap, scripted statuses, banner follows the monitor, `offlineProvider` default.
- `test/widgets/sync_details_screen_test.dart` (10) — empty; pending → failed with error detail → retry after edit → synced; Retry / Discard per item; Retry all; transport error copy + next attempt; photo upload line; te/kn/hi/mr.
- `test/goldens/sync_details_golden_test.dart` (4).
- agent `test/sync_route_test.dart` (2) — A63 row → A64 → Sync now → back; A63 "Sync now".

## Checklist

- [x] Tests written first; acceptance criteria covered (72-hour offline then sync with zero loss; idempotency keys; 256 KB resumable uploads; backoff; conflict = server wins)
- [ ] Role + tenant authorisation tests for every new endpoint — n/a on mobile (API loop)
- [x] Strings externalised (26 keys × 5 languages); timestamps UTC (`client_ts` ISO-8601 Z, DB values normalised to UTC)
- [x] No secrets in code, fixtures or logs (tokens only via `TokenStore`; errors stored as `{code, detail}`)
- [x] Location only on duty: nothing here reads location; farm boundaries are payload data captured by the wizard
- [x] docs/progress.md updated (FA-025, NF-002, NF-003 mobile half; FA-012 next step; SEC-024 seam)

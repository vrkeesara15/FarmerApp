import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:async/async.dart' show StreamGroup;
import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart' show immutable, listEquals;

import '../db/app_database.dart';
import '../widgets/sync_status_pill.dart' show SyncState;
import 'backoff.dart';
import 'chunked_uploader.dart';
import 'local_entities.dart';
import 'outbox.dart';
import 'sync_api.dart';
import 'sync_models.dart';
import 'sync_store.dart';

/// Injected wall clock (UTC).
typedef Clock = DateTime Function();

/// What the pill shows.
enum SyncStatusKind {
  /// Nothing queued, nothing failed.
  synced,

  /// Items are waiting for the network.
  pending,

  /// Items need the user (rejected ops, failed uploads).
  failed,

  /// A sync is running right now.
  syncing,
}

/// `synced | pending(n) | failed(n) | syncing` for [SyncStatusPill].
@immutable
class SyncStatus {
  /// Creates the status.
  const SyncStatus(this.kind, {this.pending = 0, this.failed = 0});

  /// Nothing to do.
  static const SyncStatus synced = SyncStatus(SyncStatusKind.synced);

  /// Derives the kind from counts and the running flag.
  factory SyncStatus.from(SyncCounts counts, {required bool syncing}) {
    final kind = syncing
        ? SyncStatusKind.syncing
        : counts.failed > 0
        ? SyncStatusKind.failed
        : counts.pending > 0
        ? SyncStatusKind.pending
        : SyncStatusKind.synced;
    return SyncStatus(kind, pending: counts.pending, failed: counts.failed);
  }

  /// The kind.
  final SyncStatusKind kind;

  /// Items still to reach the server.
  final int pending;

  /// Items needing attention.
  final int failed;

  /// The pill variant for this status.
  SyncState get pillState => switch (kind) {
    SyncStatusKind.synced => SyncState.synced,
    SyncStatusKind.pending => SyncState.pending,
    SyncStatusKind.failed => SyncState.failed,
    SyncStatusKind.syncing => SyncState.syncing,
  };

  @override
  bool operator ==(Object other) =>
      other is SyncStatus &&
      other.kind == kind &&
      other.pending == pending &&
      other.failed == failed;

  @override
  int get hashCode => Object.hash(kind, pending, failed);

  @override
  String toString() =>
      'SyncStatus.${kind.name}(pending: $pending, '
      'failed: $failed)';
}

/// One outbox item as shown on A64.
@immutable
class SyncItem {
  /// Creates the item.
  const SyncItem({
    required this.opId,
    required this.entity,
    required this.action,
    required this.entityId,
    required this.clientTs,
    required this.state,
    this.error,
    this.waitingForUpload = false,
    this.attempts = 0,
  });

  /// Idempotency key.
  final String opId;

  /// Entity wire name.
  final String entity;

  /// Create, update or delete.
  final SyncAction action;

  /// Row id.
  final String entityId;

  /// When it was queued.
  final DateTime clientTs;

  /// Outbox state.
  final OutboxState state;

  /// Last error (rejected ops).
  final SyncError? error;

  /// Held until a photo upload completes.
  final bool waitingForUpload;

  /// Push attempts.
  final int attempts;

  @override
  bool operator ==(Object other) =>
      other is SyncItem &&
      other.opId == opId &&
      other.state == state &&
      other.error == error &&
      other.waitingForUpload == waitingForUpload &&
      other.attempts == attempts;

  @override
  int get hashCode => Object.hash(opId, state, error, waitingForUpload);
}

/// Everything A64 shows.
@immutable
class SyncDetails {
  /// Creates the details.
  const SyncDetails({
    required this.status,
    required this.pending,
    required this.failed,
    this.lastSyncAt,
    this.lastError,
    this.nextAttemptAt,
    this.pendingUploads = 0,
    this.failedUploads = 0,
  });

  /// Pill status.
  final SyncStatus status;

  /// Queued / sending ops in push order.
  final List<SyncItem> pending;

  /// Rejected ops.
  final List<SyncItem> failed;

  /// Last fully successful sync.
  final DateTime? lastSyncAt;

  /// Last transport failure.
  final SyncError? lastError;

  /// Next automatic attempt after a failure.
  final DateTime? nextAttemptAt;

  /// Photos still uploading.
  final int pendingUploads;

  /// Photos that failed locally.
  final int failedUploads;

  @override
  bool operator ==(Object other) =>
      other is SyncDetails &&
      other.status == status &&
      listEquals(other.pending, pending) &&
      listEquals(other.failed, failed) &&
      other.lastSyncAt == lastSyncAt &&
      other.lastError == lastError &&
      other.nextAttemptAt == nextAttemptAt &&
      other.pendingUploads == pendingUploads &&
      other.failedUploads == failedUploads;

  @override
  int get hashCode => Object.hash(
    status,
    Object.hashAll(pending),
    Object.hashAll(failed),
    lastSyncAt,
    lastError,
    nextAttemptAt,
    pendingUploads,
    failedUploads,
  );
}

/// What one [SyncEngine.syncNow] did.
@immutable
class SyncReport {
  /// Creates the report.
  const SyncReport({
    this.skipped = false,
    this.calls = 0,
    this.pushed = 0,
    this.applied = 0,
    this.duplicate = 0,
    this.conflict = 0,
    this.rejected = 0,
    this.pulled = 0,
    this.uploads = 0,
    this.error,
  });

  /// Backoff window not elapsed (or another sync was running).
  final bool skipped;

  /// `/v1/sync` calls made.
  final int calls;

  /// Ops sent.
  final int pushed;

  /// Ops applied.
  final int applied;

  /// Ops the server had already applied.
  final int duplicate;

  /// Ops the server overrode.
  final int conflict;

  /// Ops the server rejected.
  final int rejected;

  /// Changes pulled.
  final int pulled;

  /// Uploads completed.
  final int uploads;

  /// The transport failure that ended the run, if any.
  final SyncTransportException? error;

  /// Everything queued reached the server (no transport error).
  bool get ok => error == null && !skipped;
}

/// Offline-first sync engine (FA-025, NF-002, NF-003).
///
/// [syncNow] runs, in order: completed-upload drain (ops waiting on a photo
/// get their `blob_uri`), pending uploads, then `/v1/sync` in batches of at
/// most [batchSize] ops — one op per entity per batch so the server sees
/// each entity's ops in FIFO order with a fresh `base_version` — applying
/// results per the contract and pulling changes until `has_more` is false.
/// Transport failures back off exponentially (1 s → 5 min, jittered);
/// rejected ops are never retried automatically.
class SyncEngine {
  /// Creates the engine over [db] and [api]. `deviceId` is sent with every
  /// sync; [clock] and [random] are injected in tests.
  SyncEngine({
    required AppDatabase db,
    required this.api,
    required this._deviceId,
    Clock? clock,
    Random? random,
    this.backoff = const Backoff(),
    FileReader? readFile,
    this.batchSize = maxOpsPerSync,
    this.keepTerminalFor = const Duration(days: 7),
  }) : store = SyncStore(db),
       _now = clock ?? _utcNow,
       _random = random ?? Random() {
    uploader = ChunkedUploader(store: store, api: api, readFile: readFile);
  }

  /// Store shared with the [Outbox].
  final SyncStore store;

  /// Transport.
  final SyncApi api;

  /// Retry schedule for transport failures.
  final Backoff backoff;

  /// Ops per `/v1/sync` call (≤ 200).
  final int batchSize;

  /// How long applied ops stay in the outbox for A64 history.
  final Duration keepTerminalFor;

  /// Photo uploader.
  late final ChunkedUploader uploader;

  final Future<String> Function() _deviceId;
  final Clock _now;
  final Random _random;
  final StreamController<void> _running = StreamController<void>.broadcast();
  Future<SyncReport>? _inFlight;

  static DateTime _utcNow() => DateTime.now().toUtc();

  /// A sync is running.
  bool get isSyncing => _inFlight != null;

  /// Current status.
  Future<SyncStatus> status() async =>
      SyncStatus.from(await store.counts(), syncing: isSyncing);

  /// Status now and after every relevant change.
  Stream<SyncStatus> watchStatus() => _watch(status);

  /// Details now and after every relevant change.
  Stream<SyncDetails> watchDetails() => _watch(details);

  Stream<T> _watch<T>(Future<T> Function() load) async* {
    yield await load();
    final changes = StreamGroup.merge<Object?>(<Stream<Object?>>[
      store.db.tableUpdates(),
      _running.stream,
    ]);
    await for (final _ in changes) {
      yield await load();
    }
  }

  /// A64 view.
  Future<SyncDetails> details() async {
    final counts = await store.counts();
    final open = await store.openOps();
    final st = await store.state();
    SyncItem item(OutboxRow o) => SyncItem(
      opId: o.opId,
      entity: o.entity,
      action: SyncAction.parse(o.action),
      entityId: o.entityId,
      clientTs: DateTime.parse(o.clientTs).toUtc(),
      state: OutboxState.parse(o.state),
      error: SyncStore.errorOf(o),
      waitingForUpload: o.dependsOnUploadId != null,
      attempts: o.attempts,
    );
    return SyncDetails(
      status: SyncStatus.from(counts, syncing: isSyncing),
      pending: <SyncItem>[
        for (final o in open)
          if (o.state != 'rejected') item(o),
      ],
      failed: <SyncItem>[
        for (final o in open)
          if (o.state == 'rejected') item(o),
      ],
      lastSyncAt: st.lastSyncAt?.toUtc(),
      lastError: st.lastError == null
          ? null
          : SyncError.fromJson(jsonDecode(st.lastError!)),
      nextAttemptAt: st.nextAttemptAt?.toUtc(),
      pendingUploads: counts.pendingUploads,
      failedUploads: counts.failedUploads,
    );
  }

  /// Completes when no run is in flight (a remote wipe waits for the run
  /// that saw the wipe order before closing the database, SEC-025).
  Future<void> whenIdle() async {
    final running = _inFlight;
    if (running == null) return;
    try {
      await running;
    } on Object {
      // The run's own failure is not the caller's concern here.
    }
  }

  /// Pushes and pulls. With [force] false the run is skipped while the
  /// backoff window of the last failure has not elapsed (periodic and
  /// background triggers); user-initiated syncs pass true.
  Future<SyncReport> syncNow({bool force = true}) {
    final running = _inFlight;
    if (running != null) return running;
    final future = _run(force: force);
    _inFlight = future;
    _running.add(null);
    return future.whenComplete(() {
      _inFlight = null;
      _running.add(null);
    });
  }

  Future<SyncReport> _run({required bool force}) async {
    final startState = await store.state();
    final next = startState.nextAttemptAt;
    if (!force && next != null && _now().isBefore(next)) {
      return const SyncReport(skipped: true);
    }
    var calls = 0;
    var pushed = 0;
    var applied = 0;
    var duplicate = 0;
    var conflict = 0;
    var rejected = 0;
    var pulled = 0;
    var uploads = 0;
    try {
      await store.requeueSending();
      // 1. uploads, then release the ops that waited for them.
      for (final row in await store.uploadsToSend()) {
        final done = await uploader.upload(row);
        if (done.state == UploadState.complete.name) uploads += 1;
      }
      await _drainUploadDependants();

      // 2 + 3. push in batches, pull until has_more is false.
      final deviceId = await _deviceId();
      var hasMore = true;
      while (true) {
        final batch = await store.nextBatch(limit: batchSize);
        if (batch.isEmpty && !hasMore) break;
        final ops = <SyncOp>[for (final row in batch) await _prepare(row)];
        await store.markSending(<String>[for (final op in ops) op.opId]);
        final SyncResponse response;
        try {
          response = await api.sync(
            SyncRequest(
              deviceId: deviceId,
              cursor: (await store.state()).cursor,
              ops: ops,
            ),
          );
        } on SyncTransportException {
          await store.requeueSending();
          rethrow;
        }
        calls += 1;
        pushed += ops.length;
        final tally = await _applyResults(ops, response.results);
        applied += tally[SyncResultStatus.applied]!;
        duplicate += tally[SyncResultStatus.duplicate]!;
        conflict += tally[SyncResultStatus.conflict]!;
        rejected += tally[SyncResultStatus.rejected]!;
        pulled += await _applyChanges(response.changes);
        await store.saveState(
          SyncStatesCompanion(cursor: Value<String?>(response.cursor)),
        );
        hasMore = response.hasMore;
        final answered = tally.values.fold<int>(0, (a, b) => a + b);
        if (ops.isNotEmpty && answered == 0) {
          // The server ignored the whole batch; do not spin.
          throw const SyncTransportException(
            'server returned no results for the batch',
            code: 'empty_results',
          );
        }
      }
      final now = _now();
      await store.saveState(
        SyncStatesCompanion(
          lastSyncAt: Value<DateTime?>(now),
          lastError: const Value<String?>(null),
          attempts: const Value<int>(0),
          nextAttemptAt: const Value<DateTime?>(null),
        ),
      );
      await store.purgeTerminal(before: now.subtract(keepTerminalFor));
      return SyncReport(
        calls: calls,
        pushed: pushed,
        applied: applied,
        duplicate: duplicate,
        conflict: conflict,
        rejected: rejected,
        pulled: pulled,
        uploads: uploads,
      );
    } on SyncTransportException catch (e) {
      final attempts = (await store.state()).attempts + 1;
      final delay = backoff.delay(attempts, random: _random);
      await store.saveState(
        SyncStatesCompanion(
          lastError: Value<String?>(jsonEncode(e.toError().toJson())),
          attempts: Value<int>(attempts),
          nextAttemptAt: Value<DateTime?>(_now().add(delay)),
        ),
      );
      return SyncReport(
        calls: calls,
        pushed: pushed,
        applied: applied,
        duplicate: duplicate,
        conflict: conflict,
        rejected: rejected,
        pulled: pulled,
        uploads: uploads,
        error: e,
      );
    }
  }

  /// The op as sent: `base_version` refreshed from the local row so a
  /// queued update following a just-applied create carries the version the
  /// server assigned; a farmer create carrying an expired
  /// `phone_verification_token` sends without it (FA-012: the farmer syncs
  /// as unverified rather than being rejected 30 minutes after capture).
  Future<SyncOp> _prepare(OutboxRow row) async {
    final op = SyncStore.toOp(row);
    if (op.action == SyncAction.create) {
      if (op.entity == SyncEntities.farmer &&
          op.payload.containsKey(phoneVerificationTokenKey)) {
        final expires = op.payload[phoneVerificationExpiresKey];
        final expiry = expires is String ? DateTime.tryParse(expires) : null;
        final expired = expiry != null && !_now().isBefore(expiry.toUtc());
        final payload = Map<String, Object?>.from(op.payload)
          ..remove(phoneVerificationExpiresKey);
        if (expired) {
          payload
            ..remove(phoneVerificationTokenKey)
            ..['phone_verified'] = false;
          await store.setPayload(
            op.opId,
            payload,
            dependsOnUploadId: row.dependsOnUploadId,
          );
          await store.entities.merge(op.entity, op.entityId, <String, Object?>{
            'phone_verified': false,
          }, now: _now());
        }
        return op.copyWith(payload: payload);
      }
      return op;
    }
    final local = await store.entities.read(op.entity, op.entityId);
    final base = local?.version ?? op.baseVersion;
    if (base != op.baseVersion) await store.setBaseVersion(op.opId, base);
    return op.copyWith(baseVersion: base);
  }

  Future<Map<SyncResultStatus, int>> _applyResults(
    List<SyncOp> ops,
    List<SyncOpResult> results,
  ) async {
    final tally = <SyncResultStatus, int>{
      for (final s in SyncResultStatus.values) s: 0,
    };
    final byId = <String, SyncOpResult>{for (final r in results) r.opId: r};
    final now = _now();
    for (final op in ops) {
      final result = byId[op.opId];
      if (result == null) {
        await store.requeue(op.opId);
        continue;
      }
      tally[result.status] = tally[result.status]! + 1;
      final stillDirty =
          await store.activeOpsFor(op.entityId, excludingOpId: op.opId) > 0;
      switch (result.status) {
        case SyncResultStatus.applied:
        case SyncResultStatus.duplicate:
          await store.setResult(
            op.opId,
            result.status == SyncResultStatus.applied
                ? OutboxState.applied
                : OutboxState.duplicate,
          );
          if (op.action == SyncAction.delete) {
            await store.entities.delete(op.entity, op.entityId);
          } else {
            // Server-computed fields echoed with an applied op (a
            // `location_batch` answers `{accepted, rejected}`) are kept on
            // the local row.
            final echo = result.server;
            if (echo != null && echo.isNotEmpty) {
              await store.entities.merge(
                op.entity,
                op.entityId,
                echo,
                now: now,
              );
            }
            await store.entities.setFlags(
              op.entity,
              op.entityId,
              now: now,
              version: result.version,
              dirty: stillDirty,
            );
          }
        case SyncResultStatus.conflict:
          await store.setResult(
            op.opId,
            OutboxState.conflict,
            error: result.error,
          );
          final server = result.server;
          if (server == null) {
            await store.entities.delete(op.entity, op.entityId);
          } else {
            await store.entities.write(
              op.entity,
              op.entityId,
              server,
              version:
                  result.version ?? (server['version'] as num?)?.toInt() ?? 0,
              dirty: stillDirty,
              now: now,
            );
          }
        case SyncResultStatus.rejected:
          final error = result.error ?? const SyncError('rejected');
          await store.setResult(op.opId, OutboxState.rejected, error: error);
          await store.entities.markRejected(
            op.entity,
            op.entityId,
            error,
            now: now,
          );
      }
    }
    return tally;
  }

  Future<int> _applyChanges(List<SyncChange> changes) async {
    final now = _now();
    for (final change in changes) {
      if (LocalEntities.isKnown(change.entity)) {
        if (change.action == SyncAction.delete) {
          await store.entities.delete(change.entity, change.entityId);
          continue;
        }
        final local = await store.entities.read(change.entity, change.entityId);
        // A dirty row has queued ops; the push settles it (server wins on
        // conflict), so the pulled copy is not allowed to clobber the edit.
        if (local != null && local.dirty) continue;
        await store.entities.write(
          change.entity,
          change.entityId,
          change.data,
          version: change.version,
          dirty: false,
          now: now,
        );
      } else if (change.action == SyncAction.delete) {
        await store.entities.deleteRef(change.entity, change.entityId);
      } else {
        await store.entities.writeRef(
          change.entity,
          change.entityId,
          change.data,
          version: change.version,
          now: now,
        );
        // ST-007 / FA-020 A56: the cluster head approved a blocked credit
        // sale -> resend it with the approval (pushed in this same run).
        if (change.entity == SyncEntities.creditApprovalRequest &&
            change.data['status'] == 'approved') {
          await store.requeueApprovedCredit(change.entityId);
        }
      }
    }
    return changes.length;
  }

  /// Ops waiting on uploads: substitute `blob_uri`s once every referenced
  /// upload is complete; fail the op when an upload failed for good.
  Future<void> _drainUploadDependants() async {
    final waiting = (await store.opsIn(<String>['queued']))
        .where((o) => o.dependsOnUploadId != null);
    for (final row in waiting) {
      final payload = SyncStore.payloadOf(row);
      final refs = uploadRefsIn(payload);
      final uris = <String, String>{};
      String? blocking;
      SyncError? failure;
      for (final id in refs) {
        final up = await store.upload(id);
        if (up == null) {
          failure = SyncError('upload_missing', 'photo $id was not queued');
          break;
        }
        if (up.state == UploadState.complete.name && up.blobUri != null) {
          uris[id] = up.blobUri!;
        } else if (up.state == UploadState.failed.name) {
          failure = SyncError(
            'upload_failed',
            up.lastError ?? 'photo $id could not be uploaded',
          );
          break;
        } else {
          blocking ??= id;
        }
      }
      if (failure != null) {
        await store.setResult(row.opId, OutboxState.rejected, error: failure);
        continue;
      }
      final substituted = Map<String, Object?>.from(
        substituteUploadRefs(payload, uris)! as Map,
      );
      await store.setPayload(
        row.opId,
        substituted,
        dependsOnUploadId: blocking,
      );
      if (blocking == null) {
        // Keep the typed row in step with what will be sent.
        await store.entities.merge(
          row.entity,
          row.entityId,
          substituted,
          now: _now(),
        );
      }
    }
  }

  /// Requeues a rejected op (A64 retry; the user edited the item first).
  Future<void> retry(String opId) => store.requeue(opId);

  /// Requeues a failed upload.
  Future<void> retryUpload(String uploadId) => store.requeueUpload(uploadId);

  /// Requeues every rejected op and failed upload.
  Future<void> retryAll() async {
    for (final op in await store.opsIn(<String>['rejected'])) {
      await store.requeue(op.opId);
    }
    for (final up in await store.uploadsIn(<String>['failed'])) {
      await store.requeueUpload(up.id);
    }
  }

  /// Drops an op the user gave up on; the local row keeps its last state
  /// but is no longer dirty unless other ops reference it.
  Future<void> discard(String opId) async {
    final rows = await store.opsIn(OutboxState.values.map((s) => s.name));
    final row = rows.where((r) => r.opId == opId).firstOrNull;
    if (row == null) return;
    await store.discard(opId);
    final stillDirty = await store.activeOpsFor(row.entityId) > 0;
    if (row.action == SyncAction.create.name) {
      await store.entities.delete(row.entity, row.entityId);
    } else {
      await store.entities.setFlags(
        row.entity,
        row.entityId,
        now: _now(),
        dirty: stillDirty,
      );
    }
  }

  /// Releases the status stream.
  Future<void> dispose() => _running.close();
}

import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart' show immutable;

import '../db/app_database.dart';
import 'local_entities.dart';
import 'sync_models.dart';

/// Outbox / upload counts behind the status pill.
@immutable
class SyncCounts {
  /// Creates the counts.
  const SyncCounts({
    required this.queuedOps,
    required this.rejectedOps,
    required this.waitingOps,
    required this.pendingUploads,
    required this.failedUploads,
  });

  /// Ops in `queued` or `sending`.
  final int queuedOps;

  /// Ops in `rejected`.
  final int rejectedOps;

  /// Queued ops waiting on an upload (subset of [queuedOps]).
  final int waitingOps;

  /// Uploads in `pending` or `uploading`.
  final int pendingUploads;

  /// Uploads in `failed`.
  final int failedUploads;

  /// Everything still to reach the server.
  int get pending => queuedOps + pendingUploads;

  /// Everything needing the user's attention.
  int get failed => rejectedOps + failedUploads;
}

/// Data access for the outbox, uploads and sync bookkeeping tables.
class SyncStore {
  /// Creates the store over [db].
  SyncStore(this.db) : entities = LocalEntities(db);

  /// The database.
  final AppDatabase db;

  /// Typed local rows.
  final LocalEntities entities;

  static const List<String> _activeStates = <String>['queued', 'sending'];

  /// Decodes the JSON payload of an outbox row.
  static Map<String, Object?> payloadOf(OutboxRow row) =>
      Map<String, Object?>.from(jsonDecode(row.payload) as Map);

  /// Decodes the stored error of an outbox row.
  static SyncError? errorOf(OutboxRow row) => row.lastError == null
      ? null
      : SyncError.fromJson(jsonDecode(row.lastError!));

  /// Decodes the acknowledged chunk list of an upload row.
  static List<int> receivedOf(Upload row) =>
      (jsonDecode(row.receivedChunks) as List<Object?>)
          .map((c) => (c! as num).toInt())
          .toList(growable: false);

  /// The op as it goes on the wire.
  static SyncOp toOp(OutboxRow row) => SyncOp(
    opId: row.opId,
    entity: row.entity,
    action: SyncAction.parse(row.action),
    entityId: row.entityId,
    baseVersion: row.baseVersion,
    payload: payloadOf(row),
    clientTs: DateTime.parse(row.clientTs).toUtc(),
  );

  // --- outbox -------------------------------------------------------------

  /// Appends [op] to the outbox in queued state.
  Future<void> insertOp(SyncOp op, {String? dependsOnUploadId}) {
    return db.transaction(() async {
      final maxSeq = db.outboxTable.seq.max();
      final row = await (db.selectOnly(
        db.outboxTable,
      )..addColumns(<Expression<Object>>[maxSeq])).getSingle();
      final seq = (row.read(maxSeq) ?? 0) + 1;
      await db
          .into(db.outboxTable)
          .insert(
            OutboxTableCompanion.insert(
              opId: op.opId,
              seq: seq,
              entity: op.entity,
              action: op.action.name,
              entityId: op.entityId,
              baseVersion: Value<int>(op.baseVersion),
              payload: jsonEncode(op.payload),
              clientTs: op.clientTs.toUtc().toIso8601String(),
              dependsOnUploadId: Value<String?>(dependsOnUploadId),
            ),
          );
    });
  }

  /// The earliest non-terminal op for [entityId], or null.
  Future<OutboxRow?> firstOpenOp(String entityId) {
    return (db.select(db.outboxTable)
          ..where(
            (t) =>
                t.entityId.equals(entityId) &
                t.state.isIn(<String>['queued', 'sending', 'rejected']),
          )
          ..orderBy(<OrderingTerm Function($OutboxTableTable)>[
            (t) => OrderingTerm.asc(t.seq),
          ])
          ..limit(1))
        .getSingleOrNull();
  }

  /// Ops in [states], in push order.
  Future<List<OutboxRow>> opsIn(Iterable<String> states) {
    return (db.select(db.outboxTable)
          ..where((t) => t.state.isIn(states))
          ..orderBy(<OrderingTerm Function($OutboxTableTable)>[
            (t) => OrderingTerm.asc(t.seq),
          ]))
        .get();
  }

  /// The next batch to push: queued ops in seq order, at most one per
  /// entity id, none behind a blocked op (sending, rejected or waiting on
  /// an upload) for the same entity, at most [limit].
  Future<List<OutboxRow>> nextBatch({int limit = maxOpsPerSync}) async {
    final open = await opsIn(<String>['queued', 'sending', 'rejected']);
    final taken = <String>{};
    final batch = <OutboxRow>[];
    for (final op in open) {
      if (!taken.add(op.entityId)) continue;
      if (op.state != 'queued' || op.dependsOnUploadId != null) continue;
      batch.add(op);
      if (batch.length >= limit) break;
    }
    return batch;
  }

  /// Marks [opIds] as sending and bumps their attempts.
  Future<void> markSending(List<String> opIds) {
    if (opIds.isEmpty) return Future<void>.value();
    return db.transaction(() async {
      for (final id in opIds) {
        await (db.update(
          db.outboxTable,
        )..where((t) => t.opId.equals(id))).write(
          OutboxTableCompanion(
            state: const Value<String>('sending'),
            attempts: Value<int>(await _attempts(id) + 1),
          ),
        );
      }
    });
  }

  Future<int> _attempts(String opId) async {
    final row = await (db.select(
      db.outboxTable,
    )..where((t) => t.opId.equals(opId))).getSingle();
    return row.attempts;
  }

  /// Rewrites the base version an op will be sent with.
  Future<void> setBaseVersion(String opId, int baseVersion) {
    return (db.update(db.outboxTable)..where((t) => t.opId.equals(opId))).write(
      OutboxTableCompanion(baseVersion: Value<int>(baseVersion)),
    );
  }

  /// Records the server's answer for an op.
  Future<void> setResult(String opId, OutboxState state, {SyncError? error}) {
    return (db.update(db.outboxTable)..where((t) => t.opId.equals(opId))).write(
      OutboxTableCompanion(
        state: Value<String>(state.name),
        lastError: Value<String?>(
          error == null ? null : jsonEncode(error.toJson()),
        ),
      ),
    );
  }

  /// Puts an op back in the queue (after an edit, a manual retry, or a
  /// request that never completed).
  Future<void> requeue(String opId, {Map<String, Object?>? payload}) {
    return (db.update(db.outboxTable)..where((t) => t.opId.equals(opId))).write(
      OutboxTableCompanion(
        state: const Value<String>('queued'),
        lastError: const Value<String?>(null),
        payload: payload == null
            ? const Value<String>.absent()
            : Value<String>(jsonEncode(payload)),
      ),
    );
  }

  /// Requeues everything left in `sending` (crash / kill mid-request).
  Future<int> requeueSending() {
    return (db.update(db.outboxTable)..where((t) => t.state.equals('sending')))
        .write(const OutboxTableCompanion(state: Value<String>('queued')));
  }

  /// Replaces the payload and the upload dependency of an op.
  Future<void> setPayload(
    String opId,
    Map<String, Object?> payload, {
    required String? dependsOnUploadId,
  }) {
    return (db.update(db.outboxTable)..where((t) => t.opId.equals(opId))).write(
      OutboxTableCompanion(
        payload: Value<String>(jsonEncode(payload)),
        dependsOnUploadId: Value<String?>(dependsOnUploadId),
      ),
    );
  }

  /// Removes an op (the user gave up on it).
  Future<void> discard(String opId) {
    return (db.delete(db.outboxTable)..where((t) => t.opId.equals(opId))).go();
  }

  /// Number of active ops for [entityId] other than [excludingOpId].
  Future<int> activeOpsFor(String entityId, {String? excludingOpId}) async {
    final count = db.outboxTable.opId.count();
    final query = db.selectOnly(db.outboxTable)
      ..addColumns(<Expression<Object>>[count])
      ..where(
        db.outboxTable.entityId.equals(entityId) &
            db.outboxTable.state.isIn(<String>[..._activeStates, 'rejected']) &
            (excludingOpId == null
                ? const Constant<bool>(true)
                : db.outboxTable.opId.equals(excludingOpId).not()),
      );
    final row = await query.getSingle();
    return row.read(count) ?? 0;
  }

  /// Deletes terminal ops queued before [before].
  Future<int> purgeTerminal({required DateTime before}) {
    return (db.delete(db.outboxTable)..where(
          (t) =>
              t.state.isIn(<String>['applied', 'duplicate', 'conflict']) &
              t.clientTs.isSmallerThanValue(before.toUtc().toIso8601String()),
        ))
        .go();
  }

  /// Ops in queued/sending/rejected order, for A64.
  Future<List<OutboxRow>> openOps() =>
      opsIn(<String>['queued', 'sending', 'rejected']);

  // --- uploads ------------------------------------------------------------

  /// Queues a file for upload.
  Future<Upload> insertUpload({
    required String id,
    required String filePath,
    required String sha256,
    required int sizeBytes,
    required String purpose,
    required DateTime now,
    String contentType = 'image/jpeg',
    int chunkSize = 256 * 1024,
  }) async {
    final row = Upload(
      id: id,
      filePath: filePath,
      sha256: sha256,
      sizeBytes: sizeBytes,
      chunkSize: chunkSize,
      receivedChunks: '[]',
      state: UploadState.pending.name,
      purpose: purpose,
      contentType: contentType,
      attempts: 0,
      createdAt: now,
    );
    await db.into(db.uploads).insert(row);
    return row;
  }

  /// Reads an upload row.
  Future<Upload?> upload(String id) =>
      (db.select(db.uploads)..where((t) => t.id.equals(id))).getSingleOrNull();

  /// Uploads still to send, oldest first.
  Future<List<Upload>> uploadsToSend() {
    return (db.select(db.uploads)
          ..where((t) => t.state.isIn(<String>['pending', 'uploading']))
          ..orderBy(<OrderingTerm Function($UploadsTable)>[
            (t) => OrderingTerm.asc(t.createdAt),
          ]))
        .get();
  }

  /// Patches an upload row.
  Future<void> patchUpload(String id, UploadsCompanion patch) {
    return (db.update(db.uploads)..where((t) => t.id.equals(id))).write(patch);
  }

  /// Puts a failed upload back in the queue.
  Future<void> requeueUpload(String id) => patchUpload(
    id,
    const UploadsCompanion(
      state: Value<String>('pending'),
      lastError: Value<String?>(null),
    ),
  );

  /// Uploads in [states].
  Future<List<Upload>> uploadsIn(Iterable<String> states) =>
      (db.select(db.uploads)..where((t) => t.state.isIn(states))).get();

  // --- bookkeeping --------------------------------------------------------

  /// Current counts.
  Future<SyncCounts> counts() async {
    final ops = await opsIn(<String>[..._activeStates, 'rejected']);
    final ups = await uploadsIn(<String>['pending', 'uploading', 'failed']);
    return SyncCounts(
      queuedOps: ops.where((o) => o.state != 'rejected').length,
      rejectedOps: ops.where((o) => o.state == 'rejected').length,
      waitingOps: ops
          .where((o) => o.state == 'queued' && o.dependsOnUploadId != null)
          .length,
      pendingUploads: ups.where((u) => u.state != 'failed').length,
      failedUploads: ups.where((u) => u.state == 'failed').length,
    );
  }

  /// The single bookkeeping row (defaults when never written).
  Future<SyncStateRow> state() async {
    final row = await (db.select(
      db.syncStates,
    )..where((t) => t.id.equals(1))).getSingleOrNull();
    if (row == null) return const SyncStateRow(id: 1, attempts: 0);
    // Drift hands back local-time DateTimes; the engine works in UTC.
    return row.copyWith(
      lastSyncAt: Value<DateTime?>(row.lastSyncAt?.toUtc()),
      nextAttemptAt: Value<DateTime?>(row.nextAttemptAt?.toUtc()),
    );
  }

  /// Writes bookkeeping fields.
  Future<void> saveState(SyncStatesCompanion patch) {
    return db
        .into(db.syncStates)
        .insertOnConflictUpdate(patch.copyWith(id: const Value<int>(1)));
  }
}

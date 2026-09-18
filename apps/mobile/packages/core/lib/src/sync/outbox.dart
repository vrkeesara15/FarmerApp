import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../auth/token_store.dart' show generateUuidV4;
import '../db/app_database.dart';
import '../photo/chunked_upload_planner.dart';
import 'local_entities.dart';
import 'sync_models.dart';
import 'sync_store.dart';

/// Collects the `upload:<id>` placeholders anywhere inside a JSON value.
Set<String> uploadRefsIn(Object? json) {
  final refs = <String>{};
  void walk(Object? v) {
    if (v is String && v.startsWith(uploadPlaceholderPrefix)) {
      refs.add(v.substring(uploadPlaceholderPrefix.length));
    } else if (v is Map) {
      v.values.forEach(walk);
    } else if (v is List) {
      v.forEach(walk);
    }
  }

  walk(json);
  return refs;
}

/// Replaces `upload:<id>` placeholders with the blob URIs in [byUploadId].
Object? substituteUploadRefs(Object? json, Map<String, String> byUploadId) {
  if (json is String && json.startsWith(uploadPlaceholderPrefix)) {
    return byUploadId[json.substring(uploadPlaceholderPrefix.length)] ?? json;
  }
  if (json is Map) {
    return <String, Object?>{
      for (final e in json.entries)
        e.key as String: substituteUploadRefs(e.value, byUploadId),
    };
  }
  if (json is List) {
    return <Object?>[for (final v in json) substituteUploadRefs(v, byUploadId)];
  }
  return json;
}

/// Writes local rows optimistically and queues the matching ops
/// (NF-003 outbox with idempotency keys, FA-025).
///
/// Every enqueue is one transaction: the typed row is written with
/// `dirty = true` and the op is appended to `outbox` with a fresh uuid
/// `op_id`. The [SyncEngine] pushes ops in that order.
class Outbox {
  /// Creates the outbox over [db].
  Outbox(AppDatabase db, {DateTime Function()? clock, String Function()? ids})
    : store = SyncStore(db),
      _now = clock ?? _utcNow,
      _newId = ids ?? generateUuidV4;

  /// Shared store.
  final SyncStore store;

  final DateTime Function() _now;
  final String Function() _newId;

  static DateTime _utcNow() => DateTime.now().toUtc();

  /// Placeholder to put in a payload for a queued upload.
  static String uploadRef(String localUploadId) =>
      '$uploadPlaceholderPrefix$localUploadId';

  void _check(String entity) {
    if (!SyncEntities.writable.contains(entity)) {
      throw ArgumentError.value(entity, 'entity', 'not a writable entity');
    }
  }

  Future<String?> _pendingUploadIn(Map<String, Object?> payload) async {
    for (final id in uploadRefsIn(payload)) {
      final row = await store.upload(id);
      if (row == null || row.state != UploadState.complete.name) return id;
    }
    return null;
  }

  /// Queues a create: writes the row (version 0, dirty) and the op.
  ///
  /// [local] holds device-only fields for the row (estimates, display
  /// labels); they are stored under `LocalEntities.localKey` and never
  /// sent. Entities in [SyncEntities.createPayloadWithoutId] send the
  /// payload without `id` (the server takes it from `entity_id`).
  Future<SyncOp> enqueueCreate(
    String entity,
    String id,
    Map<String, Object?> payload, {
    Map<String, Object?>? local,
  }) async {
    _check(entity);
    final now = _now();
    final op = SyncOp(
      opId: _newId(),
      entity: entity,
      action: SyncAction.create,
      entityId: id,
      baseVersion: 0,
      payload: SyncEntities.createPayloadWithoutId.contains(entity)
          ? <String, Object?>{...payload}
          : <String, Object?>{...payload, 'id': id},
      clientTs: now,
    );
    await store.db.transaction(() async {
      await store.entities.write(
        entity,
        id,
        <String, Object?>{
          ...op.payload,
          'id': id,
          LocalEntities.localKey: ?local,
        },
        version: 0,
        dirty: true,
        now: now,
      );
      await store.insertOp(
        op,
        dependsOnUploadId: await _pendingUploadIn(op.payload),
      );
    });
    return op;
  }

  /// Queues an update: merges [payload] into the row and appends the op.
  ///
  /// When the row's earliest open op was `rejected`, the edit is folded into
  /// that op and it is requeued under the same `op_id` (A64 "retry after
  /// edit") instead of stacking a second op behind a failed one.
  Future<SyncOp> enqueueUpdate(
    String entity,
    String id,
    Map<String, Object?> payload,
  ) async {
    _check(entity);
    final now = _now();
    return store.db.transaction(() async {
      final row = await store.entities.merge(
        entity,
        id,
        payload,
        now: now,
        dirty: true,
      );
      final open = await store.firstOpenOp(id);
      if (open != null && open.state == OutboxState.rejected.name) {
        final merged = <String, Object?>{
          ...SyncStore.payloadOf(open),
          ...payload,
        };
        await store.requeue(open.opId, payload: merged);
        await store.setPayload(
          open.opId,
          merged,
          dependsOnUploadId: await _pendingUploadIn(merged),
        );
        return SyncStore.toOp(open).copyWith(payload: merged);
      }
      final op = SyncOp(
        opId: _newId(),
        entity: entity,
        action: SyncAction.update,
        entityId: id,
        baseVersion: row.version,
        payload: payload,
        clientTs: now,
      );
      await store.insertOp(
        op,
        dependsOnUploadId: await _pendingUploadIn(op.payload),
      );
      return op;
    });
  }

  /// Queues a delete: tombstones the row and appends the op.
  Future<SyncOp> enqueueDelete(String entity, String id) async {
    _check(entity);
    final now = _now();
    return store.db.transaction(() async {
      final existing = await store.entities.read(entity, id);
      await store.entities.setFlags(
        entity,
        id,
        now: now,
        dirty: true,
        deleted: true,
      );
      final op = SyncOp(
        opId: _newId(),
        entity: entity,
        action: SyncAction.delete,
        entityId: id,
        baseVersion: existing?.version ?? 0,
        payload: const <String, Object?>{},
        clientTs: now,
      );
      await store.insertOp(op);
      return op;
    });
  }

  /// Queues a processed photo for a resumable upload and returns the local
  /// upload id; reference it in payloads with [uploadRef].
  ///
  /// [bytes] are hashed here; the file at [filePath] must hold the same
  /// bytes when the upload runs (the uploader re-checks the hash).
  Future<String> enqueueUpload({
    required String filePath,
    required Uint8List bytes,
    required String purpose,
    String contentType = 'image/jpeg',
    int chunkSize = defaultUploadChunkSize,
  }) async {
    final id = _newId();
    await store.insertUpload(
      id: id,
      filePath: filePath,
      sha256: sha256.convert(bytes).toString(),
      sizeBytes: bytes.length,
      purpose: purpose,
      contentType: contentType,
      chunkSize: chunkSize,
      now: _now(),
    );
    return id;
  }
}

import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../photo/chunked_upload_planner.dart';
import 'sync_models.dart';

/// Transport for the sync contract (FA-025 / NF-003).
///
/// [HttpSyncApi] talks to the FarmerApp API; [FakeSyncApi] is an in-memory
/// server for tests and previews. Every method throws
/// [SyncTransportException] when the request does not complete.
abstract interface class SyncApi {
  /// `POST /v1/sync`: push [SyncRequest.ops], pull changes since the cursor.
  Future<SyncResponse> sync(SyncRequest request);

  /// `POST /v1/uploads`: opens (or re-opens) an upload session.
  Future<UploadSession> initUpload({
    required String sha256,
    required int sizeBytes,
    required String contentType,
    required String purpose,
    int chunkSize = defaultUploadChunkSize,
  });

  /// `PUT /v1/uploads/{id}/chunks/{index}` with `X-Chunk-Sha256`.
  Future<UploadSession> uploadChunk({
    required String uploadId,
    required int index,
    required Uint8List bytes,
    required String chunkSha256,
  });

  /// `GET /v1/uploads/{id}`; `null` when the session is gone (expired).
  Future<UploadSession?> getUpload(String uploadId);

  /// `POST /v1/uploads/{id}/complete`.
  Future<UploadResult> completeUpload(String uploadId);
}

/// A row on the fake server.
class FakeServerRow {
  /// Creates the row.
  FakeServerRow({required this.version, required this.data});

  /// Current version.
  int version;

  /// Current data.
  Map<String, Object?> data;
}

/// An upload session on the fake server.
class FakeUpload {
  /// Creates the session.
  FakeUpload({
    required this.uploadId,
    required this.sha256,
    required this.sizeBytes,
    required this.contentType,
    required this.purpose,
    required this.chunkSize,
  });

  /// Server id.
  final String uploadId;

  /// Declared hash.
  final String sha256;

  /// Declared size.
  final int sizeBytes;

  /// Declared type.
  final String contentType;

  /// Declared purpose.
  final String purpose;

  /// Negotiated chunk size.
  final int chunkSize;

  /// Chunks received, by index.
  final Map<int, Uint8List> chunks = <int, Uint8List>{};

  /// Set once `complete` succeeded.
  String? blobUri;

  /// Chunks expected.
  int get chunkCount => (sizeBytes + chunkSize - 1) ~/ chunkSize;

  /// Session view.
  UploadSession get session => UploadSession(
    uploadId: uploadId,
    chunkSize: chunkSize,
    receivedChunks: chunks.keys.toList()..sort(),
  );
}

/// In-memory [SyncApi] that behaves like the server: idempotent by `op_id`,
/// optimistic versions, server-wins conflicts, a change feed with paging and
/// resumable uploads. Scriptable for tests:
///
/// * [offline] / [failNext] inject transport failures;
/// * [validate] rejects ops; [script] overrides any result;
/// * [addChange] feeds the pull side; [pageSize] controls `has_more`;
/// * [failChunk] / [expiredUploads] exercise upload resume.
class FakeSyncApi implements SyncApi {
  /// Creates the fake.
  FakeSyncApi({
    this.pageSize = 100,
    this.chunkSize = defaultUploadChunkSize,
    this.echoChanges = false,
  });

  /// Changes per page.
  int pageSize;

  /// Chunk size the fake server negotiates.
  int chunkSize;

  /// Emit a change for every applied op (as the real server does for other
  /// devices of the same tenant).
  bool echoChanges;

  /// Every call throws [SyncTransportException] while true.
  bool offline = false;

  /// Number of upcoming calls that fail with a transport error.
  int failNext = 0;

  /// Number of upcoming `sync` calls whose ops are applied server-side but
  /// whose response is lost (the client sees a transport error).
  int loseResponseNext = 0;

  /// Returns an error to reject an op, or null to process it normally.
  SyncError? Function(SyncOp op)? validate;

  /// Overrides the result for an op (null = process normally).
  SyncOpResult? Function(SyncOp op)? script;

  /// Returns true to fail a chunk `PUT` with a transport error.
  bool Function(String uploadId, int index)? failChunk;

  /// Upload ids whose `GET` answers 404 (session expired).
  final Set<String> expiredUploads = <String>{};

  /// Every request received (including failed ones).
  final List<SyncRequest> requests = <SyncRequest>[];

  /// Ops applied, in order (duplicates excluded).
  final List<SyncOp> appliedOps = <SyncOp>[];

  /// Op ids seen (idempotency).
  final Set<String> seenOpIds = <String>{};

  /// Server rows keyed `entity/id`.
  final Map<String, FakeServerRow> rows = <String, FakeServerRow>{};

  /// Change feed.
  final List<SyncChange> feed = <SyncChange>[];

  /// Upload sessions by id.
  final Map<String, FakeUpload> uploads = <String, FakeUpload>{};

  /// Successful `sync` calls.
  int syncCalls = 0;

  /// Calls that failed with a transport error.
  int transportFailures = 0;

  int _seq = 0;
  int _uploadCounter = 0;

  /// The server row for [entity]/[id], if any.
  FakeServerRow? row(String entity, String id) => rows['$entity/$id'];

  /// Appends a change to the feed (returns its seq).
  int addChange({
    required String entity,
    required SyncAction action,
    required String entityId,
    int version = 1,
    Map<String, Object?> data = const <String, Object?>{},
  }) {
    _seq += 1;
    feed.add(
      SyncChange(
        entity: entity,
        action: action,
        entityId: entityId,
        version: version,
        data: data,
        seq: _seq,
      ),
    );
    return _seq;
  }

  void _gate() {
    if (offline) {
      transportFailures += 1;
      throw const SyncTransportException('offline');
    }
    if (failNext > 0) {
      failNext -= 1;
      transportFailures += 1;
      throw const SyncTransportException('injected failure', statusCode: 503);
    }
  }

  @override
  Future<SyncResponse> sync(SyncRequest request) async {
    requests.add(request);
    _gate();
    if (request.ops.length > maxOpsPerSync) {
      throw const SyncTransportException(
        'too many ops',
        statusCode: 413,
        code: 'batch_too_large',
      );
    }
    syncCalls += 1;
    final results = <SyncOpResult>[for (final op in request.ops) _apply(op)];
    if (loseResponseNext > 0) {
      // The server applied the batch but the reply never arrived: the
      // client must resend and get `duplicate` back.
      loseResponseNext -= 1;
      transportFailures += 1;
      throw const SyncTransportException('response lost');
    }
    final since = int.tryParse(request.cursor ?? '') ?? 0;
    final pending = feed.where((c) => c.seq > since).toList(growable: false);
    final page = pending.take(pageSize).toList(growable: false);
    final cursor = page.isEmpty ? '$since' : '${page.last.seq}';
    return SyncResponse(
      results: results,
      changes: page,
      cursor: cursor,
      hasMore: pending.length > page.length,
    );
  }

  SyncOpResult _apply(SyncOp op) {
    final scripted = script?.call(op);
    if (scripted != null) {
      // A rejected op is not recorded: the client may resend it after an
      // edit under the same op_id, exactly like the real server.
      if (scripted.status != SyncResultStatus.rejected) {
        seenOpIds.add(op.opId);
      }
      return scripted;
    }
    final key = '${op.entity}/${op.entityId}';
    final existing = rows[key];
    if (seenOpIds.contains(op.opId)) {
      return SyncOpResult(
        opId: op.opId,
        status: SyncResultStatus.duplicate,
        entityId: op.entityId,
        version: existing?.version,
      );
    }
    final error = validate?.call(op);
    if (error != null) {
      return SyncOpResult(
        opId: op.opId,
        status: SyncResultStatus.rejected,
        entityId: op.entityId,
        error: error,
      );
    }
    seenOpIds.add(op.opId);
    switch (op.action) {
      case SyncAction.create:
        if (existing != null) {
          return _conflict(op, existing);
        }
        final row = FakeServerRow(
          version: 1,
          data: <String, Object?>{...op.payload, 'id': op.entityId},
        );
        rows[key] = row;
        return _applied(op, row);
      case SyncAction.update:
        if (existing == null) {
          return SyncOpResult(
            opId: op.opId,
            status: SyncResultStatus.conflict,
            entityId: op.entityId,
            error: const SyncError('not_found', 'row no longer exists'),
          );
        }
        if (op.baseVersion != existing.version) {
          return _conflict(op, existing);
        }
        existing
          ..version += 1
          ..data = <String, Object?>{...existing.data, ...op.payload};
        return _applied(op, existing);
      case SyncAction.delete:
        if (existing != null && op.baseVersion != existing.version) {
          return _conflict(op, existing);
        }
        rows.remove(key);
        appliedOps.add(op);
        if (echoChanges) {
          addChange(
            entity: op.entity,
            action: SyncAction.delete,
            entityId: op.entityId,
            version: existing?.version ?? 0,
          );
        }
        return SyncOpResult(
          opId: op.opId,
          status: SyncResultStatus.applied,
          entityId: op.entityId,
        );
    }
  }

  SyncOpResult _applied(SyncOp op, FakeServerRow row) {
    appliedOps.add(op);
    if (echoChanges) {
      addChange(
        entity: op.entity,
        action: op.action,
        entityId: op.entityId,
        version: row.version,
        data: row.data,
      );
    }
    return SyncOpResult(
      opId: op.opId,
      status: SyncResultStatus.applied,
      entityId: op.entityId,
      version: row.version,
    );
  }

  SyncOpResult _conflict(SyncOp op, FakeServerRow row) => SyncOpResult(
    opId: op.opId,
    status: SyncResultStatus.conflict,
    entityId: op.entityId,
    version: row.version,
    server: Map<String, Object?>.of(row.data),
    error: SyncError(
      'version_conflict',
      'server has version ${row.version}, op based on ${op.baseVersion}',
    ),
  );

  @override
  Future<UploadSession> initUpload({
    required String sha256,
    required int sizeBytes,
    required String contentType,
    required String purpose,
    int chunkSize = defaultUploadChunkSize,
  }) async {
    _gate();
    _uploadCounter += 1;
    final upload = FakeUpload(
      uploadId: 'up-$_uploadCounter',
      sha256: sha256,
      sizeBytes: sizeBytes,
      contentType: contentType,
      purpose: purpose,
      chunkSize: this.chunkSize,
    );
    uploads[upload.uploadId] = upload;
    return upload.session;
  }

  @override
  Future<UploadSession> uploadChunk({
    required String uploadId,
    required int index,
    required Uint8List bytes,
    required String chunkSha256,
  }) async {
    _gate();
    final upload = uploads[uploadId];
    if (upload == null || expiredUploads.contains(uploadId)) {
      throw const SyncTransportException(
        'unknown upload',
        statusCode: 404,
        code: 'upload_not_found',
      );
    }
    if (failChunk?.call(uploadId, index) ?? false) {
      transportFailures += 1;
      throw const SyncTransportException('chunk lost', statusCode: 502);
    }
    if (hexSha256(bytes) != chunkSha256) {
      throw const SyncTransportException(
        'chunk hash mismatch',
        statusCode: 400,
        code: 'chunk_hash_mismatch',
      );
    }
    upload.chunks[index] = Uint8List.fromList(bytes);
    return upload.session;
  }

  @override
  Future<UploadSession?> getUpload(String uploadId) async {
    _gate();
    if (expiredUploads.contains(uploadId)) return null;
    return uploads[uploadId]?.session;
  }

  @override
  Future<UploadResult> completeUpload(String uploadId) async {
    _gate();
    final upload = uploads[uploadId];
    if (upload == null || expiredUploads.contains(uploadId)) {
      throw const SyncTransportException(
        'unknown upload',
        statusCode: 404,
        code: 'upload_not_found',
      );
    }
    if (upload.chunks.length != upload.chunkCount) {
      throw SyncTransportException(
        'missing chunks: ${upload.chunks.length}/${upload.chunkCount}',
        statusCode: 409,
        code: 'upload_incomplete',
      );
    }
    final joined = Uint8List(upload.sizeBytes);
    for (final entry in upload.chunks.entries) {
      joined.setRange(
        entry.key * upload.chunkSize,
        entry.key * upload.chunkSize + entry.value.length,
        entry.value,
      );
    }
    final digest = hexSha256(joined);
    if (digest != upload.sha256) {
      throw const SyncTransportException(
        'file hash mismatch',
        statusCode: 400,
        code: 'sha256_mismatch',
      );
    }
    upload.blobUri = 'blob://fake/${upload.purpose}/$digest';
    return UploadResult(
      blobUri: upload.blobUri!,
      sha256: digest,
      sizeBytes: upload.sizeBytes,
      contentType: upload.contentType,
    );
  }

  /// Hex SHA-256 of [bytes] (shared with tests).
  static String hexSha256(List<int> bytes) => sha256.convert(bytes).toString();
}

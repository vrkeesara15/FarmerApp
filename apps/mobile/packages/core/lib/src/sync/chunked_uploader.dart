import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' show Value;

import '../db/app_database.dart';
import '../photo/chunked_upload_planner.dart';
import 'sync_api.dart';
import 'sync_models.dart';
import 'sync_store.dart';

/// Reads the bytes of a local file (injected in tests).
typedef FileReader = Future<Uint8List> Function(String path);

Future<Uint8List> _readFileBytes(String path) => File(path).readAsBytes();

/// Drives one resumable upload (NF-003): init or resume the session, PUT
/// the chunks the server has not acknowledged, complete.
///
/// Progress lives in the `uploads` row, so a kill between chunks resumes
/// from `GET /v1/uploads/{id}` after restart. Transport failures propagate
/// as [SyncTransportException] for the engine's backoff; permanent local
/// problems (file gone, hash mismatch) mark the row `failed`.
class ChunkedUploader {
  /// Creates the uploader.
  ChunkedUploader({
    required this.store,
    required this.api,
    FileReader? readFile,
  }) : _readFile = readFile ?? _readFileBytes;

  /// Shared store.
  final SyncStore store;

  /// Transport.
  final SyncApi api;

  final FileReader _readFile;

  /// Runs [row] to completion (or as far as the network allows) and returns
  /// the updated row.
  Future<Upload> upload(Upload row) async {
    final Uint8List bytes;
    try {
      bytes = await _readFile(row.filePath);
    } on FileSystemException catch (e) {
      return _fail(row, SyncError('file_missing', e.message));
    }
    if (sha256.convert(bytes).toString() != row.sha256) {
      return _fail(
        row,
        const SyncError('sha256_mismatch', 'file changed since it was queued'),
      );
    }

    var session = row.uploadId == null
        ? null
        : await api.getUpload(row.uploadId!);
    session ??= await api.initUpload(
      sha256: row.sha256,
      sizeBytes: row.sizeBytes,
      contentType: row.contentType,
      purpose: row.purpose,
      chunkSize: row.chunkSize,
    );
    await _save(
      row.id,
      UploadsCompanion(
        uploadId: Value<String?>(session.uploadId),
        chunkSize: Value<int>(session.chunkSize),
        receivedChunks: Value<String>(jsonEncode(session.receivedChunks)),
        state: Value<String>(UploadState.uploading.name),
        attempts: Value<int>(row.attempts + 1),
        expiresAt: Value<DateTime?>(session.expiresAt),
        lastError: const Value<String?>(null),
      ),
    );

    final plan = ChunkedUploadPlanner.plan(bytes, chunkSize: session.chunkSize);
    final received = session.receivedChunks.toSet();
    for (final chunk in plan.chunks) {
      if (received.contains(chunk.index)) continue;
      final ack = await api.uploadChunk(
        uploadId: session.uploadId,
        index: chunk.index,
        bytes: plan.slice(bytes, chunk),
        chunkSha256: chunk.sha256,
      );
      received
        ..addAll(ack.receivedChunks)
        ..add(chunk.index);
      await _save(
        row.id,
        UploadsCompanion(
          receivedChunks: Value<String>(jsonEncode(received.toList()..sort())),
        ),
      );
    }

    final result = await api.completeUpload(session.uploadId);
    return _save(
      row.id,
      UploadsCompanion(
        state: Value<String>(UploadState.complete.name),
        blobUri: Value<String?>(result.blobUri),
      ),
    );
  }

  Future<Upload> _fail(Upload row, SyncError error) => _save(
    row.id,
    UploadsCompanion(
      state: Value<String>(UploadState.failed.name),
      lastError: Value<String?>(jsonEncode(error.toJson())),
      attempts: Value<int>(row.attempts + 1),
    ),
  );

  Future<Upload> _save(String id, UploadsCompanion patch) async {
    await store.patchUpload(id, patch);
    final row = await store.upload(id);
    if (row == null) {
      throw StateError('upload $id disappeared');
    }
    return row;
  }
}

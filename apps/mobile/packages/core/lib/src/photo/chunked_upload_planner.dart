import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show immutable, listEquals;

/// NF-003: resumable image uploads are chunked at 256 KB.
const int defaultUploadChunkSize = 256 * 1024;

/// One chunk of a [ChunkedUploadPlan].
@immutable
class UploadChunk {
  /// Creates the chunk.
  const UploadChunk({
    required this.index,
    required this.offset,
    required this.length,
    required this.sha256,
  });

  /// Parses [toJson] output.
  factory UploadChunk.fromJson(Map<String, Object?> json) => UploadChunk(
    index: json['index']! as int,
    offset: json['offset']! as int,
    length: json['length']! as int,
    sha256: json['sha256']! as String,
  );

  /// 0-based position in the plan.
  final int index;

  /// First byte in the payload.
  final int offset;

  /// Number of bytes.
  final int length;

  /// Hex SHA-256 of the chunk bytes (checked by the server per chunk).
  final String sha256;

  /// One past the last byte.
  int get end => offset + length;

  /// JSON for the outbox.
  Map<String, Object?> toJson() => <String, Object?>{
    'index': index,
    'offset': offset,
    'length': length,
    'sha256': sha256,
  };

  @override
  bool operator ==(Object other) =>
      other is UploadChunk &&
      other.index == index &&
      other.offset == offset &&
      other.length == length &&
      other.sha256 == sha256;

  @override
  int get hashCode => Object.hash(index, offset, length, sha256);
}

/// A resumable upload plan for one payload. Immutable; [withAck] returns the
/// advanced plan. Persist [toJson] in the outbox row and rebuild with
/// [ChunkedUploadPlan.fromJson] after a restart.
@immutable
class ChunkedUploadPlan {
  /// Creates a plan; use [ChunkedUploadPlanner.plan] instead.
  const ChunkedUploadPlan({
    required this.fileSha256,
    required this.totalBytes,
    required this.chunkSize,
    required this.chunks,
    required this.lastAckedChunk,
  });

  /// Parses [toJson] output.
  factory ChunkedUploadPlan.fromJson(Map<String, Object?> json) {
    final chunks = (json['chunks']! as List<Object?>)
        .map((c) => UploadChunk.fromJson(c! as Map<String, Object?>))
        .toList(growable: false);
    return ChunkedUploadPlan(
      fileSha256: json['file_sha256']! as String,
      totalBytes: json['total_bytes']! as int,
      chunkSize: json['chunk_size']! as int,
      chunks: chunks,
      lastAckedChunk: json['last_acked_chunk']! as int,
    );
  }

  /// Hex SHA-256 of the whole payload (the server verifies it on completion).
  final String fileSha256;

  /// Payload length.
  final int totalBytes;

  /// Nominal chunk length; the last chunk may be shorter.
  final int chunkSize;

  /// Every chunk, in order.
  final List<UploadChunk> chunks;

  /// Index of the last chunk the server acknowledged; -1 for none.
  final int lastAckedChunk;

  /// Chunks still to send.
  List<UploadChunk> get pendingChunks =>
      chunks.sublist((lastAckedChunk + 1).clamp(0, chunks.length));

  /// The chunk to send next, or null when complete.
  UploadChunk? get nextChunk {
    final next = lastAckedChunk + 1;
    return next < chunks.length ? chunks[next] : null;
  }

  /// True once every chunk is acknowledged.
  bool get isComplete => lastAckedChunk >= chunks.length - 1;

  /// Bytes acknowledged so far (for a progress bar).
  int get uploadedBytes => lastAckedChunk < 0 ? 0 : chunks[lastAckedChunk].end;

  /// The plan after the server acknowledged [index]. Never moves backwards.
  ChunkedUploadPlan withAck(int index) {
    if (index < -1 || index >= chunks.length) {
      throw ArgumentError.value(index, 'index', 'not a chunk of this plan');
    }
    if (index <= lastAckedChunk) return this;
    return ChunkedUploadPlan(
      fileSha256: fileSha256,
      totalBytes: totalBytes,
      chunkSize: chunkSize,
      chunks: chunks,
      lastAckedChunk: index,
    );
  }

  /// The bytes of [chunk] from [payload], which must be the planned payload.
  Uint8List slice(Uint8List payload, UploadChunk chunk) {
    if (payload.length != totalBytes) {
      throw StateError(
        'payload is ${payload.length} bytes, plan expects $totalBytes',
      );
    }
    return Uint8List.sublistView(payload, chunk.offset, chunk.end);
  }

  /// JSON for the outbox.
  Map<String, Object?> toJson() => <String, Object?>{
    'v': 1,
    'file_sha256': fileSha256,
    'total_bytes': totalBytes,
    'chunk_size': chunkSize,
    'last_acked_chunk': lastAckedChunk,
    'chunks': chunks.map((c) => c.toJson()).toList(growable: false),
  };

  @override
  bool operator ==(Object other) =>
      other is ChunkedUploadPlan &&
      other.fileSha256 == fileSha256 &&
      other.totalBytes == totalBytes &&
      other.chunkSize == chunkSize &&
      other.lastAckedChunk == lastAckedChunk &&
      listEquals(other.chunks, chunks);

  @override
  int get hashCode => Object.hash(
    fileSha256,
    totalBytes,
    chunkSize,
    lastAckedChunk,
    Object.hashAll(chunks),
  );
}

/// Splits a payload into hashed chunks (pure Dart; the HTTP transport is
/// FA-025 / NF-003).
abstract final class ChunkedUploadPlanner {
  /// Plans [bytes] in [chunkSize] pieces, resuming after [lastAckedChunk].
  static ChunkedUploadPlan plan(
    Uint8List bytes, {
    int chunkSize = defaultUploadChunkSize,
    int lastAckedChunk = -1,
  }) {
    if (chunkSize <= 0) {
      throw ArgumentError.value(chunkSize, 'chunkSize', 'must be positive');
    }
    final count = (bytes.length + chunkSize - 1) ~/ chunkSize;
    if (lastAckedChunk < -1 || lastAckedChunk >= count) {
      throw ArgumentError.value(
        lastAckedChunk,
        'lastAckedChunk',
        'must be -1 or a chunk index below $count',
      );
    }
    final chunks = List<UploadChunk>.generate(count, (i) {
      final offset = i * chunkSize;
      final end = (offset + chunkSize).clamp(0, bytes.length);
      return UploadChunk(
        index: i,
        offset: offset,
        length: end - offset,
        sha256: sha256
            .convert(Uint8List.sublistView(bytes, offset, end))
            .toString(),
      );
    }, growable: false);
    return ChunkedUploadPlan(
      fileSha256: sha256.convert(bytes).toString(),
      totalBytes: bytes.length,
      chunkSize: chunkSize,
      chunks: chunks,
      lastAckedChunk: lastAckedChunk,
    );
  }
}

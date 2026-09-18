// NF-003: resumable chunked uploads, 256 KB chunks. Pure Dart planner; the
// HTTP transport lands with FA-025 / NF-003.
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _payload(int length, {int seed = 7}) {
  final out = Uint8List(length);
  var x = seed;
  for (var i = 0; i < length; i++) {
    x = (x * 1103515245 + 12345) & 0x7fffffff;
    out[i] = x >> 16 & 0xff;
  }
  return out;
}

void main() {
  const chunk = defaultUploadChunkSize;

  test('the default chunk size is 256 KB', () {
    expect(chunk, 256 * 1024);
  });

  test('exactly 256 KB is one chunk', () {
    final plan = ChunkedUploadPlanner.plan(_payload(chunk));
    expect(plan.chunks, hasLength(1));
    expect(plan.chunks.single.index, 0);
    expect(plan.chunks.single.offset, 0);
    expect(plan.chunks.single.length, chunk);
    expect(plan.totalBytes, chunk);
    expect(plan.chunkSize, chunk);
  });

  test('256 KB + 1 is two chunks, the last one byte long', () {
    final plan = ChunkedUploadPlanner.plan(_payload(chunk + 1));
    expect(plan.chunks, hasLength(2));
    expect(plan.chunks[1].offset, chunk);
    expect(plan.chunks[1].length, 1);
    expect(plan.chunks[1].end, chunk + 1);
  });

  test('offsets are contiguous and cover the whole payload', () {
    final bytes = _payload(1024 * 1024 + 100);
    final plan = ChunkedUploadPlanner.plan(bytes);
    expect(plan.chunks, hasLength(5));
    var offset = 0;
    for (final (i, c) in plan.chunks.indexed) {
      expect(c.index, i);
      expect(c.offset, offset);
      offset += c.length;
    }
    expect(offset, bytes.length);
  });

  test('per-chunk and whole-file sha256 match crypto', () {
    final bytes = _payload(chunk * 2 + 999);
    final plan = ChunkedUploadPlanner.plan(bytes);
    expect(plan.fileSha256, sha256.convert(bytes).toString());
    for (final c in plan.chunks) {
      final slice = bytes.sublist(c.offset, c.end);
      expect(c.sha256, sha256.convert(slice).toString());
      expect(plan.slice(bytes, c), slice);
    }
  });

  test('an empty payload has no chunks and is already complete', () {
    final plan = ChunkedUploadPlanner.plan(Uint8List(0));
    expect(plan.chunks, isEmpty);
    expect(plan.isComplete, isTrue);
    expect(plan.nextChunk, isNull);
    expect(plan.fileSha256, sha256.convert(<int>[]).toString());
  });

  group('resume', () {
    final bytes = _payload(chunk * 4 + 10);

    test('fresh plan starts at chunk 0', () {
      final plan = ChunkedUploadPlanner.plan(bytes);
      expect(plan.lastAckedChunk, -1);
      expect(plan.nextChunk?.index, 0);
      expect(plan.pendingChunks.map((c) => c.index), <int>[0, 1, 2, 3, 4]);
      expect(plan.isComplete, isFalse);
      expect(plan.uploadedBytes, 0);
    });

    test('resume at chunk n continues from n + 1', () {
      final plan = ChunkedUploadPlanner.plan(bytes, lastAckedChunk: 2);
      expect(plan.nextChunk?.index, 3);
      expect(plan.pendingChunks.map((c) => c.index), <int>[3, 4]);
      expect(plan.uploadedBytes, chunk * 3);
    });

    test('withAck moves forward and completes on the last chunk', () {
      var plan = ChunkedUploadPlanner.plan(bytes);
      plan = plan.withAck(0);
      expect(plan.lastAckedChunk, 0);
      plan = plan.withAck(3);
      expect(plan.nextChunk?.index, 4);
      plan = plan.withAck(4);
      expect(plan.isComplete, isTrue);
      expect(plan.nextChunk, isNull);
      expect(plan.pendingChunks, isEmpty);
      expect(plan.uploadedBytes, bytes.length);
    });

    test('withAck never moves backwards', () {
      final plan = ChunkedUploadPlanner.plan(bytes, lastAckedChunk: 3);
      expect(plan.withAck(1).lastAckedChunk, 3);
    });

    test('lastAckedChunk out of range is rejected', () {
      expect(
        () => ChunkedUploadPlanner.plan(bytes, lastAckedChunk: 5),
        throwsArgumentError,
      );
      expect(
        () => ChunkedUploadPlanner.plan(bytes, lastAckedChunk: -2),
        throwsArgumentError,
      );
    });
  });

  group('JSON for the outbox', () {
    test('round-trips including the resume position', () {
      final plan = ChunkedUploadPlanner.plan(
        _payload(chunk + 5),
        lastAckedChunk: 0,
      );
      final json =
          jsonDecode(jsonEncode(plan.toJson())) as Map<String, Object?>;
      expect(json['v'], 1);
      expect(json['chunk_size'], chunk);
      expect(json['total_bytes'], chunk + 5);
      expect(json['last_acked_chunk'], 0);
      expect(json['file_sha256'], plan.fileSha256);
      final chunks = json['chunks']! as List<Object?>;
      expect(chunks, hasLength(2));
      final second = chunks[1]! as Map<String, Object?>;
      expect(second['index'], 1);
      expect(second['offset'], chunk);
      expect(second['length'], 5);
      expect(second['sha256'], plan.chunks[1].sha256);

      final back = ChunkedUploadPlan.fromJson(json);
      expect(back, plan);
      expect(back.nextChunk?.index, 1);
    });
  });

  group('validation', () {
    test('chunk size must be positive', () {
      expect(
        () => ChunkedUploadPlanner.plan(_payload(10), chunkSize: 0),
        throwsArgumentError,
      );
    });

    test('slice refuses a payload that does not match the plan', () {
      final plan = ChunkedUploadPlanner.plan(_payload(chunk + 1));
      expect(
        () => plan.slice(_payload(chunk), plan.chunks.first),
        throwsStateError,
      );
    });

    test('custom chunk size is honoured', () {
      final plan = ChunkedUploadPlanner.plan(_payload(100), chunkSize: 30);
      expect(plan.chunks.map((c) => c.length), <int>[30, 30, 30, 10]);
    });
  });
}

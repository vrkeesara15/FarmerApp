import 'dart:convert';
import 'dart:io';

import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'sync_harness.dart';

/// NF-003 resumable uploads: 256 KB chunks, resume from the server's
/// received list after a kill, re-init on an expired session.
void main() {
  late AppDatabase db;
  late FakeClock clock;
  late FakeSyncApi api;
  late Outbox outbox;

  setUp(() {
    db = newDb();
    clock = FakeClock(t0);
    api = FakeSyncApi();
    outbox = outboxFor(db, clock: clock, ids: SeqIds());
  });

  tearDown(() => db.close());

  ChunkedUploader uploader(FileReader read) =>
      ChunkedUploader(store: outbox.store, api: api, readFile: read);

  test('uploads a 700 KB photo in three chunks and completes', () async {
    final bytes = photoBytes(700 * 1024);
    final id = await outbox.enqueueUpload(
      filePath: '/p/1.jpg',
      bytes: bytes,
      purpose: 'farm_photo',
    );
    final puts = <int>[];
    api.failChunk = (_, index) {
      puts.add(index);
      return false;
    };
    final row = await uploader((_) async => bytes)
        .upload((await outbox.store.upload(id))!);
    expect(row.state, 'complete');
    expect(row.uploadId, 'up-1');
    expect(
      row.blobUri,
      'blob://fake/farm_photo/${FakeSyncApi.hexSha256(bytes)}',
    );
    expect(jsonDecode(row.receivedChunks), [0, 1, 2]);
    expect(puts, [0, 1, 2]);
    final server = api.uploads['up-1']!;
    expect(server.chunks.keys, [0, 1, 2]);
    expect(server.chunks[2]!.length, 700 * 1024 - 2 * 256 * 1024);
  });

  test('resumes after a restart with partial received chunks', () async {
    final bytes = photoBytes(1000 * 1024); // 4 chunks
    final id = await outbox.enqueueUpload(
      filePath: '/p/1.jpg',
      bytes: bytes,
      purpose: 'visit_photo',
    );
    final puts = <int>[];
    api.failChunk = (_, index) {
      puts.add(index);
      return index == 2 && puts.where((i) => i == 2).length == 1;
    };
    await expectLater(
      uploader((_) async => bytes).upload((await outbox.store.upload(id))!),
      throwsA(isA<SyncTransportException>()),
    );
    final partial = (await outbox.store.upload(id))!;
    expect(partial.state, 'uploading');
    expect(partial.uploadId, 'up-1');
    expect(jsonDecode(partial.receivedChunks), [0, 1]);
    expect(puts, [0, 1, 2]);

    // "Restart": a new uploader over the same database and server session.
    final fresh = ChunkedUploader(
      store: SyncStore(db),
      api: api,
      readFile: (_) async => bytes,
    );
    final row = await fresh.upload((await SyncStore(db).upload(id))!);
    expect(row.state, 'complete');
    expect(puts, [0, 1, 2, 2, 3], reason: 'only the missing chunks again');
    expect(api.uploads, hasLength(1), reason: 'no second session');
    expect(api.uploads['up-1']!.chunks.keys.toList()..sort(), [0, 1, 2, 3]);
  });

  test('re-initialises when the server session expired', () async {
    final bytes = photoBytes(300 * 1024);
    final id = await outbox.enqueueUpload(
      filePath: '/p/1.jpg',
      bytes: bytes,
      purpose: 'farm_photo',
    );
    api.failChunk = (_, index) => index == 1;
    await expectLater(
      uploader((_) async => bytes).upload((await outbox.store.upload(id))!),
      throwsA(isA<SyncTransportException>()),
    );
    api.failChunk = null;
    api.expiredUploads.add('up-1');
    final row = await uploader((_) async => bytes)
        .upload((await outbox.store.upload(id))!);
    expect(row.state, 'complete');
    expect(row.uploadId, 'up-2');
    expect(api.uploads['up-2']!.chunks.keys.toList()..sort(), [0, 1]);
  });

  test('a missing file fails the upload for good', () async {
    final id = await outbox.enqueueUpload(
      filePath: '/nowhere/1.jpg',
      bytes: photoBytes(10),
      purpose: 'farm_photo',
    );
    final row = await uploader(
      (path) async => throw FileSystemException('gone', path),
    ).upload((await outbox.store.upload(id))!);
    expect(row.state, 'failed');
    expect(jsonDecode(row.lastError!), containsPair('code', 'file_missing'));
    expect(api.uploads, isEmpty);
  });

  test('a changed file fails the upload for good', () async {
    final id = await outbox.enqueueUpload(
      filePath: '/p/1.jpg',
      bytes: photoBytes(10),
      purpose: 'farm_photo',
    );
    final row = await uploader((_) async => photoBytes(10, seed: 3))
        .upload((await outbox.store.upload(id))!);
    expect(row.state, 'failed');
    expect(jsonDecode(row.lastError!), containsPair('code', 'sha256_mismatch'));
  });

  test('the default reader reads the file from disk', () async {
    final dir = Directory.systemTemp.createTempSync('farmerapp_upload');
    addTearDown(() => dir.deleteSync(recursive: true));
    final bytes = photoBytes(2048);
    final file = File('${dir.path}/photo.jpg')..writeAsBytesSync(bytes);
    final id = await outbox.enqueueUpload(
      filePath: file.path,
      bytes: bytes,
      purpose: 'farm_photo',
    );
    final row = await ChunkedUploader(
      store: outbox.store,
      api: api,
    ).upload((await outbox.store.upload(id))!);
    expect(row.state, 'complete');
  });
}

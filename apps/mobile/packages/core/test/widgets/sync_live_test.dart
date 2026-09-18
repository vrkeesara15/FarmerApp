import 'dart:async';
import 'dart:typed_data';

import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../helpers/harness.dart';
import '../sync/sync_harness.dart';

/// `syncStatusProvider` drives [SyncStatusPill] through every state and
/// `offlineProvider` shows / hides [OfflineBanner].
void main() {
  Widget scoped(Widget child, List<Override> overrides) =>
      ProviderScope(overrides: overrides, child: harness(child));

  testWidgets('pill follows the engine: synced → pending → syncing → synced', (
    tester,
  ) async {
    final db = newDb();
    addTearDown(db.close);
    final api = FakeSyncApi();
    final gate = _GatedApi(api);
    final outbox = outboxFor(db, clock: FakeClock(t0), ids: SeqIds());
    await tester.pumpWidget(
      scoped(const SyncStatusPillLive(), [
        appDatabaseProvider.overrideWithValue(db),
        syncApiProvider.overrideWithValue(gate),
      ]),
    );
    await tester.pumpAndSettle();
    expect(find.text('Synced'), findsOneWidget);

    await outbox.enqueueCreate(SyncEntities.farmer, 'f-1', farmerPayload(1));
    await outbox.enqueueCreate(SyncEntities.farmer, 'f-2', farmerPayload(2));
    await tester.pumpAndSettle();
    expect(find.text('Pending 2'), findsOneWidget);

    final element = tester.element(find.byType(SyncStatusPillLive));
    final engine = ProviderScope.containerOf(element).read(syncEngineProvider);
    final done = engine.syncNow();
    await tester.pumpAndSettle();
    expect(find.text('Syncing…'), findsOneWidget, reason: 'gated request');
    gate.release();
    await done;
    await tester.pumpAndSettle();
    expect(find.text('Synced'), findsOneWidget);
    expect(api.appliedOps, hasLength(2));
  });

  testWidgets('a rejected op shows the failed pill and opens details on tap', (
    tester,
  ) async {
    final db = newDb();
    addTearDown(db.close);
    final api = FakeSyncApi()
      ..validate = (_) => const SyncError('validation_error', 'bad phone');
    final outbox = outboxFor(db, clock: FakeClock(t0), ids: SeqIds());
    await outbox.enqueueCreate(SyncEntities.farmer, 'f-1', farmerPayload(1));
    var taps = 0;
    await tester.pumpWidget(
      scoped(SyncStatusPillLive(onTap: () => taps++), [
        appDatabaseProvider.overrideWithValue(db),
        syncApiProvider.overrideWithValue(api),
      ]),
    );
    await tester.pumpAndSettle();
    final element = tester.element(find.byType(SyncStatusPillLive));
    await ProviderScope.containerOf(element).read(syncEngineProvider).syncNow();
    await tester.pumpAndSettle();
    expect(find.text('Sync failed'), findsOneWidget);
    await tester.tap(find.text('Sync failed'));
    expect(taps, 1);
  });

  testWidgets('scripted statuses map to the pill variants', (tester) async {
    for (final (status, label) in <(SyncStatus, String)>[
      (SyncStatus.synced, 'Synced'),
      (const SyncStatus(SyncStatusKind.pending, pending: 7), 'Pending 7'),
      (const SyncStatus(SyncStatusKind.failed, failed: 2), 'Sync failed'),
      (const SyncStatus(SyncStatusKind.syncing, pending: 3), 'Syncing…'),
    ]) {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(
        scoped(const SyncStatusPillLive(), [
          syncStatusProvider.overrideWith((ref) => Stream.value(status)),
        ]),
      );
      await tester.pumpAndSettle();
      expect(find.text(label), findsOneWidget, reason: '$status');
    }
  });

  testWidgets('OfflineBannerLive follows the connectivity monitor', (
    tester,
  ) async {
    final monitor = FakeConnectivityMonitor();
    addTearDown(monitor.dispose);
    await tester.pumpWidget(
      scoped(const OfflineBannerLive(), [
        connectivityMonitorProvider.overrideWithValue(monitor),
      ]),
    );
    await tester.pumpAndSettle();
    expect(find.byType(OfflineBanner), findsNothing);

    monitor.online = false;
    await tester.pumpAndSettle();
    expect(find.byType(OfflineBanner), findsOneWidget);
    expect(
      find.text('You are offline. Your work is saved and will sync later.'),
      findsOneWidget,
    );

    monitor.online = true;
    await tester.pumpAndSettle();
    expect(find.byType(OfflineBanner), findsNothing);
  });

  testWidgets('offlineProvider is false until the monitor answers', (
    tester,
  ) async {
    late bool offline;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          connectivityMonitorProvider.overrideWithValue(
            FakeConnectivityMonitor(online: false),
          ),
        ],
        child: Consumer(
          builder: (context, ref, _) {
            offline = ref.watch(offlineProvider);
            return const SizedBox();
          },
        ),
      ),
    );
    expect(offline, isFalse);
    await tester.pumpAndSettle();
    expect(offline, isTrue);
  });
}

/// Holds every `sync` call until [release] so the syncing state is visible.
class _GatedApi implements SyncApi {
  _GatedApi(this.inner);

  final FakeSyncApi inner;
  final Completer<void> _gate = Completer<void>();

  void release() => _gate.complete();

  @override
  Future<SyncResponse> sync(SyncRequest request) async {
    await _gate.future;
    return inner.sync(request);
  }

  @override
  Future<UploadResult> completeUpload(String uploadId) =>
      inner.completeUpload(uploadId);

  @override
  Future<UploadSession?> getUpload(String uploadId) =>
      inner.getUpload(uploadId);

  @override
  Future<UploadSession> initUpload({
    required String sha256,
    required int sizeBytes,
    required String contentType,
    required String purpose,
    int chunkSize = defaultUploadChunkSize,
  }) => inner.initUpload(
    sha256: sha256,
    sizeBytes: sizeBytes,
    contentType: contentType,
    purpose: purpose,
    chunkSize: chunkSize,
  );

  @override
  Future<UploadSession> uploadChunk({
    required String uploadId,
    required int index,
    required Uint8List bytes,
    required String chunkSha256,
  }) => inner.uploadChunk(
    uploadId: uploadId,
    index: index,
    bytes: bytes,
    chunkSha256: chunkSha256,
  );
}

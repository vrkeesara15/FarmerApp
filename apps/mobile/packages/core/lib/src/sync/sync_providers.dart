import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/token_store.dart' show generateUuidV4;
import '../db/open_database.dart';
import '../state/auth_flow.dart';
import 'outbox.dart';
import 'sync_api.dart';
import 'sync_engine.dart';
import 'sync_scheduler.dart';

/// Wall clock (UTC); tests override it with a fixed clock.
final Provider<DateTime Function()> clockProvider =
    Provider<DateTime Function()>(
      (ref) =>
          () => DateTime.now().toUtc(),
    );

/// Client-side id generator (uuid v4); tests override it with sequences.
final Provider<String Function()> idGeneratorProvider =
    Provider<String Function()>((ref) => generateUuidV4);

/// The outbox over [appDatabaseProvider], [clockProvider] and
/// [idGeneratorProvider].
final Provider<Outbox> outboxProvider = Provider<Outbox>(
  (ref) => Outbox(
    ref.watch(appDatabaseProvider),
    clock: ref.watch(clockProvider),
    ids: ref.watch(idGeneratorProvider),
  ),
);

/// The sync transport; apps override it with [HttpSyncApi].
final Provider<SyncApi> syncApiProvider = Provider<SyncApi>(
  (ref) => FakeSyncApi(),
);

/// Network state; apps override it with [PlusConnectivityMonitor].
final Provider<ConnectivityMonitor> connectivityMonitorProvider =
    Provider<ConnectivityMonitor>((ref) => FakeConnectivityMonitor());

/// OS background work; apps override it with [WorkmanagerSyncScheduler].
final Provider<BackgroundWorkScheduler> backgroundWorkSchedulerProvider =
    Provider<BackgroundWorkScheduler>((ref) => FakeBackgroundWorkScheduler());

/// Reads a queued photo file for the uploader; tests override it with the
/// in-memory photo store.
final Provider<Future<Uint8List> Function(String path)> fileReaderProvider =
    Provider<Future<Uint8List> Function(String path)>(
      (ref) =>
          (path) => File(path).readAsBytes(),
    );

/// The engine over [appDatabaseProvider], [syncApiProvider] and the device
/// id from [tokenStoreProvider].
final Provider<SyncEngine> syncEngineProvider = Provider<SyncEngine>((ref) {
  final store = ref.watch(tokenStoreProvider);
  final engine = SyncEngine(
    db: ref.watch(appDatabaseProvider),
    api: ref.watch(syncApiProvider),
    deviceId: store.deviceId,
    readFile: ref.watch(fileReaderProvider),
  );
  ref.onDispose(engine.dispose);
  return engine;
});

/// Connectivity + WorkManager wiring; the app calls `start()` once.
final Provider<SyncScheduler> syncSchedulerProvider = Provider<SyncScheduler>((
  ref,
) {
  final scheduler = SyncScheduler(
    engine: ref.watch(syncEngineProvider),
    connectivity: ref.watch(connectivityMonitorProvider),
    background: ref.watch(backgroundWorkSchedulerProvider),
  );
  ref.onDispose(scheduler.dispose);
  return scheduler;
});

/// `synced | pending(n) | failed(n) | syncing`, live.
final StreamProvider<SyncStatus> syncStatusProvider =
    StreamProvider<SyncStatus>(
      (ref) => ref.watch(syncEngineProvider).watchStatus(),
    );

/// Everything A64 shows, live.
final StreamProvider<SyncDetails> syncDetailsProvider =
    StreamProvider<SyncDetails>(
      (ref) => ref.watch(syncEngineProvider).watchDetails(),
    );

/// Offline flag as a stream (true = no network).
final StreamProvider<bool> offlineStreamProvider = StreamProvider<bool>((
  ref,
) async* {
  final monitor = ref.watch(connectivityMonitorProvider);
  yield !(await monitor.isOnline());
  await for (final online in monitor.onlineChanges) {
    yield !online;
  }
});

/// Drives [OfflineBanner]: true while the device is offline.
final Provider<bool> offlineProvider = Provider<bool>(
  (ref) => ref.watch(offlineStreamProvider).value ?? false,
);

import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'sync_harness.dart';

/// FA-025 triggers: periodic background work is registered, connectivity
/// regained runs an immediate sync plus a one-off job, and the background
/// task runner reports success only when the sync completed.
void main() {
  late AppDatabase db;
  late FakeSyncApi api;
  late SyncEngine engine;
  late FakeConnectivityMonitor connectivity;
  late FakeBackgroundWorkScheduler background;
  late SyncScheduler scheduler;

  setUp(() {
    db = newDb();
    api = FakeSyncApi();
    engine = engineFor(db, api, clock: FakeClock(t0));
    connectivity = FakeConnectivityMonitor(online: false);
    background = FakeBackgroundWorkScheduler();
    scheduler = SyncScheduler(
      engine: engine,
      connectivity: connectivity,
      background: background,
    );
  });

  tearDown(() async {
    await scheduler.dispose();
    await connectivity.dispose();
    await engine.dispose();
    await db.close();
  });

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test('start registers the periodic job and syncs if online', () async {
    connectivity.online = true;
    await scheduler.start();
    await settle();
    expect(background.periodicRegistrations, 1);
    expect(scheduler.syncsTriggered, 1);
    expect(api.syncCalls, 1);
  });

  test('offline at start: no sync until connectivity returns', () async {
    await scheduler.start();
    await settle();
    expect(scheduler.syncsTriggered, 0);
    expect(api.syncCalls, 0);

    connectivity.online = true;
    await settle();
    await settle();
    expect(scheduler.syncsTriggered, 1);
    expect(background.oneOffRequests, 1);
    expect(api.syncCalls, 1);

    // Staying online does not re-trigger; a drop and return does.
    connectivity.online = true;
    connectivity.online = false;
    await settle();
    expect(scheduler.syncsTriggered, 1);
    connectivity.online = true;
    await settle();
    await settle();
    expect(scheduler.syncsTriggered, 2);
    expect(background.oneOffRequests, 2);
  });

  test('regaining connectivity ignores the backoff window', () async {
    api.offline = true;
    connectivity.online = true;
    await scheduler.start();
    await settle();
    expect(api.transportFailures, 1);
    api.offline = false;
    connectivity.online = false;
    connectivity.online = true;
    await settle();
    await settle();
    expect(api.syncCalls, 1, reason: 'forced despite nextAttemptAt');
  });

  test(
    'runBackgroundTask runs only sync tasks and reports the outcome',
    () async {
      var built = 0;
      Future<SyncEngine> build() async {
        built += 1;
        return engineFor(db, api, clock: FakeClock(t0));
      }

      expect(await SyncScheduler.runBackgroundTask('other', build), isTrue);
      expect(built, 0);

      expect(
        await SyncScheduler.runBackgroundTask(syncPeriodicTaskName, build),
        isTrue,
      );
      expect(built, 1);
      expect(api.syncCalls, 1);

      api.offline = true;
      expect(
        await SyncScheduler.runBackgroundTask(syncOneOffTaskName, build),
        isFalse,
      );
      expect(built, 2);
    },
  );

  test('the fake connectivity monitor reports its state', () async {
    expect(await connectivity.isOnline(), isFalse);
    connectivity.online = true;
    expect(await connectivity.isOnline(), isTrue);
  });
}

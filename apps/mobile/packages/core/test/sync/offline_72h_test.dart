import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'sync_harness.dart';

/// NF-002 / FA-025 acceptance: 72 hours offline, 300 ops captured across
/// three simulated days with two app restarts, then back online: every op
/// reaches the server exactly once, in order per entity, with zero loss.
void main() {
  test('72-hour offline capture syncs with zero loss and exact order', () async {
    final db = newDb();
    addTearDown(db.close);
    final clock = FakeClock(t0);
    final api = FakeSyncApi()..offline = true;
    final ids = SeqIds();
    var outbox = outboxFor(db, clock: clock, ids: ids);
    var engine = engineFor(db, api, clock: clock);

    // Expected per-entity op order, by op id.
    final expected = <String, List<String>>{};
    void record(String entityId, SyncOp op) =>
        expected.putIfAbsent(entityId, () => <String>[]).add(op.opId);

    const farmersPerDay = 20;
    const periodic = Duration(minutes: 15);
    var ticks = 0;

    Future<void> tick() async {
      // What WorkManager does every 15 minutes while the network is "up"
      // (the phone sees a dead 2G cell): an automatic, backoff-respecting run.
      ticks += 1;
      final report = await engine.syncNow(force: false);
      expect(report.ok, isFalse);
    }

    Future<void> restart() async {
      await engine.dispose();
      outbox = outboxFor(db, clock: clock, ids: ids);
      engine = engineFor(db, api, clock: clock);
    }

    for (var day = 0; day < 3; day++) {
      final dayStart = t0.add(Duration(days: day));
      clock.now = dayStart;
      for (var i = 0; i < farmersPerDay; i++) {
        final n = day * farmersPerDay + i + 1;
        final farmerId = 'farmer-$n';
        final farmId = 'farm-$n';
        final plotId = 'plot-$n';
        // Day: a registration (5 ops per farmer) spread over ~8 hours.
        clock.now = dayStart.add(Duration(minutes: 24 * i));
        record(
          farmerId,
          await outbox.enqueueCreate(
            SyncEntities.farmer,
            farmerId,
            farmerPayload(n),
          ),
        );
        record(
          farmId,
          await outbox.enqueueCreate(
            SyncEntities.farm,
            farmId,
            farmPayload(farmerId),
          ),
        );
        record(
          plotId,
          await outbox.enqueueCreate(
            SyncEntities.cropPlot,
            plotId,
            cropPlotPayload(farmId),
          ),
        );
        clock.advance(const Duration(minutes: 3));
        record(
          farmerId,
          await outbox.enqueueUpdate(SyncEntities.farmer, farmerId, {
            'landmark': 'day $day',
          }),
        );
        record(
          farmId,
          await outbox.enqueueUpdate(SyncEntities.farm, farmId, {
            'soil': 'red',
          }),
        );
        if (i % 4 == 0) await tick();
      }
      // The rest of the day: periodic ticks every 15 minutes until midnight.
      while (clock.now.isBefore(dayStart.add(const Duration(days: 1)))) {
        clock.advance(periodic);
        await tick();
      }
      if (day < 2) await restart(); // the officer reboots the phone at night
    }

    // 72 hours have passed offline.
    expect(
      clock.now.difference(t0),
      greaterThanOrEqualTo(const Duration(hours: 72)),
    );
    final queued = await engine.store.opsIn(<String>['queued']);
    expect(queued, hasLength(300), reason: 'nothing lost across restarts');
    expect(queued.map((o) => o.seq), List<int>.generate(300, (i) => i + 1));
    expect(
      await engine.status(),
      const SyncStatus(SyncStatusKind.pending, pending: 300),
    );
    expect(
      api.transportFailures,
      lessThanOrEqualTo(ticks),
      reason: 'backoff never attempts more often than the periodic trigger',
    );
    expect((await engine.store.state()).attempts, greaterThan(9));
    expect((await engine.store.state()).lastError, isNotNull);

    // Signal is back. The first response is lost on the way (2G), so the
    // resend must be answered with `duplicate` and not applied twice.
    api
      ..offline = false
      ..loseResponseNext = 1;
    final firstTry = await engine.syncNow();
    expect(firstTry.error, isNotNull);
    expect(
      api.appliedOps,
      isNotEmpty,
      reason: 'the server applied the lost batch',
    );

    final report = await engine.syncNow();
    expect(report.ok, isTrue, reason: '${report.error}');
    expect(report.pushed + firstTry.pushed, greaterThanOrEqualTo(300));
    expect(report.rejected, 0);
    expect(report.conflict, 0);
    expect(
      report.duplicate,
      greaterThan(0),
      reason: 'the lost batch was resent',
    );

    // Exactly once, all 300, order preserved per entity.
    expect(api.appliedOps, hasLength(300));
    expect(api.appliedOps.map((o) => o.opId).toSet(), hasLength(300));
    expect(api.seenOpIds, hasLength(300));
    final applied = <String, List<String>>{};
    for (final op in api.appliedOps) {
      applied.putIfAbsent(op.entityId, () => <String>[]).add(op.opId);
    }
    expect(applied, expected);
    for (final request in api.requests) {
      expect(request.ops.length, lessThanOrEqualTo(maxOpsPerSync));
    }

    // Server state.
    for (var n = 1; n <= 60; n++) {
      final farmer = api.row('farmer', 'farmer-$n')!;
      expect(farmer.version, 2);
      expect(farmer.data['landmark'], 'day ${(n - 1) ~/ farmersPerDay}');
      expect(api.row('farm', 'farm-$n')!.version, 2);
      expect(api.row('farm', 'farm-$n')!.data['soil'], 'red');
      expect(api.row('crop_plot', 'plot-$n')!.version, 1);
    }

    // Local state: clean and matching the server versions.
    final farmers = await db.select(db.farmers).get();
    final farms = await db.select(db.farms).get();
    final plots = await db.select(db.cropPlots).get();
    expect(farmers, hasLength(60));
    expect(farms, hasLength(60));
    expect(plots, hasLength(60));
    expect(farmers.every((f) => f.version == 2 && !f.dirty), isTrue);
    expect(farms.every((f) => f.version == 2 && !f.dirty), isTrue);
    expect(plots.every((p) => p.version == 1 && !p.dirty), isTrue);
    expect(
      await engine.store.opsIn(<String>['queued', 'sending', 'rejected']),
      isEmpty,
    );
    expect(await engine.status(), SyncStatus.synced);
    final state = await engine.store.state();
    expect(state.attempts, 0);
    expect(state.lastError, isNull);
    expect(state.lastSyncAt, clock.now);
    await engine.dispose();
  });
}

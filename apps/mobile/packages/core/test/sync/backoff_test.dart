import 'dart:math';

import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'sync_harness.dart';

/// NF-003 retry with backoff: 1 s doubling to a 5 min cap with jitter, and
/// the engine honouring the window for automatic triggers only.
void main() {
  group('Backoff', () {
    const backoff = Backoff();

    test('ceilings double from 1 s and cap at 5 min', () {
      expect(
        List<int>.generate(12, (i) => backoff.ceiling(i + 1).inSeconds),
        <int>[1, 2, 4, 8, 16, 32, 64, 128, 256, 300, 300, 300],
      );
      expect(backoff.ceiling(0), const Duration(seconds: 1));
      expect(backoff.ceiling(100), const Duration(minutes: 5));
    });

    test('delay stays within [ceiling / 2, ceiling]', () {
      final rng = Random(42);
      for (var attempt = 1; attempt <= 15; attempt++) {
        final ceiling = backoff.ceiling(attempt).inMilliseconds;
        for (var i = 0; i < 50; i++) {
          final delay = backoff.delay(attempt, random: rng).inMilliseconds;
          expect(delay, inInclusiveRange(ceiling ~/ 2, ceiling));
        }
      }
    });

    test('a fixed random source gives a reproducible schedule', () {
      final a = List<Duration>.generate(
        6,
        (i) => backoff.delay(i + 1, random: Random(7)),
      );
      final b = List<Duration>.generate(
        6,
        (i) => backoff.delay(i + 1, random: Random(7)),
      );
      expect(a, b);
    });

    test('custom base and cap', () {
      const fast = Backoff(
        base: Duration(milliseconds: 100),
        cap: Duration(seconds: 1),
        jitter: 0,
      );
      expect(fast.delay(1), const Duration(milliseconds: 100));
      expect(fast.delay(4), const Duration(milliseconds: 800));
      expect(fast.delay(5), const Duration(seconds: 1));
    });
  });

  group('SyncEngine', () {
    late AppDatabase db;
    late FakeClock clock;
    late FakeSyncApi api;
    late SyncEngine engine;

    setUp(() {
      db = newDb();
      clock = FakeClock(t0);
      api = FakeSyncApi()..offline = true;
      engine = engineFor(db, api, clock: clock, random: _MaxRandom());
    });

    tearDown(() async {
      await engine.dispose();
      await db.close();
    });

    test('a transport failure records the error and the next window', () async {
      final report = await engine.syncNow();
      expect(report.error, isA<SyncTransportException>());
      expect(report.ok, isFalse);
      final state = await engine.store.state();
      expect(state.attempts, 1);
      expect(state.lastError, contains('offline'));
      expect(state.nextAttemptAt, t0.add(const Duration(seconds: 1)));
      final details = await engine.details();
      expect(details.lastError, const SyncError('transport', 'offline'));
      expect(details.nextAttemptAt, t0.add(const Duration(seconds: 1)));
    });

    test('automatic runs wait for the window; manual runs do not', () async {
      await engine.syncNow(force: false);
      expect(api.transportFailures, 1);

      final skipped = await engine.syncNow(force: false);
      expect(skipped.skipped, isTrue);
      expect(api.transportFailures, 1, reason: 'window not elapsed');

      final forced = await engine.syncNow();
      expect(forced.skipped, isFalse);
      expect(api.transportFailures, 2);
      expect((await engine.store.state()).attempts, 2);
      expect(
        (await engine.store.state()).nextAttemptAt,
        t0.add(const Duration(seconds: 2)),
      );

      clock.advance(const Duration(seconds: 2));
      await engine.syncNow(force: false);
      expect(api.transportFailures, 3);
    });

    test('the schedule grows 1, 2, 4 ... and caps at 5 minutes', () async {
      final delays = <int>[];
      for (var i = 0; i < 12; i++) {
        await engine.syncNow();
        final next = (await engine.store.state()).nextAttemptAt!;
        delays.add(next.difference(clock.now).inSeconds);
        clock.now = next;
      }
      expect(delays, <int>[1, 2, 4, 8, 16, 32, 64, 128, 256, 300, 300, 300]);
    });

    test('a success resets the counter and clears the error', () async {
      await engine.syncNow();
      await engine.syncNow();
      api.offline = false;
      final report = await engine.syncNow();
      expect(report.ok, isTrue);
      final state = await engine.store.state();
      expect(state.attempts, 0);
      expect(state.lastError, isNull);
      expect(state.nextAttemptAt, isNull);
      expect(state.lastSyncAt, clock.now);
    });

    test('rejected ops are not retried, transport errors are', () async {
      api.offline = false;
      api.validate = (_) => const SyncError('validation_error', 'no');
      final outbox = outboxFor(db, clock: clock, ids: SeqIds());
      await outbox.enqueueCreate(SyncEntities.farmer, 'f-1', farmerPayload(1));
      await engine.syncNow();
      expect((await engine.store.state()).attempts, 0);
      expect((await engine.store.state()).nextAttemptAt, isNull);
      await engine.syncNow();
      expect(api.requests.last.ops, isEmpty);
    });
  });
}

/// Always draws the top of the jitter range so delays equal the ceilings.
class _MaxRandom implements Random {
  @override
  bool nextBool() => true;

  @override
  double nextDouble() => 1;

  @override
  int nextInt(int max) => max - 1;
}

import 'dart:convert';

import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'duty_harness.dart';

void main() {
  late DutyDeps deps;
  late ProviderContainer c;

  setUp(() {
    deps = DutyDeps();
    c = deps.container();
    deps.sampler.initial = fixAt(dutyT0);
  });

  tearDown(() async {
    c.dispose();
    await deps.dispose();
  });

  DutyController controller() => c.read(dutyControllerProvider.notifier);
  DutyState state() => c.read(dutyControllerProvider);
  DutyRepository repo() => c.read(dutyRepositoryProvider);

  Future<List<OutboxRow>> ops(String entity) async =>
      (await outboxRows(deps.db)).where((o) => o.entity == entity).toList();

  /// Emits [fix] and lets the controller's fix chain settle.
  Future<void> emit(LocationFix fix) async {
    deps.sampler.emit(fix);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
  }

  group('FA-011 gate', () {
    test('duty stays off until the policy is accepted: no session op, the '
        'sampler and the service are never started', () async {
      expect(await controller().goOnDuty(), DutyStartResult.policyNotAccepted);
      expect(state().onDuty, isFalse);
      expect(await outboxRows(deps.db), isEmpty);
      expect(deps.sampler.starts, 0);
      expect(deps.service.starts, 0);
      // A fix arriving now is dropped, nothing is buffered.
      deps.sampler.emit(fixAt(dutyT0));
      expect(deps.sampler.droppedWhileStopped, hasLength(1));
      expect(await deps.db.select(deps.db.locationBuffer).get(), isEmpty);
    });
  });

  group('FA-010 duty on', () {
    test('creates the duty_session op with the fix and the integrity signals, '
        'starts the foreground service and the sampler, schedules the '
        'VV-007 prompt', () async {
      await acceptPolicy(c);
      deps.probe.rooted = true;
      c
          .read(clockDriftTrackerProvider)
          .record(dutyT0, dutyT0.add(const Duration(seconds: 12)));
      expect(await controller().goOnDuty(), DutyStartResult.started);
      final s = state();
      expect(s.onDuty, isTrue);
      expect(s.active!.startAt.toUtc(), dutyT0);
      expect(s.integrity.isRooted, isTrue);
      expect(s.integrity.hasIssues, isTrue);

      final session = (await ops('duty_session')).single;
      expect(session.action, 'create');
      final payload = SyncStore.payloadOf(session);
      expect(payload['device_id'], 'device-1');
      expect(payload['app_version'], '0.1.0+1');
      expect(payload['policy_version'], '2026-09-v1');
      expect(payload['start_at'], dutyT0.toIso8601String());
      expect(payload['start_point'], <String, Object?>{
        'lat': 17.4,
        'lon': 78.4,
        'accuracy_m': 8.0,
      });
      expect(payload['integrity'], <String, Object?>{
        'is_mock': false,
        'is_rooted': true,
        'clock_drift_s': 12,
      });

      expect(deps.service.starts, 1);
      expect(deps.service.running, isTrue);
      expect(deps.service.title, 'On duty — location on');
      expect(deps.service.text, 'On duty for 0:00');
      expect(deps.sampler.starts, 1);
      expect(deps.sampler.isRunning, isTrue);
      expect(deps.sampler.lastPolicy, const DutyPolicy());

      // Prompt 10 minutes before 20:00 IST.
      expect(deps.alerts.pending, isNotNull);
      expect(
        deps.alerts.pending!.at,
        autoEndT0.subtract(const Duration(minutes: 10)),
      );
      expect(deps.alerts.pending!.title, 'Still on duty?');
      expect(deps.alerts.pending!.body, 'Ending at 20:00');
      expect(controller().autoEndAt, autoEndT0);

      // The typed row is there for A12.
      final row = await repo().activeSession();
      expect(row!.id, s.active!.id);
      expect(row.policyVersion, '2026-09-v1');
      expect(jsonDecode(row.integrity), payload['integrity']);
    });

    test('a second start while active is a no-op', () async {
      await acceptPolicy(c);
      await controller().goOnDuty();
      expect(await controller().goOnDuty(), DutyStartResult.alreadyActive);
      expect(await ops('duty_session'), hasLength(1));
      expect(deps.sampler.starts, 1);
    });

    test('no fix: duty stays off with a notice, nothing started', () async {
      await acceptPolicy(c);
      deps.sampler.initial = null;
      expect(
        await controller().goOnDuty(),
        DutyStartResult.locationUnavailable,
      );
      expect(state().onDuty, isFalse);
      expect(state().notice, DutyNotice.locationUnavailable);
      expect(await ops('duty_session'), isEmpty);
      expect(deps.sampler.starts, 0);
      expect(deps.service.starts, 0);
      controller().dismissNotice();
      expect(state().notice, isNull);
    });

    test('the elapsed time and the notification follow the clock', () async {
      await acceptPolicy(c);
      await controller().goOnDuty();
      deps.clock.advance(const Duration(hours: 2, minutes: 5));
      await controller().tick();
      expect(state().elapsed, const Duration(hours: 2, minutes: 5));
      expect(deps.service.text, 'On duty for 2:05');
    });
  });

  group('VV-001 sampling', () {
    test('kept fixes are buffered with battery, provider and the integrity '
        'signals; the cadence drops the rest; distance accumulates', () async {
      await acceptPolicy(c);
      deps.conditions.set(const DeviceConditions(batteryPct: 63));
      await controller().goOnDuty();
      await emit(fixAt(dutyT0, speedMps: 2));
      await emit(fixAt(dutyT0.add(const Duration(minutes: 1)), speedMps: 2));
      await emit(
        fixAt(
          dutyT0.add(const Duration(minutes: 2)),
          east: 200,
          speedMps: 2,
          isMock: true,
        ),
      );
      final rows = await deps.db.select(deps.db.locationBuffer).get();
      expect(rows, hasLength(2));
      expect(rows.first.batteryPct, 63);
      expect(rows.first.provider, 'fused');
      expect(rows.first.speedMps, 2);
      expect(rows.first.bearing, 90);
      expect(rows.first.isMock, isFalse);
      expect(rows.last.isMock, isTrue);
      expect(rows.last.isRooted, isFalse);
      expect(rows.first.batchId, isNull);
      expect(state().pointsPending, 2);
      expect(state().integrity.isMock, isTrue);
      final session = await repo().activeSession();
      expect(session!.distanceM, closeTo(200, 1));
    });

    test('NEGATIVE: nothing is buffered while off duty — before the first '
        'start and after the end', () async {
      await acceptPolicy(c);
      deps.sampler.emit(fixAt(dutyT0));
      expect(deps.sampler.starts, 0);
      await controller().goOnDuty();
      await emit(fixAt(dutyT0.add(const Duration(seconds: 1))));
      expect(await deps.db.select(deps.db.locationBuffer).get(), hasLength(1));
      await controller().goOffDuty();
      expect(deps.sampler.isRunning, isFalse);
      expect(deps.sampler.stops, 1);
      deps.sampler.emit(fixAt(dutyT0.add(const Duration(minutes: 30))));
      await Future<void>.delayed(Duration.zero);
      expect(deps.sampler.droppedWhileStopped, hasLength(2));
      final rows = await deps.db.select(deps.db.locationBuffer).get();
      expect(rows, hasLength(1));
      expect(rows.single.batchId, isNotNull, reason: 'flushed at end');
      expect(state().onDuty, isFalse);
      expect(state().pointsPending, 0);
    });

    test('the 15-minute tick flushes the buffer into one location_batch op '
        'in the contract shape', () async {
      await acceptPolicy(c);
      await controller().goOnDuty();
      await emit(fixAt(dutyT0, speedMps: 1));
      await emit(fixAt(dutyT0.add(const Duration(minutes: 2)), east: 100));
      deps.clock.advance(const Duration(minutes: 14));
      await controller().tick();
      expect(await ops('location_batch'), isEmpty, reason: 'not yet 15 min');
      deps.clock.advance(const Duration(minutes: 1));
      await controller().tick();
      final batch = (await ops('location_batch')).single;
      final payload = SyncStore.payloadOf(batch);
      expect(payload['duty_session_id'], state().active!.id);
      expect(payload['device_id'], 'device-1');
      expect(payload['sent_at'], deps.clock.now.toIso8601String());
      final points = payload['points']! as List<Object?>;
      expect(points, hasLength(2));
      final p0 = points.first! as Map<String, Object?>;
      expect(
        p0.keys,
        containsAll(<String>[
          'ts',
          'lat',
          'lon',
          'accuracy_m',
          'speed_mps',
          'bearing',
          'battery_pct',
          'is_mock',
          'is_rooted',
          'clock_drift_s',
          'provider',
        ]),
      );
      expect(p0['ts'], dutyT0.toIso8601String());
      expect(p0['speed_mps'], 1);
      expect(state().pointsPending, 0);
      final rows = await deps.db.select(deps.db.locationBuffer).get();
      expect(rows.every((r) => r.batchId == batch.entityId), isTrue);
      // The local doc keeps a count, not the points.
      final doc = await repo().batchesOf(state().active!.id);
      expect(doc.single['point_count'], 2);
      expect(doc.single.containsKey('points'), isFalse);
    });

    test('Wi-Fi or charging flushes immediately', () async {
      await acceptPolicy(c);
      await controller().goOnDuty();
      await emit(fixAt(dutyT0));
      deps.conditions.set(const DeviceConditions(onWifi: true, batteryPct: 50));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(await ops('location_batch'), hasLength(1));
      await emit(fixAt(dutyT0.add(const Duration(minutes: 10))));
      deps.conditions.set(const DeviceConditions(charging: true));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(await ops('location_batch'), hasLength(2));
    });

    test('a tenant that turns the Wi-Fi/charging flush off waits for the '
        'interval', () async {
      deps.policyApi.duty = DutyPolicy.fromJson(const <String, Object?>{
        'upload_on_wifi_or_charging': false,
      });
      await c.read(locationPolicyProvider.notifier).refresh();
      await acceptPolicy(c);
      await controller().goOnDuty();
      await emit(fixAt(dutyT0));
      deps.conditions.set(const DeviceConditions(onWifi: true));
      await Future<void>.delayed(Duration.zero);
      expect(await ops('location_batch'), isEmpty);
    });

    test('at most 500 points per op: 1,200 buffered points flush as '
        '500 + 500 + 200', () async {
      await acceptPolicy(c);
      await controller().goOnDuty();
      final id = state().active!.id;
      for (var i = 0; i < 1200; i++) {
        await repo().insertPoint(
          sessionId: id,
          fix: fixAt(dutyT0.add(Duration(seconds: i)), east: i.toDouble()),
          integrity: const IntegritySnapshot(),
        );
      }
      await controller().flush();
      final batches = await ops('location_batch');
      expect(batches, hasLength(3));
      final sizes = <int>[
        for (final b in batches)
          (SyncStore.payloadOf(b)['points']! as List<Object?>).length,
      ];
      expect(sizes, <int>[500, 500, 200]);
      expect(state().pointsPending, 0);
    });

    test(
      'a fix arriving while the buffer reaches 500 flushes at once',
      () async {
        await acceptPolicy(c);
        await controller().goOnDuty();
        final id = state().active!.id;
        for (var i = 0; i < 499; i++) {
          await repo().insertPoint(
            sessionId: id,
            fix: fixAt(dutyT0.add(Duration(seconds: i))),
            integrity: const IntegritySnapshot(),
          );
        }
        await emit(fixAt(dutyT0.add(const Duration(minutes: 30)), east: 300));
        expect(await ops('location_batch'), hasLength(1));
      },
    );

    test('server results are kept on the batch doc for A12 (accepted / '
        'rejected)', () async {
      await acceptPolicy(c);
      await controller().goOnDuty();
      await emit(fixAt(dutyT0));
      await emit(fixAt(dutyT0.add(const Duration(minutes: 3)), east: 100));
      await controller().flush();
      deps.api.script = (op) => op.entity == 'location_batch'
          ? SyncOpResult(
              opId: op.opId,
              status: SyncResultStatus.applied,
              entityId: op.entityId,
              version: 1,
              server: const <String, Object?>{
                'accepted': 1,
                'rejected': <Object?>[
                  <String, Object?>{'index': 1, 'reason': 'bad_accuracy'},
                ],
              },
            )
          : null;
      await c.read(syncEngineProvider).syncNow();
      final (from, to) = istDayBounds(dutyT0);
      final day = await repo().day(from, to);
      expect(day.sessions.single.pointsAccepted, 1);
      expect(day.sessions.single.pointsRejected, 1);
      expect(day.pointsPending, 0);
      expect(day.distanceM, closeTo(100, 1));
      expect(day.track, hasLength(2));
    });
  });

  group('duty off', () {
    test('flushes, queues the end op with the end fix, stops the sampler '
        'and the service, cancels the prompt', () async {
      await acceptPolicy(c);
      await controller().goOnDuty();
      await emit(fixAt(dutyT0));
      deps.clock.advance(const Duration(hours: 3));
      deps.sampler.initial = fixAt(deps.clock.now, east: 500);
      await controller().goOffDuty();
      expect(state().onDuty, isFalse);
      expect(state().busy, isFalse);
      expect(deps.sampler.stops, 1);
      expect(deps.service.stops, 1);
      expect(deps.service.running, isFalse);
      expect(deps.alerts.pending, isNull);
      expect(deps.alerts.cancels, 1);
      final all = await outboxRows(deps.db);
      expect(all.map((o) => '${o.entity}/${o.action}').toList(), <String>[
        'policy_acceptance/create',
        'duty_session/create',
        'location_batch/create',
        'duty_session/update',
      ]);
      final end = SyncStore.payloadOf(all.last);
      expect(end['end_at'], deps.clock.now.toIso8601String());
      expect(end['end_reason'], 'manual');
      expect((end['end_point']! as Map)['lon'], greaterThan(78.4));
      final row = await repo().session(all.last.entityId);
      expect(row!.endAt!.toUtc(), deps.clock.now);
      expect(row.endReason, 'manual');
      expect(await repo().activeSession(), isNull);

      // Everything syncs in order; the session row ends up clean.
      final report = await c.read(syncEngineProvider).syncNow();
      expect(report.applied, 4);
      expect(report.rejected, 0);
      expect((await repo().session(row.id))!.dirty, isFalse);
    });
  });

  group('VV-007 auto end', () {
    test('at 20:00 IST the tick ends the session with auto_time and shows '
        'the notice', () async {
      await acceptPolicy(c);
      await controller().goOnDuty();
      deps.clock.now = autoEndT0.subtract(const Duration(minutes: 1));
      await controller().tick();
      expect(state().onDuty, isTrue);
      deps.clock.now = autoEndT0;
      await controller().tick();
      expect(state().onDuty, isFalse);
      expect(state().notice, DutyNotice.autoEnded);
      final end = SyncStore.payloadOf((await ops('duty_session')).last);
      expect(end['end_reason'], 'auto_time');
      expect(end['end_at'], autoEndT0.toIso8601String());
      expect(deps.alerts.notices.single.title, 'Duty ended');
      expect(
        deps.alerts.notices.single.body,
        'Your day ended automatically at 20:00.',
      );
      expect(deps.sampler.isRunning, isFalse);
      expect(deps.service.running, isFalse);
    });

    test('a start after 20:00 IST schedules tomorrow\'s prompt', () async {
      deps.clock.now = autoEndT0.add(const Duration(minutes: 30));
      deps.sampler.initial = fixAt(deps.clock.now);
      await acceptPolicy(c);
      await controller().goOnDuty();
      expect(
        deps.alerts.pending!.at,
        autoEndT0.add(const Duration(days: 1) - const Duration(minutes: 10)),
      );
    });

    test('the tenant auto-end time is honoured', () async {
      deps.policyApi.duty = DutyPolicy.fromJson(const <String, Object?>{
        'auto_end_local_time': '18:30',
      });
      await c.read(locationPolicyProvider.notifier).refresh();
      await acceptPolicy(c);
      await controller().goOnDuty();
      expect(controller().autoEndAt, DateTime.utc(2026, 9, 21, 13));
      expect(deps.alerts.pending!.body, 'Ending at 18:30');
    });

    test(
      'the server-owned end_at (conflict on the update, or the pulled '
      'row) ends the session locally, stops the service and notifies',
      () async {
        await acceptPolicy(c);
        await controller().goOnDuty();
        await emit(fixAt(dutyT0));
        final id = state().active!.id;
        // The create is applied; then the server auto-ended the session
        // (idle) and answers the next sync with a conflict carrying its row.
        final serverEnd = dutyT0.add(const Duration(hours: 4));
        deps.api.script = (op) => op.entity == 'duty_session'
            ? SyncOpResult(
                opId: op.opId,
                status: SyncResultStatus.conflict,
                entityId: op.entityId,
                version: 2,
                error: const SyncError('server_owned', 'auto-ended'),
                server: <String, Object?>{
                  'id': id,
                  'start_at': dutyT0.toIso8601String(),
                  'end_at': serverEnd.toIso8601String(),
                  'end_reason': 'auto_idle',
                  'auto_ended': true,
                  'km': 3.2,
                },
              )
            : null;
        await c.read(syncEngineProvider).syncNow();
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);
        expect(state().onDuty, isFalse);
        expect(state().notice, DutyNotice.endedByServer);
        expect(deps.sampler.isRunning, isFalse);
        expect(deps.service.running, isFalse);
        expect(deps.alerts.pending, isNull);
        expect(deps.alerts.notices.single.body, contains('server'));
        final row = await repo().session(id);
        expect(row!.endAt!.toUtc(), serverEnd);
        expect(row.endReason, 'auto_idle');
        expect(row.autoEnded, isTrue);
        expect((jsonDecode(row.extra) as Map)['km'], 3.2);
        // No client end op was queued: the server owns the end.
        expect(
          (await ops('duty_session')).where((o) => o.action == 'update'),
          isEmpty,
        );
        // Sampling after that is impossible.
        deps.sampler.emit(fixAt(serverEnd.add(const Duration(minutes: 1))));
        expect(deps.sampler.droppedWhileStopped, hasLength(1));
      },
    );
  });

  group('server rejections', () {
    test(
      'duty_already_active drops the local session and keeps duty off',
      () async {
        await acceptPolicy(c);
        await controller().goOnDuty();
        deps.api.validate = (op) => op.entity == 'duty_session'
            ? const SyncError('duty_already_active', 'other device')
            : null;
        await c.read(syncEngineProvider).syncNow();
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);
        expect(state().onDuty, isFalse);
        expect(state().notice, DutyNotice.alreadyActiveElsewhere);
        expect(deps.sampler.isRunning, isFalse);
        expect(deps.service.running, isFalse);
        expect(await repo().activeSession(), isNull);
        expect(await ops('duty_session'), isEmpty, reason: 'discarded');
        expect(c.read(locationPolicyProvider).accepted, isTrue);
      },
    );

    test(
      'policy_not_accepted also forgets the acceptance so A05 returns',
      () async {
        await acceptPolicy(c);
        await controller().goOnDuty();
        deps.api.validate = (op) => op.entity == 'duty_session'
            ? const SyncError('policy_not_accepted', 'accept v2')
            : null;
        await c.read(syncEngineProvider).syncNow();
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);
        expect(state().onDuty, isFalse);
        expect(state().notice, DutyNotice.policyNotAccepted);
        expect(c.read(locationPolicyProvider).accepted, isFalse);
        expect(
          await controller().goOnDuty(),
          DutyStartResult.policyNotAccepted,
        );
      },
    );
  });

  group('restart', () {
    test('restore resumes an open session: service and sampler again, '
        'cadence seeded from the last point, prompt rescheduled', () async {
      await acceptPolicy(c);
      await controller().goOnDuty();
      await emit(fixAt(dutyT0));
      final id = state().active!.id;
      c.dispose();
      // "App killed": fresh container over the same database.
      c = deps.container();
      deps.clock.advance(const Duration(minutes: 5));
      expect(c.read(dutyControllerProvider).restored, isFalse);
      await c.read(dutyControllerProvider.notifier).restore();
      final s = c.read(dutyControllerProvider);
      expect(s.restored, isTrue);
      expect(s.onDuty, isTrue);
      expect(s.active!.id, id);
      expect(s.elapsed, const Duration(minutes: 5));
      // Resuming flushes what was buffered before the restart.
      expect(s.pointsPending, 0);
      expect(await ops('location_batch'), hasLength(1));
      expect(deps.sampler.starts, 2);
      expect(deps.service.starts, 2);
      expect(deps.alerts.pending, isNotNull);
      // Seeded cadence: a fix 1 minute after the stored point is dropped.
      await emit(fixAt(dutyT0.add(const Duration(minutes: 1)), east: 5));
      expect(await deps.db.select(deps.db.locationBuffer).get(), hasLength(1));
    });

    test(
      'restore with nothing open leaves duty off and starts nothing',
      () async {
        await controller().restore();
        expect(state().restored, isTrue);
        expect(state().onDuty, isFalse);
        expect(deps.sampler.starts, 0);
        expect(deps.service.starts, 0);
      },
    );
  });
}

import 'dart:convert';

import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'duty_harness.dart';

void main() {
  late DutyDeps deps;

  setUp(() => deps = DutyDeps());
  tearDown(() => deps.dispose());

  test('starts blocked: the bundled policy is current and nothing is '
      'accepted', () async {
    final c = deps.container();
    addTearDown(c.dispose);
    final policy = c.read(locationPolicyProvider.notifier);
    await policy.load();
    final s = c.read(locationPolicyProvider);
    expect(s.loaded, isTrue);
    expect(s.accepted, isFalse);
    expect(s.needsReacceptance, isFalse);
    expect(s.current.version, '2026-09-v1');
    expect(s.duty, const DutyPolicy());
  });

  test('accept stores version, hash, timestamp and device in kv and queues '
      'a policy_acceptance op', () async {
    final c = deps.container();
    addTearDown(c.dispose);
    await acceptPolicy(c);
    final s = c.read(locationPolicyProvider);
    expect(s.accepted, isTrue);
    expect(s.acceptedVersion, '2026-09-v1');
    expect(s.acceptedHash, LocationPolicyDoc.bundled().textHash);
    expect(s.acceptedAt, dutyT0);

    final stored = Map<String, Object?>.from(
      jsonDecode(
        (await deps.db.getValue(LocationPolicyController.acceptanceKey))!,
      ) as Map,
    );
    expect(stored['version'], '2026-09-v1');
    expect(stored['text_hash'], s.acceptedHash);
    expect(stored['device_id'], 'device-1');
    expect(stored['accepted_at'], dutyT0.toIso8601String());

    final ops = await outboxRows(deps.db);
    expect(ops, hasLength(1));
    expect(ops.single.entity, 'policy_acceptance');
    expect(ops.single.action, 'create');
    expect(ops.single.state, 'queued');
    final payload = SyncStore.payloadOf(ops.single);
    expect(payload['policy_key'], 'location_policy');
    expect(payload['version'], '2026-09-v1');
    expect(payload['text_hash'], s.acceptedHash);
    expect(payload['device_id'], 'device-1');
    expect(payload['app_version'], '0.1.0+1');
    expect(payload['accepted_at'], dutyT0.toIso8601String());
    expect(payload['id'], 'op-0001');

    // Syncs as a create the fake server applies.
    final report = await c.read(syncEngineProvider).syncNow();
    expect(report.applied, 1);
    expect(deps.api.appliedOps.single.entity, 'policy_acceptance');
  });

  test('the acceptance survives a restart (new container, same db)', () async {
    final c1 = deps.container();
    await acceptPolicy(c1);
    c1.dispose();
    final c2 = deps.container();
    addTearDown(c2.dispose);
    await c2.read(locationPolicyProvider.notifier).load();
    expect(c2.read(locationPolicyProvider).accepted, isTrue);
  });

  test(
    'a newer version from the server re-prompts and blocks duty again',
    () async {
      final c = deps.container();
      addTearDown(c.dispose);
      await acceptPolicy(c);
      deps.policyApi.location = const LocationPolicyDoc(
        version: '2026-10-v2',
        textHash: 'h2',
        text: <String, String>{'en': 'New text', 'te': 'కొత్త'},
      );
      deps.policyApi.duty = DutyPolicy.fromJson(const <String, Object?>{
        'auto_end_local_time': '19:00',
        'upload_interval_s': 600,
      });
      final newer = await c.read(locationPolicyProvider.notifier).refresh();
      expect(newer, isTrue);
      final s = c.read(locationPolicyProvider);
      expect(s.accepted, isFalse);
      expect(s.needsReacceptance, isTrue);
      expect(s.current.version, '2026-10-v2');
      expect(s.current.textFor('te'), 'కొత్త');
      expect(s.duty.autoEndLocalTime, '19:00');
      expect(s.duty.uploadInterval, const Duration(minutes: 10));
      // Cached: a fresh container sees the new version offline.
      final c2 = deps.container();
      addTearDown(c2.dispose);
      await c2.read(locationPolicyProvider.notifier).load();
      expect(c2.read(locationPolicyProvider).current.version, '2026-10-v2');
      expect(c2.read(locationPolicyProvider).accepted, isFalse);
      // Accepting the new version unblocks; the op carries the new hash.
      await c2.read(locationPolicyProvider.notifier).accept();
      expect(c2.read(locationPolicyProvider).accepted, isTrue);
      final ops = await outboxRows(deps.db);
      expect(SyncStore.payloadOf(ops.last)['text_hash'], 'h2');
    },
  );

  test('the same version from the server does not re-prompt', () async {
    final c = deps.container();
    addTearDown(c.dispose);
    await acceptPolicy(c);
    expect(await c.read(locationPolicyProvider.notifier).refresh(), isFalse);
    expect(c.read(locationPolicyProvider).accepted, isTrue);
  });

  test('offline refresh keeps the bundled copy and defaults', () async {
    final c = deps.container();
    addTearDown(c.dispose);
    deps.policyApi.offline = true;
    expect(await c.read(locationPolicyProvider.notifier).refresh(), isFalse);
    final s = c.read(locationPolicyProvider);
    expect(s.current, LocationPolicyDoc.bundled());
    expect(s.duty, const DutyPolicy());
  });

  test(
    'markNotAccepted (server said policy_not_accepted) blocks again',
    () async {
      final c = deps.container();
      addTearDown(c.dispose);
      await acceptPolicy(c);
      await c.read(locationPolicyProvider.notifier).markNotAccepted();
      expect(c.read(locationPolicyProvider).accepted, isFalse);
      expect(
        await deps.db.getValue(LocationPolicyController.acceptanceKey),
        isNull,
      );
    },
  );
}

import 'dart:async';
import 'dart:convert';

import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter_test/flutter_test.dart';

/// Farmer app data layer (FM-002, FM-003, FM-010, FM-011, FM-015, NF-002).
Map<String, Object?> _farmer({
  List<Map<String, Object?>> consents = const <Map<String, Object?>>[],
}) => <String, Object?>{
  'id': 'f-1',
  'name': 'Lakshmi Devi',
  'village_id': 'v-1',
  'registered_by': 'officer-1',
  'source': 'field_officer',
  'version': 3,
  'officer': <String, Object?>{
    'id': 'officer-1',
    'name': 'Ramesh Kumar',
    'phone': '+919100000001',
  },
  'farms': <Object?>[
    <String, Object?>{
      'id': 'farm-1',
      'area_acres': '2.50',
      'soil': 'black',
      'irrigation': 'borewell',
      'version': 2,
      'crop_plots': <Object?>[
        <String, Object?>{
          'id': 'plot-1',
          'farm_id': 'farm-1',
          'crop_id': 'crop-cotton',
          'stage': 'flowering',
          'version': 1,
        },
      ],
    },
  ],
  'consents': consents,
};

Map<String, Object?> _consent(
  String id,
  String purpose, {
  bool granted = true,
}) => <String, Object?>{
  'id': id,
  'purpose': purpose,
  'version': '2026-09-v1',
  'granted_at': granted ? '2026-09-01T05:00:00Z' : null,
  'withdrawn_at': granted ? null : '2026-09-02T05:00:00Z',
  'channel': 'officer',
  'created_at': '2026-09-01T05:00:00Z',
};

void main() {
  late AppDatabase db;
  late FakeKisanApi api;
  late KisanRepository repo;
  late DateTime now;
  var n = 0;
  var queued = 0;

  setUp(() {
    db = openInMemoryDatabase();
    now = DateTime.utc(2026, 9, 19, 4, 30);
    api = FakeKisanApi(clock: () => now, farmerRecord: _farmer());
    queued = 0;
    repo = KisanRepository(
      db: db,
      api: api,
      outbox: Outbox(db, clock: () => now, ids: () => 'op-${++n}'),
      clock: () => now,
      ids: () => 'id-${++n}',
      onQueued: () => queued += 1,
    );
  });

  tearDown(() => db.close());

  test('the farmer id is asked once and remembered', () async {
    expect(await repo.farmerId(), 'f-1');
    api.offline = true;
    expect(await repo.farmerId(), 'f-1');
    expect(api.calls.where((c) => c == 'GET /v1/farmers'), hasLength(1));
  });

  test(
    'FM-003: the profile is cached with its fetch time and parsed',
    () async {
      expect(await repo.refreshProfile(), isTrue);
      final cached = await repo.watchProfile().first;
      expect(cached!.asOf, now);
      final p = cached.value;
      expect(p.registeredByOfficer, isTrue);
      expect(p.officer!.firstName, 'Ramesh');
      expect(p.farms.single.plots.single.stage, 'flowering');
      expect(p.farms.single.areaAcres, 2.5);

      // Offline: the refresh fails and the cache stays.
      api.offline = true;
      now = now.add(const Duration(hours: 5));
      expect(await repo.refreshProfile(), isFalse);
      expect(
        (await repo.watchProfile().first)!.asOf,
        DateTime.utc(2026, 9, 19, 4, 30),
      );
    },
  );

  test('FM-003: a stage change is a PATCH with the row version, then a '
      'refresh', () async {
    await repo.refreshProfile();
    final plot = (await repo.watchProfile().first)!.value.plots.single;
    expect(await repo.setPlotStage(plot, 'fruiting'), KisanWrite.done);
    expect(api.writes.last.$1, 'PATCH /v1/crop-plots/plot-1');
    expect(api.writes.last.$2, <String, Object?>{
      'version': 1,
      'stage': 'fruiting',
    });
    final after = (await repo.watchProfile().first)!.value.plots.single;
    expect(after.stage, 'fruiting');
    expect(after.version, 2);
    // A stale version is refused and the profile re-fetched.
    expect(await repo.setPlotStage(plot, 'maturity'), KisanWrite.refused);
    api.offline = true;
    expect(await repo.setPlotStage(after, 'maturity'), KisanWrite.offline);
  });

  test('FM-002: consent state is the newest row per purpose; the stream '
      'follows refreshes and grants', () async {
    api.farmerRecord = _farmer(
      consents: <Map<String, Object?>>[_consent('c-1', 'data')],
    );
    final states = <ConsentState>[];
    final sub = repo.watchConsents().listen(states.add);
    await pumpEventQueue();
    expect(states.last.dataGranted, isFalse);

    await repo.refreshProfile();
    await pumpEventQueue();
    expect(states.last.dataGranted, isTrue);
    expect(states.last.marketingGranted, isFalse);

    now = now.add(const Duration(days: 20));
    expect(
      await repo.recordConsent('marketing', granted: true, language: 'te'),
      KisanWrite.done,
    );
    await pumpEventQueue();
    expect(states.last.marketingGranted, isTrue);
    now = now.add(const Duration(minutes: 1));
    expect(
      await repo.recordConsent('marketing', granted: false, language: 'te'),
      KisanWrite.done,
    );
    await pumpEventQueue();
    expect(states.last.marketingGranted, isFalse);
    expect(states.last.marketing!.at, now);
    expect(states.last.dataGranted, isTrue);
    unawaited(sub.cancel());
  });

  test('FM-002 offline: the grant is a queued consent_record create and '
      'counts as pending', () async {
    await repo.farmerId();
    api.offline = true;
    expect(
      await repo.recordConsent('data', granted: true, language: 'hi'),
      KisanWrite.queued,
    );
    expect(queued, 1);
    final op = (await db.select(db.outboxTable).get()).single;
    expect(op.entity, 'consent_record');
    expect(jsonDecode(op.payload), <String, Object?>{
      'farmer_id': 'f-1',
      'purpose': 'data',
      'granted': true,
      'language': 'hi',
      'id': op.entityId,
    });
    final state = await repo.watchConsents().first;
    expect(state.dataGranted, isTrue);
    expect(state.pending, isTrue);
  });

  test('FM-011: prompts from push payloads and the sync feed; answered '
      'and expired ones disappear', () async {
    await repo.receivePush(<String, Object?>{
      'type': 'visit_confirm',
      'visit_id': 'v-1',
      'token': 'tok-1',
      'officer_name': 'Ramesh Kumar',
      'expires_at': now.add(const Duration(hours: 1)).toIso8601String(),
    });
    await LocalEntities(db).write(
      SyncEntities.visitConfirmation,
      'conf-2',
      <String, Object?>{
        'visit_id': 'v-2',
        'channel': 'app_push',
        'status': 'pending',
        'expires_at': now.add(const Duration(hours: 2)).toIso8601String(),
      },
      version: 1,
      dirty: false,
      now: now,
    );
    var prompts = await repo.prompts();
    expect(prompts.map((p) => p.visitId).toSet(), <String>{'v-1', 'v-2'});
    expect(
      prompts.firstWhere((p) => p.visitId == 'v-1').officerFirstName,
      'Ramesh',
    );
    expect(prompts.firstWhere((p) => p.visitId == 'v-2').token, isNull);

    await repo.dismissPrompt('v-2');
    now = now.add(const Duration(minutes: 61));
    prompts = await repo.prompts();
    expect(prompts, isEmpty);
  });

  test('FM-011: confirm online with rating; offline it is queued with the '
      'token', () async {
    api.visitTokens['v-1'] = 'tok-1';
    expect(
      await repo.confirmVisit(
        visitId: 'v-1',
        token: 'tok-1',
        rating: 5,
        reason: 'useful_advice',
      ),
      KisanWrite.done,
    );
    expect(api.confirmedVisits['v-1'], (5, 'useful_advice'));
    // Already confirmed counts as done.
    expect(
      await repo.confirmVisit(visitId: 'v-1', token: 'tok-1'),
      KisanWrite.done,
    );
    expect(
      await repo.confirmVisit(visitId: 'v-9', token: 'bad'),
      KisanWrite.refused,
    );

    api.offline = true;
    expect(
      await repo.confirmVisit(
        visitId: 'v-3',
        token: 'tok-3',
        channel: 'qr',
        rating: 2,
        reason: 'too_short',
      ),
      KisanWrite.queued,
    );
    final op = (await db.select(db.outboxTable).get()).single;
    expect(op.entity, 'visit_confirmation');
    expect(jsonDecode(op.payload), containsPair('token', 'tok-3'));
    expect(jsonDecode(op.payload), containsPair('rating', 2));
    expect(jsonDecode(op.payload), containsPair('channel', 'qr'));
  });

  test('FM-015: deletion request and its status', () async {
    expect(await repo.watchDeletion().first, isNull);
    expect(await repo.requestDeletion(reason: 'farmer_app'), KisanWrite.done);
    final d = (await repo.watchDeletion().first)!;
    expect(d.status, 'received');
    expect(d.ticketId, startsWith('DEL-'));
    expect(d.dueBy, now.add(const Duration(days: 30)));
    expect(api.writes.last.$2, <String, Object?>{'reason': 'farmer_app'});
    expect(await repo.refreshDeletion(), isTrue);
    api.offline = true;
    expect(await repo.requestDeletion(), KisanWrite.offline);
    expect(await repo.watchDeletion().first, d);
  });

  test('ConfirmToken reads the claims of a visit token', () {
    String part(Map<String, Object?> m) =>
        base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
    final raw =
        '${part(<String, Object?>{'alg': 'HS256'})}.'
        '${part(<String, Object?>{'typ': 'visit_confirm', 'vid': 'v-7', 'cid': 'c-7', 'ch': 'qr', 'exp': 1790000000})}.sig';
    final t = ConfirmToken.decode(raw)!;
    expect(t.visitId, 'v-7');
    expect(t.channel, 'qr');
    expect(t.expiresAt!.isUtc, isTrue);
    expect(ConfirmToken.decode('not-a-token'), isNull);
    expect(
      ConfirmToken.decode(
        '${part(<String, Object?>{})}.${part(<String, Object?>{'typ': 'access', 'vid': 'x'})}.s',
      ),
      isNull,
    );
  });
}

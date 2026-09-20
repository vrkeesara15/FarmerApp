import 'dart:typed_data';

import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter_test/flutter_test.dart';

final DateTime t0 = DateTime.utc(2026, 9, 20, 0, 30);

class _Ids {
  int _n = 0;
  String call() => 'id-${(++_n).toString().padLeft(4, '0')}';
}

({AppDatabase db, FakeFieldApi api, FieldRepository repo}) build() {
  final db = openInMemoryDatabase();
  final api = FakeFieldApi();
  final ids = _Ids();
  final repo = FieldRepository(
    db: db,
    api: api,
    outbox: Outbox(db, clock: () => t0, ids: ids.call),
    clock: () => t0,
    ids: ids.call,
  );
  return (db: db, api: api, repo: repo);
}

void main() {
  test('every M7 field entity is a writable sync entity', () {
    for (final entity in FieldEntities.all) {
      expect(SyncEntities.writable, contains(entity));
      expect(LocalEntities.isKnown(entity), isTrue);
      expect(LocalEntities.conflictRules[entity], isNotNull);
      expect(
        LocalEntities.conflictRules[entity],
        FieldEntities.conflictRules[entity],
      );
    }
  });

  test('istDateKey and istMonthBounds follow the IST day', () {
    // 2026-09-20 00:30 UTC is 06:00 IST the same day.
    expect(istDateKey(t0), '2026-09-20');
    expect(istMonthKey(t0), '2026-09');
    expect(istMonthBounds(t0), ('2026-09-01', '2026-09-20'));
    // 18:45 UTC is already the next IST day.
    expect(istDateKey(DateTime.utc(2026, 9, 20, 18, 45)), '2026-09-21');
  });

  test('a pull never undoes a queued read receipt', () async {
    final h = build();
    addTearDown(h.db.close);
    h.api.inbox = Inbox(
      unread: 1,
      items: <InboxItem>[
        InboxItem(
          id: 'n1',
          kind: 'order_status',
          titleKey: 'notification.order_status.title',
          bodyKey: 'notification.order_status.body',
          route: '/orders/o1',
          createdAt: t0,
        ),
      ],
    );
    await h.repo.refreshInbox();
    expect((await h.repo.inbox()).unread, 1);

    await h.repo.markRead('n1');
    expect((await h.repo.inbox()).unread, 0);

    // The server has not seen the receipt yet and still says "unread".
    await h.repo.refreshInbox();
    expect((await h.repo.inbox()).unread, 0);
  });

  test('marking a row read twice queues one op', () async {
    final h = build();
    addTearDown(h.db.close);
    h.api.inbox = Inbox(
      unread: 1,
      items: <InboxItem>[
        InboxItem(
          id: 'n1',
          kind: 'order_status',
          titleKey: 'k',
          bodyKey: 'k',
          route: '/orders/o1',
          createdAt: t0,
        ),
      ],
    );
    await h.repo.refreshInbox();
    await h.repo.markRead('n1');
    await h.repo.markRead('n1');
    final ops = await SyncStore(h.db).opsIn(<String>['queued']);
    expect(
      ops.where((o) => o.entity == FieldEntities.notification),
      hasLength(1),
    );
  });

  test('a gap reason is a create the first time and an update after', () async {
    final h = build();
    addTearDown(h.db.close);
    await h.repo.setGapReason('gap-1', GapReason.network);
    await h.repo.setGapReason('gap-1', GapReason.vehicle, note: 'Puncture');

    final ops = <SyncOp>[
      for (final row in await SyncStore(h.db).opsIn(<String>['queued']))
        if (row.entity == FieldEntities.trackGap) SyncStore.toOp(row),
    ];
    expect(ops.map((o) => o.action.name), <String>['create', 'update']);
    expect(ops.last.payload['reason'], 'vehicle');
    expect(ops.last.payload['note'], 'Puncture');
  });

  test('the cached day carries the reasons queued on this device', () async {
    final h = build();
    addTearDown(h.db.close);
    h.api.days['2026-09-20'] = DayTimeline(
      date: '2026-09-20',
      km: 12,
      fromServer: true,
      gaps: <DayGap>[
        DayGap(
          id: 'gap-1',
          start: t0,
          end: t0.add(const Duration(hours: 1)),
          durationS: 3600,
        ),
      ],
    );
    await h.repo.refreshDay('2026-09-20');
    expect(
      (await h.repo.day('2026-09-20')).value!.unexplainedGaps,
      hasLength(1),
    );

    await h.repo.setGapReason('gap-1', GapReason.personalBreak, note: 'Lunch');
    final day = (await h.repo.day('2026-09-20')).value!;
    expect(day.unexplainedGaps, isEmpty);
    expect(day.gaps.single.reason, GapReason.personalBreak);
    expect(day.gaps.single.note, 'Lunch');
  });

  test('a queued claim shows in the statement before it syncs', () async {
    final h = build();
    addTearDown(h.db.close);
    h.api.statements['2026-09'] = const TravelStatement(
      month: '2026-09',
      kmTotal: 100,
      kmCappedTotal: 100,
      taTotalPaise: 30000,
      payablePaise: 30000,
    );
    await h.repo.refreshTravel('2026-09');
    expect((await h.repo.travel('2026-09')).value!.claims, isEmpty);

    await h.repo.addClaim(
      claimDate: '2026-09-20',
      type: ClaimType.fuel,
      amountPaise: 25000,
      receiptPath: 'memory://receipt.jpg',
      receiptBytes: Uint8List.fromList(<int>[1, 2, 3]),
      note: 'Diesel',
    );
    final claims = (await h.repo.travel('2026-09')).value!.claims;
    expect(claims, hasLength(1));
    expect(claims.single.status, ClaimStatus.queued);
    expect(claims.single.pending, isTrue);
    expect(claims.single.receiptUri, startsWith('upload:'));
  });

  test('explaining a flag updates the cached copy', () async {
    final h = build();
    addTearDown(h.db.close);
    h.api.flags = <MyFlag>[
      MyFlag(
        id: 'f1',
        ruleId: 'VA-E06',
        severity: 'low',
        title: 'Idle',
        state: 'open',
        createdAt: t0,
        canExplain: true,
      ),
    ];
    await h.repo.refreshFlags();
    expect((await h.repo.flags()).value!.single.explanations, isEmpty);

    await h.repo.explainFlag('f1', 'I was at the bus stop.');
    final flags = (await h.repo.flags()).value!;
    expect(flags.single.explanations.single.body, 'I was at the bus stop.');
    // VA-005: an open flag never carries an outcome.
    expect(flags.single.outcome, isNull);
  });

  test(
    'clearCaches drops every officer view but keeps the sync rows',
    () async {
      final h = build();
      addTearDown(h.db.close);
      h.api.days['2026-09-20'] = const DayTimeline(
        date: '2026-09-20',
        fromServer: true,
      );
      h.api.statements['2026-09'] = const TravelStatement(month: '2026-09');
      await h.repo.refreshDay('2026-09-20');
      await h.repo.refreshTravel('2026-09');
      await h.repo.setGapReason('gap-1', GapReason.other);

      await h.repo.clearCaches();
      expect((await h.repo.day('2026-09-20')).isEmpty, isTrue);
      expect((await h.repo.travel('2026-09')).isEmpty, isTrue);
      // The queued op survives: it is still owed to the server.
      expect(await SyncStore(h.db).opsIn(<String>['queued']), hasLength(1));
    },
  );

  test('demo plot transitions follow the server lifecycle', () async {
    final h = build();
    addTearDown(h.db.close);
    final plot = await h.repo.createDemoPlot(
      farmerId: 'farmer-1',
      cropPlotId: 'plot-1',
      treatment: 'Own brand',
    );
    expect(plot.status, DemoStatus.created);
    expect(plot.nextStates, <DemoStatus>[DemoStatus.active]);

    // `created -> reported` is not a legal move and is ignored.
    await h.repo.transitionDemoPlot(plot.id, DemoStatus.reported);
    expect((await h.repo.demoPlots()).single.status, DemoStatus.created);

    await h.repo.transitionDemoPlot(plot.id, DemoStatus.active);
    expect((await h.repo.demoPlots()).single.status, DemoStatus.active);

    await h.repo.enterYield(
      plot.id,
      demoKgPerAcre: 1200,
      practiceKgPerAcre: 1000,
    );
    final harvested = (await h.repo.demoPlots()).single;
    expect(harvested.status, DemoStatus.harvested);
    expect(harvested.gainPct, closeTo(20, 0.001));

    await h.repo.transitionDemoPlot(plot.id, DemoStatus.reported);
    expect((await h.repo.demoPlots()).single.status, DemoStatus.reported);
  });

  test('a farmer attends a meeting once', () async {
    final h = build();
    addTearDown(h.db.close);
    final meeting = await h.repo.createMeeting(
      villageId: 'village-1',
      topic: 'Pest management',
      lat: 17.4,
      lon: 78.4,
    );
    await h.repo.addAttendance(
      meetingId: meeting.id,
      method: AttendanceMethod.qr,
      farmerId: 'farmer-1',
      token: 'a.b.c',
    );
    await h.repo.addAttendance(
      meetingId: meeting.id,
      method: AttendanceMethod.otp,
      farmerId: 'farmer-1',
      code: '123456',
    );
    // Two ops go out (the server is the arbiter and returns the first row),
    // but the officer sees one attendee.
    expect((await h.repo.meetings()).single.attendance, hasLength(1));

    await h.repo.closeMeeting(meeting.id);
    expect((await h.repo.meetings()).single.open, isFalse);
  });

  test('the trend counts verified visits per IST day', () async {
    final h = build();
    addTearDown(h.db.close);
    final entities = LocalEntities(h.db);
    Future<void> visit(String id, DateTime at, String status) => entities.write(
      SyncEntities.visit,
      id,
      <String, Object?>{
        'farmer_id': 'farmer-1',
        'checkin_at': at.toIso8601String(),
        'checkin_lat': 17.4,
        'checkin_lon': 78.4,
        'status': status,
      },
      version: 1,
      dirty: false,
      now: t0,
    );
    await visit('v1', t0, 'verified');
    await visit('v2', t0.subtract(const Duration(days: 1)), 'verified');
    await visit('v3', t0.subtract(const Duration(days: 1)), 'partial');
    await visit('v4', t0.subtract(const Duration(days: 40)), 'verified');

    final trend = await h.repo.verifiedVisitTrend();
    expect(trend, hasLength(14));
    expect(trend.last, 1);
    expect(trend[12], 1);
    expect(trend.reduce((a, b) => a + b), 2);
  });
}

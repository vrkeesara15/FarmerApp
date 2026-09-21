import 'package:farmerapp_core/farmerapp_core.dart';

import '../farmers/agent_harness.dart';

/// 2026-09-21 (IST) — the day the M7 officer fixtures live on.
const String testDate = '2026-09-20';

/// The month of [testDate].
const String testMonth = '2026-09';

/// A beat plan with two farmers and one village, each with reasons.
BeatPlan beatFixture({String status = 'generated', int version = 3}) =>
    BeatPlan(
      id: 'beat-1',
      planDate: testDate,
      status: status,
      target: 10,
      version: version,
      items: const <BeatItem>[
        BeatItem(
          id: 'item-1',
          kind: 'farmer',
          farmerId: 'farmer-1',
          farmerName: 'Ramesh Reddy',
          villageId: 'village-1',
          villageName: 'Kondapur',
          priority: 1,
          reasons: <BeatReasonCode>[
            BeatReasonCode.followUpDue,
            BeatReasonCode.creditDue,
          ],
        ),
        BeatItem(
          id: 'item-2',
          kind: 'farmer',
          farmerId: 'farmer-2',
          farmerName: 'Lakshmi Devi',
          villageId: 'village-1',
          villageName: 'Kondapur',
          priority: 2,
          reasons: <BeatReasonCode>[BeatReasonCode.pestAlert],
        ),
        BeatItem(
          id: 'item-3',
          kind: 'village',
          villageId: 'village-1',
          villageName: 'Kondapur',
          priority: 3,
          reasons: <BeatReasonCode>[BeatReasonCode.demoPlotStage],
        ),
      ],
    );

/// A day with a track, one stop, one visit and one unexplained gap.
///
/// VV-006: [processed] drives the duty session the day's km hang off — an
/// ended session with a processed km, or one still open, which is what the
/// server sends while the officer is on duty and its km are an estimate.
DayTimeline dayFixture({GapReason? reason, bool processed = true}) =>
    DayTimeline(
      date: testDate,
      km: 24.5,
      fromServer: true,
      sessions: <DaySession>[
        DaySession(
          id: 'duty-1',
          startAt: DateTime.utc(2026, 9, 20, 3, 30),
          endAt: processed ? DateTime.utc(2026, 9, 20, 12, 30) : null,
          km: processed ? 24.5 : null,
          endReason: processed ? 'manual' : null,
        ),
      ],
      track: const <GeoPoint>[
        GeoPoint(17.4, 78.4),
        GeoPoint(17.41, 78.41),
        GeoPoint(17.42, 78.42),
      ],
      stops: <DayStop>[
        DayStop(
          point: const GeoPoint(17.41, 78.41),
          start: DateTime.utc(2026, 9, 20, 5),
          end: DateTime.utc(2026, 9, 20, 5, 20),
          durationS: 1200,
        ),
      ],
      visits: <DayVisit>[
        DayVisit(
          id: 'visit-1',
          point: const GeoPoint(17.41, 78.41),
          checkinAt: DateTime.utc(2026, 9, 20, 5),
          farmerName: 'Ramesh Reddy',
          status: 'verified',
          score: 88,
        ),
      ],
      gaps: <DayGap>[
        DayGap(
          id: 'gap-1',
          start: DateTime.utc(2026, 9, 20, 7),
          end: DateTime.utc(2026, 9, 20, 8),
          durationS: 3600,
          dutySessionId: 'duty-1',
          reason: reason,
        ),
      ],
      travel: const TravelDay(
        date: testDate,
        km: 24.5,
        kmCapped: 24.5,
        capKm: 150,
        ratePerKmPaise: 300,
        taPaise: 7350,
        sessions: 1,
      ),
    );

/// Performance with targets and a trend.
Performance performanceFixture() =>
    const Performance(
      from: '$testMonth-01',
      to: testDate,
      dutyDays: 16,
      visits: 92,
      verifiedVisits: 74,
      farmersAdded: 23,
      confirmationRate: 0.64,
      salesNetPaise: 128000000,
      collectionsPaise: 45000000,
      kmPerDay: 32.4,
      rank: 3,
      incentiveEarnedPaise: 69100,
    ).with2(
      targets: const PerformanceTargets(
        visitsVerified: 100,
        newFarmers: 30,
        salesPaise: 200000000,
        collectionsPaise: 60000000,
      ),
    );

/// A travel statement with three days and one approved claim.
TravelStatement travelFixture({bool processed = true}) => TravelStatement(
  month: testMonth,
  ratePerKmPaise: 300,
  kmTotal: 168,
  kmCappedTotal: 160,
  taTotalPaise: 48000,
  claimsApprovedPaise: 45000,
  payablePaise: 93000,
  days: <TravelDay>[
    TravelDay(
      date: '2026-09-20',
      km: 24.5,
      kmCapped: 24.5,
      capKm: 150,
      ratePerKmPaise: 300,
      taPaise: 7350,
      sessions: 1,
      openSession: !processed,
    ),
    const TravelDay(
      date: '2026-09-19',
      km: 168,
      kmCapped: 150,
      capKm: 150,
      ratePerKmPaise: 300,
      taPaise: 45000,
      sessions: 2,
    ),
  ],
  claims: const <TravelClaim>[
    TravelClaim(
      id: 'claim-server-1',
      claimDate: '2026-09-18',
      type: ClaimType.fuel,
      amountPaise: 45000,
      receiptUri: 'blob://receipt-1',
      status: ClaimStatus.approved,
    ),
  ],
);

/// One open flag (no outcome) and one resolved flag (with an outcome).
List<MyFlag> flagsFixture() => <MyFlag>[
  MyFlag(
    id: 'flag-open',
    ruleId: 'VA-E06',
    ruleTitle: 'Duty with no activity',
    severity: 'low',
    title: 'Three hours on duty without a visit',
    state: 'open',
    createdAt: DateTime.utc(2026, 9, 19, 4),
    canExplain: true,
    metrics: const <String, Object?>{'idle_hours': 3},
  ),
  MyFlag(
    id: 'flag-resolved',
    ruleId: 'VA-E07',
    ruleTitle: 'TA claim vs km',
    severity: 'medium',
    title: 'Claim km differs from the tracked km',
    state: 'resolved',
    createdAt: DateTime.utc(2026, 9, 10, 4),
    outcome: FlagOutcome(
      status: 'resolved_invalid',
      resolvedAt: DateTime.utc(2026, 9, 12, 4),
      label: 'Explained',
      note: 'Bus fare, not vehicle km.',
    ),
    explanations: <FlagExplanation>[
      FlagExplanation(
        id: 'exp-1',
        body: 'I took the bus that day.',
        createdAt: DateTime.utc(2026, 9, 11, 4),
      ),
    ],
  ),
];

/// Two inbox rows, the first unread.
Inbox inboxFixture() => Inbox(
  unread: 1,
  items: <InboxItem>[
    InboxItem(
      id: 'notif-1',
      kind: 'beat_plan_ready',
      titleKey: 'notification.beat_plan_ready.title',
      bodyKey: 'notification.beat_plan_ready.body',
      route: '/beat/$testDate',
      createdAt: DateTime.utc(2026, 9, 20, 0, 30),
      data: const <String, Object?>{'beat_plan_id': 'beat-1'},
    ),
    InboxItem(
      id: 'notif-2',
      kind: 'travel_claim_decided',
      titleKey: 'notification.travel_claim_decided.title',
      bodyKey: 'notification.travel_claim_decided.body.approved',
      route: '/travel/claims/claim-server-1',
      createdAt: DateTime.utc(2026, 9, 19, 9),
      readAt: DateTime.utc(2026, 9, 19, 10),
    ),
  ],
);

/// Loads every M7 officer view into [deps]' local cache, as a sync and a
/// refresh would.
Future<void> seedFieldCaches(
  AgentDeps deps, {
  bool beat = true,
  bool day = true,
  bool performance = true,
  bool travel = true,
  bool flags = true,
  bool inbox = true,

  /// VV-006: false leaves the day's duty session open, so the server's km
  /// are not the processed ones and the screens must say so.
  bool processed = true,
}) async {
  if (beat) deps.field.beats[testDate] = beatFixture();
  if (day) deps.field.days[testDate] = dayFixture(processed: processed);
  if (performance) deps.field.performanceOut = performanceFixture();
  if (travel) {
    deps.field.statements[testMonth] = travelFixture(processed: processed);
  }
  if (flags) deps.field.flags = flagsFixture();
  if (inbox) deps.field.inbox = inboxFixture();
  final c = deps.container();
  final repo = c.read(fieldRepositoryProvider);
  if (beat) await repo.refreshBeat(testDate);
  if (day) await repo.refreshDay(testDate);
  if (performance) {
    await repo.refreshPerformance(from: '$testMonth-01', to: testDate);
  }
  if (travel) await repo.refreshTravel(testMonth);
  if (flags) await repo.refreshFlags();
  if (inbox) await repo.refreshInbox();
  c.dispose();
}

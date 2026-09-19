import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:farmerapp_farmer/router.dart';
import 'package:farmerapp_farmer/screens/welcome_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'kisan_harness.dart';

/// FM-002: F04 two separate cards (data required, offers optional), read
/// aloud, recorded online or queued offline; F70 withdraws offers with a
/// new `granted: false` row and shows the current state.
void main() {
  late KisanDeps deps;

  setUp(() async {
    deps = KisanDeps()..seedWorld(dataConsent: false);
    await deps.signIn(welcomeDone: false);
  });
  tearDown(() => deps.dispose());

  AppButton continueButton(WidgetTester tester) =>
      tester.widget<AppButton>(find.byKey(const Key('consent-continue')));

  testWidgets('F04: two separate cards; Continue needs the data card only', (
    tester,
  ) async {
    usePhoneSurface(tester);
    await pumpApp(tester, deps.app(initialLocation: AppRoutes.consent));

    expect(find.text('Use my data to give crop advice'), findsOneWidget);
    expect(find.text('Send me offers and tips'), findsOneWidget);
    expect(find.text('Required'), findsOneWidget);
    expect(find.text('Optional'), findsOneWidget);
    expect(find.byType(Switch, skipOffstage: false), findsNWidgets(2));
    expect(continueButton(tester).onPressed, isNull);
    expect(find.byKey(const Key('consent-data-needed')), findsOneWidget);

    // Offers alone do not unlock the app.
    await tapIt(tester, find.byKey(const Key('consent-marketing')));
    expect(continueButton(tester).onPressed, isNull);
    // Data unlocks it; offers can be turned off again independently.
    await tapIt(tester, find.byKey(const Key('consent-data')));
    expect(continueButton(tester).onPressed, isNotNull);
    await tapIt(tester, find.byKey(const Key('consent-marketing')));
    expect(continueButton(tester).onPressed, isNotNull);
    await tapIt(tester, find.byKey(const Key('consent-marketing')));

    await tapIt(tester, find.byKey(const Key('consent-continue')));
    final writes = deps.kisan.writes
        .where((w) => w.$1 == 'POST /v1/farmers/f-1/consents')
        .map((w) => w.$2)
        .toList();
    expect(writes, <Map<String, Object?>>[
      <String, Object?>{'purpose': 'data', 'granted': true, 'language': 'en'},
      <String, Object?>{
        'purpose': 'marketing',
        'granted': true,
        'language': 'en',
      },
    ]);
    expect(find.byType(WelcomeScreen), findsOneWidget);
  });

  testWidgets('F04: each card reads its own text aloud', (tester) async {
    usePhoneSurface(tester);
    await pumpApp(tester, deps.app(initialLocation: AppRoutes.consent));
    await tapIt(tester, find.byKey(const Key('audio-f04_data')));
    await tapIt(tester, find.byKey(const Key('audio-f04_offers')));
    expect(deps.audio.played.map((p) => p.promptId), <String>[
      'f04_data',
      'f04_offers',
    ]);
    expect(deps.audio.played.first.text, contains('crop advice'));
    expect(deps.audio.played.last.text, contains('offers and tips'));
    expect(deps.audio.played.first.locale, const Locale('en'));
  });

  testWidgets('F04 offline: the grants are queued in the outbox and the '
      'farmer continues', (tester) async {
    usePhoneSurface(tester);
    deps.kisan.offline = true;
    deps.connectivity.online = false;
    await pumpApp(tester, deps.app(initialLocation: AppRoutes.consent));
    await tapIt(tester, find.byKey(const Key('consent-data')));
    await tapIt(tester, find.byKey(const Key('consent-continue')));

    expect(find.byType(WelcomeScreen), findsOneWidget);
    final ops = await real(tester, deps.db.select(deps.db.outboxTable).get);
    expect(ops.map((o) => (o.entity, o.action)).toList(), <(String, String)>[
      ('consent_record', 'create'),
      ('consent_record', 'create'),
    ]);
    expect(ops.first.payload, contains('"purpose":"data"'));
    expect(ops.first.payload, contains('"granted":true'));
    expect(ops.first.payload, contains('"farmer_id":"f-1"'));
    final c = deps.container();
    addTearDown(c.dispose);
    final state = await real(
      tester,
      () => c.read(kisanRepositoryProvider).watchConsents().first,
    );
    expect(state.dataGranted, isTrue);
    expect(state.pending, isTrue);
  });

  testWidgets('F70: withdraw offers any time (new row, granted false) and '
      'the current state is shown', (tester) async {
    usePhoneSurface(tester);
    deps.kisan.farmerRecord = farmerRecord(
      dataConsent: true,
      marketingConsent: true,
    );
    await deps.signIn();
    await pumpApp(tester, deps.app(initialLocation: AppRoutes.me));
    await settle(tester);
    expect(find.text('Offers and tips: on'), findsOneWidget);

    await tapIt(tester, find.byKey(const Key('me-consent')));
    expect(find.text('Given on 01-09-2026'), findsNWidgets(2));
    final toggle = tester.widget<Switch>(
      find.byKey(const Key('consent-marketing')),
    );
    expect(toggle.value, isTrue);

    await tapIt(tester, find.byKey(const Key('consent-marketing')));
    expect(deps.kisan.writes.last.$1, 'POST /v1/farmers/f-1/consents');
    expect(deps.kisan.writes.last.$2, <String, Object?>{
      'purpose': 'marketing',
      'granted': false,
      'language': 'en',
    });
    expect(
      tester.widget<Switch>(find.byKey(const Key('consent-marketing'))).value,
      isFalse,
    );
    expect(find.text('Stopped on 19-09-2026'), findsOneWidget);
    // The data consent is unchanged and explains how to stop it.
    expect(
      find.descendant(
        of: find.byKey(const Key('consent-state-data')),
        matching: find.text('Given on 01-09-2026'),
      ),
      findsOneWidget,
    );
    // The server has both rows: the grant and the withdrawal.
    final rows = (deps.kisan.farmerRecord!['consents']! as List)
        .whereType<Map<String, Object?>>()
        .where((r) => r['purpose'] == 'marketing')
        .toList();
    expect(rows, hasLength(2));
    expect(rows.last['withdrawn_at'], isNotNull);
  });
}

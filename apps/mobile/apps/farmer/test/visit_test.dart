import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:farmerapp_farmer/router.dart';
import 'package:farmerapp_farmer/screens/home_screen.dart';
import 'package:farmerapp_farmer/screens/visit/visit_rating_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'kisan_harness.dart';

/// FM-011: F60 prompt from a push (with token) or the sync feed, QR scan to
/// confirm, F61 five faces + quick reasons posted to
/// `/v1/visits/{id}/farmer-confirm`; F62 call / WhatsApp the officer.
void main() {
  late KisanDeps deps;

  setUp(() async {
    deps = KisanDeps()..seedWorld();
    await deps.signIn();
  });
  tearDown(() => deps.dispose());

  Future<void> push(WidgetTester tester, String visitId) =>
      real(tester, () async {
        final c = deps.container();
        await c.read(kisanRepositoryProvider).receivePush(<String, Object?>{
          'type': 'visit_confirm',
          'visit_id': visitId,
          'token': visitToken(visitId, channel: 'app_push'),
          'officer_name': 'Ramesh Kumar',
          'expires_at': t0.add(const Duration(hours: 24)).toIso8601String(),
        });
        c.dispose();
      });

  testWidgets('push: home asks "Did Ramesh visit your farm today?", Yes → '
      'five faces + reason → confirmed with the rating', (tester) async {
    usePhoneSurface(tester);
    deps.kisan.visitTokens['v-1'] = visitToken('v-1', channel: 'app_push');
    await push(tester, 'v-1');
    await pumpApp(tester, deps.app());

    expect(find.byKey(const Key('home-visit-prompt')), findsOneWidget);
    expect(find.text('Did Ramesh visit your farm today?'), findsOneWidget);
    await tapIt(tester, find.byKey(const Key('home-visit-prompt')));
    expect(find.byKey(const Key('visit-question')), findsOneWidget);
    await tapIt(tester, find.byKey(const Key('audio-f60_question')));
    expect(deps.audio.played.last.text, 'Did Ramesh visit your farm today?');

    await tapIt(tester, find.byKey(const Key('visit-yes')));
    expect(find.byType(VisitRatingScreen), findsOneWidget);
    expect(find.byType(Rating), findsOneWidget);
    final send = find.byKey(const Key('rating-send'));
    expect(tester.widget<AppButton>(send).onPressed, isNull);
    await tapIt(tester, find.text('Very good'));
    expect(find.byKey(const Key('reason-useful_advice')), findsOneWidget);
    await tapIt(tester, find.byKey(const Key('reason-useful_advice')));
    await tapIt(tester, send);

    expect(deps.kisan.confirmedVisits['v-1'], (5, 'useful_advice'));
    expect(deps.kisan.writes.last.$1, 'POST /v1/visits/v-1/farmer-confirm');
    expect(find.byKey(const Key('visit-confirmed')), findsOneWidget);
    await tapIt(tester, find.byKey(const Key('visit-done')));
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byKey(const Key('home-visit-prompt')), findsNothing);
  });

  testWidgets('QR: scan the officer\'s QR, rate, confirmed', (tester) async {
    usePhoneSurface(tester);
    final token = visitToken('v-7');
    deps.kisan.visitTokens['v-7'] = token;
    deps.scanner.enqueue(token);
    await pumpApp(tester, deps.app(initialLocation: AppRoutes.visitScan));
    await tapIt(tester, find.byKey(const Key('visit-scan')));
    expect(find.byType(VisitRatingScreen), findsOneWidget);
    await tapIt(tester, find.text('Bad'));
    await tapIt(tester, find.byKey(const Key('reason-too_short')));
    await tapIt(tester, find.byKey(const Key('rating-send')));
    expect(deps.kisan.confirmedVisits['v-7'], (2, 'too_short'));
  });

  testWidgets('QR that is not a visit QR is explained', (tester) async {
    usePhoneSurface(tester);
    deps.scanner.enqueue('https://example.com/not-a-token');
    await pumpApp(tester, deps.app(initialLocation: AppRoutes.visitScan));
    await tapIt(tester, find.byKey(const Key('visit-scan')));
    expect(find.textContaining('This is not a visit QR'), findsOneWidget);
    expect(find.byType(VisitRatingScreen), findsNothing);
  });

  testWidgets('sync-feed prompt without a token: Yes goes to the QR scan', (
    tester,
  ) async {
    usePhoneSurface(tester);
    await real(
      tester,
      () => LocalEntities(deps.db).write(
        SyncEntities.visitConfirmation,
        'conf-3',
        <String, Object?>{
          'visit_id': 'v-3',
          'channel': 'app_push',
          'status': 'pending',
          'expires_at': t0.add(const Duration(hours: 3)).toIso8601String(),
        },
        version: 1,
        dirty: false,
        now: t0,
      ),
    );
    await pumpApp(tester, deps.app(initialLocation: AppRoutes.visit('v-3')));
    expect(
      find.text('Did your field officer visit your farm today?'),
      findsOneWidget,
    );
    await tapIt(tester, find.byKey(const Key('visit-yes')));
    expect(find.byKey(const Key('visit-scan')), findsOneWidget);
  });

  testWidgets('No: the prompt is dismissed and nothing is confirmed', (
    tester,
  ) async {
    usePhoneSurface(tester);
    await push(tester, 'v-2');
    await pumpApp(tester, deps.app(initialLocation: AppRoutes.visit('v-2')));
    await tapIt(tester, find.byKey(const Key('visit-no')));
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byKey(const Key('home-visit-prompt')), findsNothing);
    expect(deps.kisan.confirmedVisits, isEmpty);
  });

  testWidgets('offline: the confirmation with rating is queued in the outbox', (
    tester,
  ) async {
    usePhoneSurface(tester);
    deps.kisan.offline = true;
    deps.connectivity.online = false;
    await push(tester, 'v-4');
    await pumpApp(tester, deps.app(initialLocation: AppRoutes.visit('v-4')));
    await tapIt(tester, find.byKey(const Key('visit-yes')));
    await tapIt(tester, find.text('Good'));
    await tapIt(tester, find.byKey(const Key('rating-send')));
    expect(
      find.text('Saved. We will send it when you are online.'),
      findsOneWidget,
    );
    final op = (await real(
      tester,
      deps.db.select(deps.db.outboxTable).get,
    )).single;
    expect(op.entity, 'visit_confirmation');
    expect(op.payload, contains('"visit_id":"v-4"'));
    expect(op.payload, contains('"rating":4'));
    expect(op.payload, contains('"channel":"app_push"'));
  });

  testWidgets('F62: call and WhatsApp the field officer', (tester) async {
    usePhoneSurface(tester);
    await real(tester, () async {
      final c = deps.container();
      await c.read(kisanRepositoryProvider).refreshProfile();
      c.dispose();
    });
    await pumpApp(tester, deps.app(initialLocation: AppRoutes.officer));
    expect(find.text('Ramesh Kumar'), findsOneWidget);
    await tapIt(tester, find.byKey(const Key('officer-call')));
    await tapIt(tester, find.byKey(const Key('officer-whatsapp')));
    expect(deps.urls.opened, <String>[
      'tel:+919100000001',
      'https://wa.me/919100000001',
    ]);
  });
}

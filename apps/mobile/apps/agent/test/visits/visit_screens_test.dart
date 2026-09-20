import 'package:farmerapp_agent/router.dart';
import 'package:farmerapp_agent/screens/farmers/farmer_profile_screen.dart';
import 'package:farmerapp_agent/screens/home/home_screen.dart';
import 'package:farmerapp_agent/screens/visits/confirm_screen.dart';
import 'package:farmerapp_agent/screens/visits/start_visit_screen.dart';
import 'package:farmerapp_agent/screens/visits/summary_screen.dart';
import 'package:farmerapp_agent/screens/visits/visit_screen.dart';
import 'package:farmerapp_agent/screens/visits/visits_list_screen.dart';
import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../farmers/agent_harness.dart';
import 'visit_test_support.dart';

/// A30–A34 through the UI: duty gate, inside / outside check-in payloads,
/// no gallery affordance, FA-016 channels, rejection handling, A33 server
/// override and the A34 list; wiring from A10 and A22.
void main() {
  late AgentDeps deps;

  setUp(() => deps = AgentDeps());
  tearDown(() => deps.dispose());

  Future<List<OutboxRow>> visitOps() async =>
      (await SyncStore(deps.db).opsIn(OutboxState.values.map((s) => s.name)))
          .where((o) => o.entity.startsWith('visit'))
          .toList();

  testWidgets('A30 off duty: prompt to go on duty, no check-in', (
    tester,
  ) async {
    usePhoneSurface(tester);
    await seedVisitWorld(deps, onDuty: false);
    await tester.pumpWidget(
      deps.app(initialLocation: '/visits/new?farmerId=f-1&farmId=farm-f-1'),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('visit-off-duty')), findsOneWidget);
    expect(find.text('Go on duty first'), findsOneWidget);
    expect(find.byKey(const Key('visit-check-in')), findsNothing);
    await tester.tap(find.text('Go to Home'));
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(await visitOps(), isEmpty);
  });

  testWidgets('A30 inside: green state, check-in queues the op and opens A31', (
    tester,
  ) async {
    usePhoneSurface(tester);
    await seedVisitWorld(deps);
    await tester.pumpWidget(
      deps.app(initialLocation: '/visits/new?farmerId=f-1&farmId=farm-f-1'),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('visit-inside')), findsOneWidget);
    expect(find.text('You are inside the farm geofence'), findsOneWidget);
    final map = tester.widget<MapPanel>(find.byKey(const Key('visit-map')));
    expect(map.geofence, GeofenceHighlight.inside);
    expect(find.byKey(const Key('visit-request-override')), findsNothing);
    await tapVisible(tester, find.byKey(const Key('visit-purpose-demo')));
    await tapVisible(tester, find.byKey(const Key('visit-check-in')));
    expect(find.byType(VisitScreen), findsOneWidget);
    final op = (await visitOps()).single;
    expect('${op.entity}/${op.action}', 'visit/create');
    final p = SyncStore.payloadOf(op);
    expect(p['farmer_id'], 'f-1');
    expect(p['farm_id'], 'farm-f-1');
    expect(p['village_id'], 'village-1');
    expect(p['purpose'], 'demo');
    expect(p['client_visit_id'], op.entityId);
    expect((p['checkin_point']! as Map)['lat'], closeTo(17.40045, 1e-4));
    expect(p['device_integrity'], isA<Map<String, Object?>>());
    expect(p.containsKey('override_note'), isFalse);
  });

  testWidgets('A30 outside: distance shown; override needs a note; with a '
      'note the op carries override_note', (tester) async {
    usePhoneSurface(tester);
    await seedVisitWorld(deps, east: 600);
    await tester.pumpWidget(
      deps.app(initialLocation: '/visits/new?farmerId=f-1&farmId=farm-f-1'),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('visit-outside')), findsOneWidget);
    expect(
      find.text('500 m from the farm boundary; the geofence is 150 m.'),
      findsOneWidget,
    );
    final check = tester.widget<AppButton>(
      find.byKey(const Key('visit-check-in')),
    );
    expect(check.onPressed, isNull);
    await tapVisible(tester, find.byKey(const Key('visit-request-override')));
    await tapVisible(tester, find.byKey(const Key('visit-check-in')));
    expect(find.text('Add a note to request an override'), findsOneWidget);
    expect(await visitOps(), isEmpty);
    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('visit-override-note')),
        matching: find.byType(TextField),
      ),
      'Met at the market',
    );
    await tapVisible(tester, find.byKey(const Key('visit-check-in')));
    expect(find.byType(VisitScreen), findsOneWidget);
    final p = SyncStore.payloadOf((await visitOps()).single);
    expect(p['override_note'], 'Met at the market');
    expect(
      find.text('Override requested; waiting for the cluster head'),
      findsOneWidget,
    );
  });

  testWidgets('A30 without a farmer: picker, then pre-check', (tester) async {
    usePhoneSurface(tester);
    await seedVisitWorld(deps);
    await tester.pumpWidget(deps.app(initialLocation: '/visits/new'));
    await tester.pumpAndSettle();
    expect(find.text('Choose a farmer'), findsOneWidget);
    await tester.tap(find.byKey(const Key('visit-farmer-f-1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('visit-inside')), findsOneWidget);
  });

  testWidgets('A31: no gallery affordance, voice placeholder disabled, live '
      'checklist and timer', (tester) async {
    usePhoneSurface(tester);
    await seedVisitWorld(deps);
    final id = await seedVisit(deps);
    await tester.pumpWidget(deps.app(initialLocation: '/visits/$id'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('visit-take-photo')), findsOneWidget);
    for (final icon in <IconData>[
      Icons.photo_library,
      Icons.photo_library_outlined,
      Icons.collections,
      Icons.collections_outlined,
      Icons.image_search,
      Icons.upload_file,
    ]) {
      expect(find.byIcon(icon), findsNothing);
    }
    expect(
      find.textContaining(RegExp('gallery|upload', caseSensitive: false)),
      findsNothing,
    );
    // FA-005: the notes field has a working microphone; typing still works.
    final mic = tester.widget<IconButton>(find.byKey(const Key('visit-voice')));
    expect(mic.onPressed, isNotNull);
    expect(mic.tooltip, 'Speak');
    expect(find.text('0:00'), findsOneWidget);
    // Inside, integrity fine, nothing else yet: 30 + 10.
    expect(
      tester
          .widget<VisitScoreBadge>(
            find.byKey(const Key('visit-expected-score')),
          )
          .score,
      40,
    );
    // Six minutes later the duration row ticks over.
    deps.now = deps.now.add(const Duration(minutes: 6));
    appContainer(tester, VisitScreen).invalidate(visitDetailProvider(id));
    await tester.pumpAndSettle();
    expect(find.text('6:00'), findsOneWidget);
    expect(
      tester
          .widget<VisitScoreBadge>(
            find.byKey(const Key('visit-expected-score')),
          )
          .score,
      50,
    );
    expect(find.text('Minimum duration reached'), findsOneWidget);
    // Crop stage queues a capture op.
    await tapVisible(tester, find.byKey(const Key('visit-stage-flowering')));
    final ops = await visitOps();
    expect(SyncStore.payloadOf(ops.last), <String, Object?>{
      'crop_stage': 'flowering',
    });
  });

  testWidgets('A31 photo: camera → review → use queues visit_photo with '
      'taken_in_app and EXIF', (tester) async {
    usePhoneSurface(tester);
    await seedVisitWorld(deps);
    final id = await seedVisit(deps);
    deps.camera.enqueue(testJpeg());
    await tester.pumpWidget(deps.app(initialLocation: '/visits/$id'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('visit-take-photo')));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('visit-take-photo')));
      await Future<void>.delayed(const Duration(seconds: 3));
    });
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('visit-photo-review')), findsOneWidget);
    await tester.ensureVisible(find.text('Use photo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use photo'));
    await tester.pumpAndSettle();
    final op = (await visitOps()).last;
    expect('${op.entity}/${op.action}', 'visit_photo/create');
    final p = SyncStore.payloadOf(op);
    expect(p['taken_in_app'], isTrue);
    expect(p['exif_time'], deps.now.toIso8601String());
    expect(p['exif_point'], isNotNull);
    expect(p['device_time'], deps.now.toIso8601String());
    expect(find.text('1 photos'), findsOneWidget);
    expect(find.text('Photo with location taken'), findsOneWidget);
  });

  testWidgets('A31 rejected outside_geofence: banner with distance and '
      '"Retry from the farm"', (tester) async {
    usePhoneSurface(tester);
    await seedVisitWorld(deps);
    final id = await seedVisit(deps);
    deps.api.validate = (op) => op.entity == 'visit'
        ? const SyncError(
            'outside_geofence',
            '412 m from the farm boundary; the geofence is 150 m.',
            <String, Object?>{'distance_m': 412, 'target': 'farm'},
          )
        : null;
    await tester.pumpWidget(deps.app(initialLocation: '/visits/$id'));
    await tester.pumpAndSettle();
    await appContainer(tester, VisitScreen).read(syncEngineProvider).syncNow();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('visit-rejected')), findsOneWidget);
    expect(
      find.textContaining('The server placed you 412 m outside the geofence.'),
      findsOneWidget,
    );
    final checkOut = tester.widget<AppButton>(
      find.byKey(const Key('visit-check-out')),
    );
    expect(checkOut.onPressed, isNull);
    deps.api.validate = null;
    await tapVisible(tester, find.byKey(const Key('visit-retry')));
    expect(find.byKey(const Key('visit-rejected')), findsNothing);
    expect((await visitOps()).single.state, 'queued');
  });

  group('A32', () {
    Future<String> open(WidgetTester tester, {bool online = true}) async {
      usePhoneSurface(tester);
      await seedVisitWorld(deps);
      final id = await seedVisit(deps);
      deps.connectivity.online = online;
      await tester.pumpWidget(deps.app(initialLocation: '/visits/$id/confirm'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('confirm-choose')), findsOneWidget);
      return id;
    }

    testWidgets('OTP online: wrong code shows the error, right code confirms', (
      tester,
    ) async {
      final id = await open(tester);
      await tester.tap(find.byKey(const Key('confirm-otp')));
      await tester.pumpAndSettle();
      expect(find.text('Code sent to +91••••••3210'), findsOneWidget);
      final input = find.descendant(
        of: find.byKey(const Key('confirm-otp-input')),
        matching: find.byType(TextField),
      );
      await tester.enterText(input, '000000');
      await tester.pumpAndSettle();
      expect(find.textContaining('4 attempts left'), findsOneWidget);
      expect(find.byKey(const Key('confirm-done')), findsNothing);
      await tester.enterText(input, '123456');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('confirm-done')), findsOneWidget);
      expect(find.text('Confirmed via OTP by SMS'), findsOneWidget);
      expect(deps.confirmApi.confirmed, contains(id));
      // Let the resend timer die.
      await tester.pump(const Duration(seconds: 31));
    });

    testWidgets('OTP offline: needs network', (tester) async {
      await open(tester, online: false);
      await tester.tap(find.byKey(const Key('confirm-otp')));
      await tester.pumpAndSettle();
      expect(
        find.text('This needs network. Try again when you are online.'),
        findsOneWidget,
      );
      expect(deps.confirmApi.requests, isEmpty);
    });

    testWidgets('QR offline explains the sync; online renders the token', (
      tester,
    ) async {
      final id = await open(tester, online: false);
      await tester.tap(find.byKey(const Key('confirm-qr')));
      await tester.pumpAndSettle();
      expect(
        find.text('The QR needs one sync first. Connect once and come back.'),
        findsOneWidget,
      );
      deps.connectivity.online = true;
      await tapVisible(tester, find.byKey(const Key('confirm-qr')));
      final qr = tester.widget<QrImageView>(
        find.byKey(const Key('confirm-qr-image')),
      );
      expect(qr, isNotNull);
      expect(find.byKey(const Key('confirm-qr-state')), findsOneWidget);
      final conf = (await appContainer(
        tester,
        ConfirmScreen,
      ).read(visitRepositoryProvider).detail(id))!.latestConfirmation!;
      expect(conf.token, FakeVisitConfirmApi.tokenFor(id));
    });

    testWidgets('push: waiting, then confirmed when the pull brings '
        'confirmed_at', (tester) async {
      final id = await open(tester);
      final c = appContainer(tester, ConfirmScreen);
      await c.read(syncEngineProvider).syncNow();
      await tester.tap(find.byKey(const Key('confirm-push')));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(find.byKey(const Key('confirm-push-waiting')), findsOneWidget);
      expect(find.text('Waiting for the farmer…'), findsOneWidget);
      deps.api.addChange(
        entity: 'visit',
        action: SyncAction.update,
        entityId: id,
        version: 2,
        data: <String, Object?>{
          ...deps.api.row('visit', id)!.data,
          'confirmation_channel': 'app_push',
          'confirmed_at': deps.now.toIso8601String(),
        },
      );
      await c.read(syncEngineProvider).syncNow();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('confirm-done')), findsOneWidget);
      expect(find.text('Confirmed via Ask in Kisan app'), findsOneWidget);
    });
  });

  testWidgets('A33: local expectation with the under-minimum warning, then '
      'the server-owned score wins', (tester) async {
    usePhoneSurface(tester);
    await seedVisitWorld(deps);
    final id = await seedVisit(deps);
    deps.now = deps.now.add(const Duration(minutes: 3));
    await tester.pumpWidget(deps.app(initialLocation: '/visits/$id'));
    await tester.pumpAndSettle();
    await tapVisible(tester, find.byKey(const Key('visit-check-out')));
    expect(find.byType(SummaryScreen), findsOneWidget);
    expect(find.byKey(const Key('summary-expected')), findsOneWidget);
    expect(
      tester
          .widget<VisitScoreBadge>(find.byKey(const Key('summary-score')))
          .score,
      40,
    );
    expect(find.byKey(const Key('summary-under-minimum')), findsOneWidget);
    expect(find.text('What was missing'), findsOneWidget);
    final checkout = (await visitOps()).last;
    expect(
      SyncStore.payloadOf(checkout)['checkout_at'],
      deps.now.toIso8601String(),
    );

    final c = appContainer(tester, SummaryScreen);
    await c.read(syncEngineProvider).syncNow();
    deps.api.addChange(
      entity: 'visit',
      action: SyncAction.update,
      entityId: id,
      version: 7,
      data: <String, Object?>{
        ...deps.api.row('visit', id)!.data,
        'geofence_result': 'inside',
        'score': 70,
        'status': 'verified',
        'duration_s': 180,
        'flags': <String>['under_minimum'],
        'confirmed_at': deps.now.toIso8601String(),
        'score_components': <String, int>{
          'geofence': 30,
          'confirmation': 30,
          'photo': 0,
          'duration': 0,
          'integrity': 10,
        },
      },
    );
    await c.read(syncEngineProvider).syncNow();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('summary-server')), findsOneWidget);
    expect(
      tester
          .widget<VisitScoreBadge>(find.byKey(const Key('summary-score')))
          .score,
      70,
    );
    expect(find.byKey(const Key('summary-under-minimum')), findsOneWidget);
    await tapVisible(tester, find.byKey(const Key('summary-done')));
    expect(find.byType(VisitsListScreen), findsOneWidget);
    expect(find.byKey(Key('visit-card-$id')), findsOneWidget);
  });

  testWidgets('A34: today / week tabs, status filter and sync state', (
    tester,
  ) async {
    usePhoneSurface(tester);
    await seedVisitWorld(deps);
    final open = await seedVisit(deps);
    await tester.pumpWidget(deps.app(initialLocation: AppRoutes.visits));
    await tester.pumpAndSettle();
    expect(find.byKey(Key('visit-card-$open')), findsOneWidget);
    expect(find.text('Will sync when online'), findsOneWidget);
    expect(find.text('In progress'), findsWidgets);
    await tester.tap(find.byKey(const Key('visits-filter-verified')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('visits-empty')), findsOneWidget);
    await tester.tap(find.byKey(const Key('visits-filter-open')));
    await tester.pumpAndSettle();
    expect(find.byKey(Key('visit-card-$open')), findsOneWidget);
    await tester.tap(find.byKey(const Key('visits-tab-week')));
    await tester.pumpAndSettle();
    expect(find.byKey(Key('visit-card-$open')), findsOneWidget);
    await tester.tap(find.byKey(Key('visit-card-$open')));
    await tester.pumpAndSettle();
    expect(find.byType(VisitScreen), findsOneWidget);
  });

  testWidgets(
    'A10 quick action and Visits nav; A22 Start visit and Visits tab',
    (tester) async {
      usePhoneSurface(tester);
      await seedVisitWorld(deps);
      await seedVisit(deps);
      await tester.pumpWidget(deps.app(initialLocation: AppRoutes.home));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const Key('home-start-visit')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('home-start-visit')));
      await tester.pumpAndSettle();
      expect(find.byType(StartVisitScreen), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Visits').last);
      await tester.pumpAndSettle();
      expect(find.byType(VisitsListScreen), findsOneWidget);

      await tester.pumpWidget(deps.app(initialLocation: '/farmers/f-1'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Visits'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('profile-visits')), findsOneWidget);
      await tester.tap(find.byKey(const Key('profile-start-visit')));
      await tester.pumpAndSettle();
      expect(find.byType(StartVisitScreen), findsOneWidget);
      expect(find.byKey(const Key('visit-inside')), findsOneWidget);
      expect(find.byType(FarmerProfileScreen), findsNothing);
    },
  );
}

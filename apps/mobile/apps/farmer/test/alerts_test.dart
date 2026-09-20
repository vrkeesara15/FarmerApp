import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:farmerapp_farmer/router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'kisan_harness.dart';

/// FM-009 F44: the district's pest and disease alerts with the derived
/// severity, the symptom checklist and "what to do", dismissal that
/// sticks, and the F27 "your result was updated" state on the same list.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('severity is derived from the cases against the baseline', () {
    OutbreakAlert of({
      required int cases,
      required int farmers,
      required double baseline,
    }) => OutbreakAlert.fromJson(
      alertRow(cases: cases, farmers: farmers, baseline: baseline),
    );

    expect(
      of(cases: 12, farmers: 9, baseline: 2).severity,
      AlertSeverity.high,
      reason: 'six times the baseline',
    );
    expect(
      of(cases: 4, farmers: 2, baseline: 2).severity,
      AlertSeverity.medium,
      reason: 'twice the baseline',
    );
    expect(of(cases: 3, farmers: 2, baseline: 2.5).severity, AlertSeverity.low);
    expect(
      of(cases: 3, farmers: 12, baseline: 2.5).severity,
      AlertSeverity.high,
      reason: 'ten farmers or more',
    );
  });

  group('F44 screen', () {
    late KisanDeps deps;

    setUp(() async {
      deps = KisanDeps()..seedWorld();
      deps.seedAdvisory();
      deps.advisory.alertRows.add(
        alertRow(
          id: 'alert-2',
          cropCode: 'chilli',
          cropId: 'pilot:chilli',
          problemCode: 'leaf_curl',
          problemType: 'disease',
          problemName: 'Leaf curl',
          problemNameTe: 'ఆకు ముడత',
          cases: 4,
          farmers: 2,
        ),
      );
      await deps.signIn();
      await deps.primeAdvisory();
    });
    tearDown(() => deps.dispose());

    testWidgets('lists the alerts most severe first with the checklist', (
      tester,
    ) async {
      usePhoneSurface(tester);
      await pumpApp(tester, deps.app(initialLocation: AppRoutes.alerts));

      expect(find.byKey(const Key('alert-alert-1')), findsOneWidget);
      expect(find.text('Pink bollworm'), findsOneWidget);
      expect(find.text('You grow this crop'), findsWidgets);
      expect(find.text('High'), findsWidgets);
      expect(find.text('What to look for'), findsWidgets);
      expect(
        find.text('Look under the leaves for insects or eggs'),
        findsOneWidget,
      );
      expect(find.text('What to do'), findsWidgets);
      expect(find.byKey(const Key('alert-check-alert-1')), findsOneWidget);
      expect(find.byKey(const Key('alert-shop-alert-1')), findsOneWidget);

      // The disease alert gets the disease checklist, lower down.
      await scrollTo(tester, find.byKey(const Key('alert-alert-2')));
      expect(find.text('Look for spots on the leaves'), findsOneWidget);
    });

    testWidgets('dismiss hides the alert and the choice persists', (
      tester,
    ) async {
      usePhoneSurface(tester);
      await pumpApp(tester, deps.app(initialLocation: AppRoutes.alerts));
      await tapIt(tester, find.byKey(const Key('alert-dismiss-alert-1')));
      expect(find.byKey(const Key('alert-alert-1')), findsNothing);
      expect(find.byKey(const Key('alert-alert-2')), findsOneWidget);

      // A refresh brings the row back from the server, but the phone
      // keeps it hidden.
      final ids = await real(tester, () async {
        final c = deps.container();
        final repo = c.read(advisoryRepositoryProvider);
        await repo.refreshAlerts();
        final alerts = await repo.watchAlerts().first;
        c.dispose();
        return alerts!.value.map((a) => a.id).toList();
      });
      expect(ids, <String>['alert-2']);
    });

    testWidgets('F27: an updated crop check is surfaced on the list', (
      tester,
    ) async {
      await real(tester, () async {
        await LocalEntities(deps.db).write(
          SyncEntities.diagnosis,
          'd-1',
          <String, Object?>{
            'id': 'd-1',
            'farmer_id': farmerId,
            'status': 'confirmed',
            'updated_at': '2026-09-18T05:00:00Z',
            'result': <String, Object?>{
              'problem': <String, Object?>{
                'id': 'p-1',
                'code': 'pink_bollworm',
                'type': 'pest',
                'names': <String, Object?>{'en': 'Pink bollworm'},
              },
            },
            Diagnosis.localKey: <String, Object?>{'update_unseen': true},
          },
          version: 1,
          dirty: false,
          now: t0,
        );
      });

      usePhoneSurface(tester);
      await pumpApp(tester, deps.app(initialLocation: AppRoutes.alerts));
      expect(find.byKey(const Key('alerts-diagnosis-d-1')), findsOneWidget);
    });

    testWidgets('no alerts shows the empty state', (tester) async {
      final bare = KisanDeps()..seedWorld();
      addTearDown(bare.dispose);
      await bare.signIn();
      await bare.primeAdvisory();
      usePhoneSurface(tester);
      await pumpApp(tester, bare.app(initialLocation: AppRoutes.alerts));
      expect(find.text('No pest alerts in your district'), findsOneWidget);
    });

    testWidgets('F10 banner shows the top alert and opens F44', (tester) async {
      usePhoneSurface(tester);
      await pumpApp(tester, deps.app());
      expect(find.byKey(const Key('home-alerts')), findsOneWidget);
      await tapIt(tester, find.byKey(const Key('home-alerts')));
      expect(find.byKey(const Key('alert-alert-1')), findsOneWidget);
    });
  });
}

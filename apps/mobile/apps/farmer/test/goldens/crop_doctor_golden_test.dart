// Goldens for the M6 crop doctor at 360x800 in Light and Sunlight: F21
// camera with the overlay (retake tip lit), F22 photo check with the blur
// warning, F25 high-confidence result (also Telugu and Hindi), F26
// provisional, F28 not a plant.
// Regenerate with: flutter test --update-goldens test/goldens
import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:farmerapp_farmer/router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../crop_doctor_test.dart' show leafShot;
import '../kisan_harness.dart';

void main() {
  for (final mode in <AppThemeMode>[
    AppThemeMode.light,
    AppThemeMode.sunlight,
  ]) {
    group(mode.name, () {
      late KisanDeps deps;

      setUp(() async {
        deps = KisanDeps()..seedWorld();
        await deps.signIn();
      });
      tearDown(() => deps.dispose());

      Future<void> seedResult(
        WidgetTester tester,
        String id,
        FakeDiagnosisOutcome outcome,
      ) => real(
        tester,
        () => LocalEntities(deps.db).write(
          SyncEntities.diagnosis,
          id,
          FakeDiagnosisServer.diagnosisOut(
            id: id,
            outcome: outcome,
            cropPlotId: 'plot-2',
            now: t0,
          ),
          version: 1,
          dirty: false,
          now: t0,
        ),
      );

      Future<void> shootResult(
        WidgetTester tester,
        FakeDiagnosisOutcome outcome,
        String name, {
        Locale locale = const Locale('en'),
      }) async {
        usePhoneSurface(tester);
        await seedResult(tester, 'dx-1', outcome);
        await pumpApp(
          tester,
          deps.app(
            initialLocation: AppRoutes.cropResult('dx-1'),
            locale: locale,
            theme: mode,
          ),
        );
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/${name}_${mode.name}.png'),
        );
      }

      testWidgets('f21_camera', (tester) async {
        usePhoneSurface(tester);
        deps.quality.enqueue(ScriptedQualityModel.blurry);
        deps.camera.enqueue(leafShot());
        await pumpApp(
          tester,
          deps.app(initialLocation: AppRoutes.cropDoctor, theme: mode),
        );
        await tapIt(tester, find.byKey(const Key('crop-doctor-start')));
        await tester.tap(find.byKey(GuidedCameraView.shutterKey));
        await settle(tester);
        await tapIt(tester, find.text('Retake'));
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/f21_camera_${mode.name}.png'),
        );
      });

      testWidgets('f22_photo_check_blurry', (tester) async {
        usePhoneSurface(tester);
        deps.quality.enqueue(ScriptedQualityModel.blurry);
        deps.camera.enqueue(leafShot());
        await pumpApp(
          tester,
          deps.app(initialLocation: AppRoutes.cropDoctor, theme: mode),
        );
        await tapIt(tester, find.byKey(const Key('crop-doctor-start')));
        await tester.tap(find.byKey(GuidedCameraView.shutterKey));
        await settle(tester);
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/f22_photo_check_blurry_${mode.name}.png'),
        );
      });

      for (final lang in <String>['en', 'te', 'hi']) {
        testWidgets('f25_result_$lang', (tester) async {
          await shootResult(
            tester,
            FakeDiagnosisOutcome.high,
            'f25_result_$lang',
            locale: Locale(lang),
          );
        });
      }

      testWidgets('f26_provisional', (tester) async {
        await shootResult(
          tester,
          FakeDiagnosisOutcome.provisional,
          'f26_provisional',
        );
      });

      testWidgets('f28_not_a_plant', (tester) async {
        await shootResult(
          tester,
          FakeDiagnosisOutcome.notAPlant,
          'f28_not_a_plant',
        );
      });
    });
  }
}

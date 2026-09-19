// Goldens for A43 (FA-019 scouting result): the high-confidence and the
// provisional variant, Light and Sunlight at 360x800.
// Regenerate with: flutter test --update-goldens test/goldens
import 'package:farmerapp_agent/screens/scouting/scouting_screens.dart';
import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../farmers/agent_harness.dart';

void main() {
  for (final mode in <AppThemeMode>[
    AppThemeMode.light,
    AppThemeMode.sunlight,
  ]) {
    group(mode.name, () {
      late AgentDeps deps;

      setUp(() async {
        deps = AgentDeps();
        await seedVillage(deps.db);
        await seedSyncedFarmer(deps.db, id: 'f-1', phone: '+919876543210');
      });
      tearDown(() => deps.dispose());

      for (final (name, outcome) in <(String, FakeDiagnosisOutcome)>[
        ('a43_result_high', FakeDiagnosisOutcome.high),
        ('a43_result_provisional', FakeDiagnosisOutcome.provisional),
      ]) {
        testWidgets(name, (tester) async {
          usePhoneSurface(tester);
          await LocalEntities(deps.db).write(
            SyncEntities.diagnosis,
            'dx-1',
            FakeDiagnosisServer.diagnosisOut(
              id: 'dx-1',
              outcome: outcome,
              cropPlotId: 'plot-f-1-0',
              subject: 'officer',
              now: t0,
            ),
            version: 1,
            dirty: false,
            now: t0,
          );
          await tester.pumpWidget(
            deps.app(initialLocation: ScoutRoutes.result('dx-1'), theme: mode),
          );
          await tester.pumpAndSettle();
          await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile('goldens/${name}_${mode.name}.png'),
          );
        });
      }
    });
  }
}

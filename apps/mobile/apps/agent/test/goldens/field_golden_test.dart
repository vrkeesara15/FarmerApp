// Goldens for the M7 officer screens — A11 beat plan, A13 notifications
// inbox, A60 my performance, A61 travel allowance and A62 my flags — in
// Light and Sunlight at 360x800. A12 lives in duty_golden_test.dart next to
// the other duty screens.
//
// Regenerate with: flutter test --update-goldens test/goldens
import 'package:farmerapp_agent/router.dart';
import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../farmers/agent_harness.dart';
import '../field/field_test_support.dart';

void main() {
  for (final mode in AppThemeMode.values) {
    group(mode.name, () {
      Future<void> golden(
        WidgetTester tester,
        String name,
        String location, {
        Future<void> Function(AgentDeps deps)? before,
      }) async {
        usePhoneSurface(tester);
        final deps = AgentDeps();
        addTearDown(deps.dispose);
        await seedVillage(deps.db);
        await seedSyncedFarmer(deps.db, id: 'farmer-1', phone: '+919000000001');
        await seedFieldCaches(deps);
        await before?.call(deps);
        await tester.pumpWidget(
          deps.app(initialLocation: location, theme: mode),
        );
        await tester.pumpAndSettle();
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/${name}_${mode.name}.png'),
        );
      }

      testWidgets('a11_beat_plan', (tester) async {
        await golden(tester, 'a11_beat_plan', AppRoutes.beat);
      });

      testWidgets('a13_inbox', (tester) async {
        await golden(tester, 'a13_inbox', AppRoutes.inbox);
      });

      testWidgets('a60_performance', (tester) async {
        await golden(tester, 'a60_performance', AppRoutes.performance);
      });

      testWidgets('a61_travel', (tester) async {
        await golden(tester, 'a61_travel', AppRoutes.travel);
      });

      testWidgets('a62_my_flags', (tester) async {
        await golden(tester, 'a62_my_flags', AppRoutes.myFlags);
      });
    });
  }
}

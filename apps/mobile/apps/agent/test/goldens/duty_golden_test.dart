// Goldens for A05, A06, A07, A10 (off and on duty) and A12 in Light and
// Sunlight at 360x800. Regenerate with: flutter test --update-goldens test/goldens
import 'package:farmerapp_agent/router.dart';
import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../duty/duty_test_support.dart';
import '../farmers/agent_harness.dart';

void main() {
  for (final mode in AppThemeMode.values) {
    group(mode.name, () {
      Future<void> golden(
        WidgetTester tester,
        AgentDeps deps,
        String name,
        String location, {
        Future<void> Function()? before,
      }) async {
        usePhoneSurface(tester);
        addTearDown(deps.dispose);
        deps.now = dutyT0;
        await before?.call();
        await tester.pumpWidget(
          deps.app(initialLocation: location, theme: mode),
        );
        await tester.pumpAndSettle();
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/${name}_${mode.name}.png'),
        );
      }

      testWidgets('a05_disclosure', (tester) async {
        await golden(
          tester,
          AgentDeps(),
          'a05_disclosure',
          AppRoutes.disclosure,
        );
      });

      testWidgets('a06_permissions', (tester) async {
        final deps = AgentDeps();
        deps.permissions.granted.add(AppPermission.location);
        await golden(tester, deps, 'a06_permissions', AppRoutes.permissions);
      });

      testWidgets('a07_registered', (tester) async {
        await golden(
          tester,
          AgentDeps(),
          'a07_registered',
          AppRoutes.registered,
        );
      });

      testWidgets('a10_home_off', (tester) async {
        final deps = AgentDeps();
        await golden(
          tester,
          deps,
          'a10_home_off',
          AppRoutes.home,
          before: () => acceptPolicy(deps),
        );
      });

      testWidgets('a10_home_blocked', (tester) async {
        await golden(tester, AgentDeps(), 'a10_home_blocked', AppRoutes.home);
      });

      testWidgets('a10_home_on', (tester) async {
        final deps = AgentDeps();
        await golden(
          tester,
          deps,
          'a10_home_on',
          AppRoutes.home,
          before: () async {
            await acceptPolicy(deps);
            await seedOnDuty(deps, points: 7);
            deps.now = dutyT0.add(const Duration(hours: 2, minutes: 5));
          },
        );
      });

      testWidgets('a12_my_day', (tester) async {
        final deps = AgentDeps();
        await golden(
          tester,
          deps,
          'a12_my_day',
          AppRoutes.myDay,
          before: () async {
            await acceptPolicy(deps);
            await seedOnDuty(deps, points: 7);
          },
        );
      });
    });
  }
}

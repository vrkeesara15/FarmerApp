// FA-008 goldens: the same two screens (A01 splash, A10 home) rendered for
// two tenants whose branding differs in every field, with no code change
// between the two runs — the acceptance criterion of SPEC 2.1 as a picture.
//
// Regenerate with: flutter test --update-goldens test/goldens
import 'package:farmerapp_agent/router.dart';
import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../duty/duty_test_support.dart';
import '../farmers/agent_harness.dart';
import '../field/field_test_support.dart';

void main() {
  for (final (tenant, branding) in <(String, TenantBranding)>[
    ('harvest', TestBrands.harvest),
    ('bhoomi', TestBrands.bhoomi),
  ]) {
    group(tenant, () {
      Future<void> golden(
        WidgetTester tester,
        String name,
        String location, {
        AppThemeMode mode = AppThemeMode.light,
        Future<void> Function(AgentDeps deps)? before,
      }) async {
        usePhoneSurface(tester);
        final deps = AgentDeps();
        addTearDown(deps.dispose);
        await before?.call(deps);
        await tester.pumpWidget(
          deps.app(initialLocation: location, theme: mode, branding: branding),
        );
        await tester.pumpAndSettle();
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/${name}_${tenant}_${mode.name}.png'),
        );
      }

      testWidgets('a01_splash', (tester) async {
        await golden(tester, 'fa008_splash', AppRoutes.splash);
      });

      testWidgets('a01_splash sunlight', (tester) async {
        await golden(
          tester,
          'fa008_splash',
          AppRoutes.splash,
          mode: AppThemeMode.sunlight,
        );
      });

      testWidgets('a10_home', (tester) async {
        await golden(
          tester,
          'fa008_home',
          AppRoutes.home,
          before: (deps) async {
            await acceptPolicy(deps);
            await seedFieldCaches(deps);
          },
        );
      });
    });
  }
}

// FA-008 goldens: F10 home and F70 Me rendered for two tenants whose
// branding differs in every field, with no code change between the two runs
// — the acceptance criterion of SPEC 2.1 as a picture.
//
// Regenerate with: flutter test --update-goldens test/goldens
import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:farmerapp_farmer/router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../kisan_harness.dart';

void main() {
  for (final (tenant, branding) in <(String, TenantBranding)>[
    ('harvest', TestBrands.harvest),
    ('bhoomi', TestBrands.bhoomi),
  ]) {
    group(tenant, () {
      Future<void> shoot(
        WidgetTester tester,
        String location,
        String name, {
        AppThemeMode mode = AppThemeMode.light,
      }) async {
        usePhoneSurface(tester);
        final deps = KisanDeps()..seedWorld();
        addTearDown(deps.dispose);
        await deps.signIn();
        await pumpApp(
          tester,
          deps.app(initialLocation: location, theme: mode, branding: branding),
        );
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/${name}_${tenant}_${mode.name}.png'),
        );
      }

      testWidgets('f10_home', (tester) async {
        await shoot(tester, AppRoutes.home, 'fa008_home');
      });

      testWidgets('f10_home sunlight', (tester) async {
        await shoot(
          tester,
          AppRoutes.home,
          'fa008_home',
          mode: AppThemeMode.sunlight,
        );
      });

      testWidgets('f70_me', (tester) async {
        await shoot(tester, AppRoutes.me, 'fa008_me');
      });
    });
  }
}

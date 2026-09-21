import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:farmerapp_farmer/router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'kisan_harness.dart';

/// FA-008 acceptance in the farmer app: "a second test tenant renders with
/// its brand without a code change".
///
/// The same widget tree twice; only the `branding` from
/// `GET /v1/settings/public` differs. The farmer app names are the
/// `app_name_farmer` overrides, not the officer app's.
void main() {
  Color primaryOf(WidgetTester tester) =>
      tester.element(find.byType(Scaffold).first).app.palette.primary;

  for (final (name, branding, expectedName, expectedPrimary)
      in <(String, TenantBranding, String, String)>[
        ('tenant A (Harvest)', TestBrands.harvest, 'Harvest Kisan', '#3B4BD8'),
        ('tenant B (Bhoomi)', TestBrands.bhoomi, 'Bhoomi', '#B4362A'),
      ]) {
    testWidgets('$name brands the F10 home header', (tester) async {
      final deps = KisanDeps()..seedWorld();
      addTearDown(deps.dispose);
      await deps.signIn();
      await pumpApp(tester, deps.app(branding: branding));

      expect(
        tester.widget<Text>(find.byKey(const Key('home-brand-name'))).data,
        expectedName,
      );
      expect(find.byKey(const Key('home-brand-logo')), findsOneWidget);
      expect(find.byKey(const Key('brand-logo-image')), findsOneWidget);
      expect(hexOf(primaryOf(tester)), expectedPrimary);
    });

    testWidgets('$name puts its own number behind F70 "call support"', (
      tester,
    ) async {
      final deps = KisanDeps()..seedWorld();
      addTearDown(deps.dispose);
      await deps.signIn();
      await pumpApp(
        tester,
        deps.app(initialLocation: AppRoutes.me, branding: branding),
      );

      await scrollTo(tester, find.byKey(const Key('me-help')));
      await tapIt(tester, find.byKey(const Key('me-help')));
      expect(deps.urls.opened, <String>['tel:${branding.supportPhone}']);
    });
  }

  testWidgets('with no tenant branding the shipped brand stands', (
    tester,
  ) async {
    final deps = KisanDeps()..seedWorld();
    addTearDown(deps.dispose);
    await deps.signIn();
    await pumpApp(tester, deps.app());

    expect(
      tester.widget<Text>(find.byKey(const Key('home-brand-name'))).data,
      'Kisan',
    );
    expect(find.byKey(const Key('brand-logo-image')), findsNothing);
    expect(hexOf(primaryOf(tester)), hexOf(Tokens.light.primary));
  });

  testWidgets('the tenant colour still passes WCAG AA in Sunlight', (
    tester,
  ) async {
    final deps = KisanDeps()..seedWorld();
    addTearDown(deps.dispose);
    await deps.signIn();
    await pumpApp(
      tester,
      deps.app(branding: TestBrands.bhoomi, theme: AppThemeMode.sunlight),
    );

    final palette = tester.element(find.byType(Scaffold).first).app.palette;
    expect(
      contrastRatio(palette.primary, palette.surface),
      greaterThanOrEqualTo(7),
    );
    expect(
      contrastRatio(palette.primaryOn, palette.primary),
      greaterThanOrEqualTo(4.5),
    );
  });
}

import 'package:farmerapp_agent/router.dart';
import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'duty/duty_test_support.dart';
import 'farmers/agent_harness.dart';
import 'field/field_test_support.dart';

/// FA-008 acceptance: "a second test tenant renders with its brand without
/// a code change".
///
/// Both tenants run the same widget tree — the same routes, the same
/// harness, the same overrides — and the only difference between the two
/// runs is the `branding` object `GET /v1/settings/public` returned. Nothing
/// below reaches into the app's code to make the second tenant work.
void main() {
  Color primaryOf(WidgetTester tester) =>
      tester.element(find.byType(Scaffold).first).app.palette.primary;

  for (final (name, branding, expectedName, expectedPrimary)
      in <(String, TenantBranding, String, String)>[
        ('tenant A (Harvest)', TestBrands.harvest, 'Harvest Field', '#3B4BD8'),
        ('tenant B (Bhoomi)', TestBrands.bhoomi, 'Bhoomi Officer', '#B4362A'),
      ]) {
    testWidgets('$name brands the splash', (tester) async {
      final deps = AgentDeps();
      addTearDown(deps.dispose);
      await tester.pumpWidget(
        deps.app(initialLocation: AppRoutes.splash, branding: branding),
      );
      await tester.pump();

      expect(
        tester.widget<Text>(find.byKey(const Key('splash-app-name'))).data,
        expectedName,
      );
      expect(hexOf(primaryOf(tester)), expectedPrimary);
      // The tenant's logo, not the shipped leaf.
      expect(find.byKey(const Key('brand-logo-image')), findsOneWidget);
      expect(find.byIcon(Icons.eco_outlined), findsNothing);
    });

    testWidgets('$name brands the home header and the theme', (tester) async {
      final deps = AgentDeps();
      addTearDown(deps.dispose);
      await acceptPolicy(deps);
      await seedFieldCaches(deps);
      await tester.pumpWidget(
        deps.app(initialLocation: AppRoutes.home, branding: branding),
      );
      await tester.pumpAndSettle();

      expect(
        tester.widget<Text>(find.byKey(const Key('home-brand-name'))).data,
        expectedName,
      );
      expect(find.byKey(const Key('home-brand-logo')), findsOneWidget);
      expect(hexOf(primaryOf(tester)), expectedPrimary);
    });

    testWidgets('$name puts its own number behind "call support"', (
      tester,
    ) async {
      final deps = AgentDeps();
      addTearDown(deps.dispose);
      await tester.pumpWidget(
        deps.app(initialLocation: AppRoutes.settings, branding: branding),
      );
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.byKey(const Key('support-setting')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(const Key('support-setting')));
      await tester.pumpAndSettle();
      expect(deps.urls.opened, <String>['tel:${branding.supportPhone}']);
    });
  }

  testWidgets('with no tenant branding the shipped brand stands', (
    tester,
  ) async {
    final deps = AgentDeps();
    addTearDown(deps.dispose);
    await tester.pumpWidget(deps.app(initialLocation: AppRoutes.splash));
    await tester.pump();

    expect(
      tester.widget<Text>(find.byKey(const Key('splash-app-name'))).data,
      'Mitra',
    );
    expect(find.byIcon(Icons.eco_outlined), findsOneWidget);
    expect(
      hexOf(tester.element(find.byType(Scaffold).first).app.palette.primary),
      hexOf(Tokens.light.primary),
    );
  });

  testWidgets('a tenant that set no support number cannot dial one', (
    tester,
  ) async {
    final deps = AgentDeps();
    addTearDown(deps.dispose);
    await tester.pumpWidget(deps.app(initialLocation: AppRoutes.settings));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const Key('support-setting')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      find.text('Your organisation has not added a support number'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('support-setting')));
    await tester.pumpAndSettle();
    expect(deps.urls.opened, isEmpty);
  });

  testWidgets('the tenant colour still passes WCAG AA in Sunlight', (
    tester,
  ) async {
    // NF-009 lives in the derivation (brand_test.dart holds it to the bar);
    // this checks the app actually paints the derived palette in the
    // high-contrast theme, where a raw brand colour would fail.
    final deps = AgentDeps();
    addTearDown(deps.dispose);
    await tester.pumpWidget(
      deps.app(
        initialLocation: AppRoutes.splash,
        branding: TestBrands.bhoomi,
        theme: AppThemeMode.sunlight,
      ),
    );
    await tester.pump();

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

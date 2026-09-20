// Goldens for the M7 farmer screens at 360x800 in Light and Sunlight:
// F40 my crops, F42 crop calendar (also in Telugu), F43 weather with the
// spray windows and F44 district alerts.
// Regenerate with: flutter test --update-goldens test/goldens
import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:farmerapp_farmer/router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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
        deps.seedAdvisory();
        deps.advisory.addNotification(
          id: 'n-1',
          kind: NotificationKinds.cropTaskReminder,
          route: '/inbox',
          data: const <String, Object?>{'crop_plot_id': 'plot-1'},
        );
        await deps.signIn();
        await deps.primeAdvisory();
      });
      tearDown(() => deps.dispose());

      Future<void> shoot(
        WidgetTester tester,
        String location,
        String name, {
        Locale locale = const Locale('en'),
      }) async {
        usePhoneSurface(tester);
        await pumpApp(
          tester,
          deps.app(initialLocation: location, locale: locale, theme: mode),
        );
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/${name}_${mode.name}.png'),
        );
      }

      testWidgets('f40_my_crops', (tester) async {
        await shoot(tester, AppRoutes.crops, 'f40_my_crops');
      });

      for (final lang in <String>['en', 'te']) {
        testWidgets('f42_calendar_$lang', (tester) async {
          await shoot(
            tester,
            AppRoutes.calendar('plot-1'),
            'f42_calendar_$lang',
            locale: Locale(lang),
          );
        });
      }

      testWidgets('f43_weather', (tester) async {
        await shoot(tester, AppRoutes.weather, 'f43_weather');
      });

      testWidgets('f44_alerts', (tester) async {
        await shoot(tester, AppRoutes.alerts, 'f44_alerts');
      });

      testWidgets('inbox', (tester) async {
        await shoot(tester, AppRoutes.inbox, 'fa007_inbox');
      });
    });
  }
}

// Goldens for the M6 farmer screens at 360x800 in Light and Sunlight:
// F04 consent and F10 home in English and Telugu; F05 welcome, F33 order
// tracking, F50 khata, F60 visit prompt, F61 rating and F70 Me in English.
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
        deps = KisanDeps()..seedWorld(khataBalance: 1250000);
        await deps.signIn();
        deps.kisan.ordersById['o-1'] = <String, Object?>{
          'id': 'o-1',
          'status': 'packed',
          'fulfilment': 'pickup',
          'total_paise': 219000,
          'placed_at': '2026-09-18T05:00:00Z',
          'lines': <Object?>[
            <String, Object?>{
              'sku_id': 'sku-neem',
              'qty': '2',
              'line_total_paise': 84000,
            },
            <String, Object?>{
              'sku_id': 'sku-dap',
              'qty': '1',
              'line_total_paise': 135000,
            },
          ],
          'payments': <Object?>[],
          'events': <Object?>[
            <String, Object?>{
              'to_status': 'placed',
              'created_at': '2026-09-18T05:00:00Z',
            },
            <String, Object?>{
              'to_status': 'packed',
              'created_at': '2026-09-18T08:30:00Z',
            },
          ],
        };
        final c = deps.container();
        final repo = c.read(kisanRepositoryProvider);
        await repo.refreshProfile();
        await repo.refreshOrder('o-1');
        await repo.receivePush(<String, Object?>{
          'type': 'visit_confirm',
          'visit_id': 'v-1',
          'token': visitToken('v-1', channel: 'app_push'),
          'officer_name': 'Ramesh Kumar',
          'expires_at': t0.add(const Duration(hours: 24)).toIso8601String(),
        });
        c.dispose();
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

      for (final lang in <String>['en', 'te']) {
        testWidgets('f04_consent_$lang', (tester) async {
          await shoot(
            tester,
            AppRoutes.consent,
            'f04_consent_$lang',
            locale: Locale(lang),
          );
        });

        testWidgets('f10_home_$lang', (tester) async {
          await shoot(
            tester,
            AppRoutes.home,
            'f10_home_$lang',
            locale: Locale(lang),
          );
        });
      }

      testWidgets('f05_welcome', (tester) async {
        await shoot(tester, AppRoutes.welcome, 'f05_welcome');
      });

      testWidgets('f33_order_tracking', (tester) async {
        await shoot(tester, AppRoutes.order('o-1'), 'f33_order_tracking');
      });

      testWidgets('f50_khata', (tester) async {
        await shoot(tester, AppRoutes.khata, 'f50_khata');
      });

      testWidgets('f60_visit_prompt', (tester) async {
        await shoot(tester, AppRoutes.visit('v-1'), 'f60_visit_prompt');
      });

      testWidgets('f61_rating', (tester) async {
        usePhoneSurface(tester);
        await pumpApp(
          tester,
          deps.app(initialLocation: AppRoutes.visit('v-1'), theme: mode),
        );
        await tapIt(tester, find.byKey(const Key('visit-yes')));
        await tapIt(tester, find.text('Good'));
        await tapIt(tester, find.byKey(const Key('reason-useful_advice')));
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/f61_rating_${mode.name}.png'),
        );
      });

      testWidgets('f70_me', (tester) async {
        await shoot(tester, AppRoutes.me, 'f70_me');
      });
    });
  }
}

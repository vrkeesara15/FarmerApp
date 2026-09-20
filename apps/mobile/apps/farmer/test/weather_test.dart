import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:farmerapp_farmer/router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'kisan_harness.dart';

/// FM-008 F43: the 7-day forecast and the spray windows. The acceptance
/// criterion is that spray advice hides windows with rain or wind above
/// the threshold — the app re-checks the thresholds itself, so a window
/// the server mislabels as good is still not offered.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('spray windows', () {
    test('hides rainy and windy blocks from the good list', () {
      final weather = FarmWeather.fromJson(weatherBody());
      final spray = weather.spray;

      expect(spray.thresholds.maxRainProbabilityPct, 30);
      expect(spray.thresholds.maxWindKmh, 15);

      // 06:00 is the only genuinely good window: 09:00 is rainy, 12:00 is
      // windy and 18:00 was sent as "good" with 21 km/h of wind.
      expect(spray.good, hasLength(1));
      expect(spray.good.single.start.hour, 1); // 06:30 IST = 01:00 UTC
      expect(
        spray.avoid.map((w) => w.blockingReasons(spray.thresholds).first),
        containsAll(<String>[SprayReasons.rainLikely, SprayReasons.windHigh]),
      );
      final mislabelled = spray.all.firstWhere((w) => w.maxWindKmh == 21);
      expect(mislabelled.advice, 'good', reason: 'the server said good');
      expect(
        mislabelled.isGood(spray.thresholds),
        isFalse,
        reason: 'the app re-checks the wind threshold',
      );
      expect(
        mislabelled.blockingReasons(spray.thresholds),
        contains(SprayReasons.windHigh),
      );
    });

    test('blocks cover three days from the first window', () {
      final weather = FarmWeather.fromJson(weatherBody());
      final blocks = weather.spray.blocks(from: weather.spray.all.first.start);
      expect(blocks, hasLength(4));
      expect(blocks.first.start.isBefore(blocks.last.start), isTrue);
    });
  });

  group('F43 screen', () {
    late KisanDeps deps;

    setUp(() async {
      deps = KisanDeps()..seedWorld();
      deps.seedAdvisory();
      await deps.signIn();
      await deps.primeAdvisory();
    });
    tearDown(() => deps.dispose());

    testWidgets('shows seven days, the spray blocks and "advice only"', (
      tester,
    ) async {
      usePhoneSurface(tester);
      await pumpApp(tester, deps.app(initialLocation: AppRoutes.weather));

      expect(find.byKey(const Key('weather-day-2026-09-19')), findsOneWidget);
      expect(find.byKey(const Key('weather-day-2026-09-25')), findsOneWidget);
      expect(find.textContaining('Rain 10%'), findsWidgets);

      await scrollTo(tester, find.byKey(const Key('spray-section')));
      // One good block, three to avoid (including the mislabelled one).
      expect(
        find.byWidgetPredicate(
          (w) => w.key.toString().contains('spray-good-'),
          skipOffstage: false,
        ),
        findsOneWidget,
      );
      expect(
        find.byWidgetPredicate(
          (w) => w.key.toString().contains('spray-avoid-'),
          skipOffstage: false,
        ),
        findsNWidgets(3),
      );
      expect(find.text('Rain is likely'), findsWidgets);
      expect(find.text('Wind is too strong'), findsWidgets);
      await scrollTo(tester, find.byKey(const Key('spray-advice-only')));
      expect(
        find.text('This is advice only. Look at your field before you spray.'),
        findsOneWidget,
      );
    });

    testWidgets('the cache shows "as of" and survives going offline', (
      tester,
    ) async {
      deps.advisory.offline = true;
      deps.connectivity.online = false;

      usePhoneSurface(tester);
      await pumpApp(tester, deps.app(initialLocation: AppRoutes.weather));

      expect(find.byKey(const Key('weather-day-2026-09-19')), findsOneWidget);
      expect(find.byType(OfflineBanner), findsOneWidget);
      await scrollTo(tester, find.byKey(const Key('as-of')));
      expect(
        find.textContaining('19-09-2026'),
        findsWidgets,
        reason: 'the "as of" time of the cached forecast',
      );
    });

    testWidgets('a farm without a forecast shows the empty state', (
      tester,
    ) async {
      final bare = KisanDeps()..seedWorld();
      addTearDown(bare.dispose);
      await bare.signIn();
      usePhoneSurface(tester);
      await pumpApp(tester, bare.app(initialLocation: AppRoutes.weather));
      expect(find.text('No weather for your farm yet'), findsOneWidget);
    });

    testWidgets('F10 strip shows today and opens F43', (tester) async {
      usePhoneSurface(tester);
      await pumpApp(tester, deps.app());
      await tapIt(tester, find.byKey(const Key('home-weather')));
      expect(find.text('Next 7 days'), findsOneWidget);
    });
  });
}

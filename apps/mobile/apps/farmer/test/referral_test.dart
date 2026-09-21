import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:farmerapp_farmer/router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'kisan_harness.dart';

/// FM-013 F71: the farmer's invite code, sharing it through WhatsApp or
/// SMS, and the code an invite link left behind being claimed after login.
///
/// NF-010 is the shape of this feature: no farmer screen may ask for
/// typing, so the code only ever arrives from a link — `referralCodeFrom`
/// and the pending-code path are what make that work.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('code from a link', () {
    test('reads the code out of an invite link, a deep link or a raw code', () {
      expect(
        referralCodeFrom('https://kisan.farmerapp.in/r/KISAN123'),
        'KISAN123',
      );
      expect(referralCodeFrom('kisan://referral/kisan123'), 'KISAN123');
      expect(referralCodeFrom(' kisan-123 '), 'KISAN123');
      expect(referralCodeFrom('KISAN123'), 'KISAN123');
      expect(
        referralCodeFrom('https://kisan.farmerapp.in/r/ABCD1234?utm=x'),
        'ABCD1234',
      );
    });

    test('answers null when there is nothing code-shaped', () {
      expect(referralCodeFrom(null), isNull);
      expect(referralCodeFrom(''), isNull);
      expect(referralCodeFrom('...'), isNull);
      expect(referralCodeFrom('ab'), isNull, reason: 'too short');
    });
  });

  group('repository', () {
    late KisanDeps deps;

    setUp(() async {
      deps = KisanDeps()..seedWorld();
      deps.seedMarket();
      await deps.signIn();
    });
    tearDown(() => deps.dispose());

    test('caches the referral profile with its "as of"', () async {
      final c = deps.container();
      final repo = c.read(marketRepositoryProvider);
      expect(await repo.refreshReferral(), isTrue);
      final cached = await repo.watchReferral().first;
      expect(cached!.value.code, 'KISAN123');
      expect(cached.value.shareLink.endsWith('KISAN123'), isTrue);
      expect(cached.value.attributed, 1);
      expect(cached.asOf, deps.now);
      c.dispose();
    });

    test('remembers a code from a link and claims it once', () async {
      final c = deps.container();
      final repo = c.read(marketRepositoryProvider);
      await repo.rememberCode('https://kisan.farmerapp.in/r/friend01');
      expect(await repo.pendingCode(), 'FRIEND01');

      expect(await repo.claim(), isNull, reason: 'attributed');
      expect(deps.market.writes.last.$2['code'], 'FRIEND01');
      expect(await repo.pendingCode(), isNull, reason: 'the link is spent');
      c.dispose();
    });

    test('a refused claim reports the reason and spends the link', () async {
      final c = deps.container();
      final repo = c.read(marketRepositoryProvider);
      await repo.rememberCode('https://kisan.farmerapp.in/r/KISAN123');
      deps.market
        ..claimStatus = 409
        ..claimProblem = 'referral_already_attributed';

      expect(await repo.claim(), 'referral_already_attributed');
      expect(await repo.pendingCode(), isNull);
      c.dispose();
    });

    test('an offline claim keeps the code for the next attempt', () async {
      final c = deps.container();
      final repo = c.read(marketRepositoryProvider);
      await repo.rememberCode('KISAN123');
      deps.market.offline = true;

      expect(await repo.claim(), 'offline');
      expect(await repo.pendingCode(), 'KISAN123');
      c.dispose();
    });

    test('nothing to claim is not an error', () async {
      final c = deps.container();
      expect(await c.read(marketRepositoryProvider).pendingCode(), isNull);
      c.dispose();
    });
  });

  group('F71 screen', () {
    late KisanDeps deps;

    setUp(() async {
      deps = KisanDeps()..seedWorld();
      deps.seedMarket();
      await deps.signIn();
      await deps.primeMarket();
    });
    tearDown(() => deps.dispose());

    testWidgets('shows the code and the counts', (tester) async {
      usePhoneSurface(tester);
      await pumpApp(tester, deps.app(initialLocation: AppRoutes.referral));

      expect(find.byKey(const Key('referral-code')), findsOneWidget);
      expect(find.text('KISAN123'), findsOneWidget);
      expect(find.byKey(const Key('referral-counts')), findsOneWidget);
      // The reward is a tenant setting with a placeholder value, so the app
      // says the store will explain it rather than promising an amount.
      expect(find.byKey(const Key('referral-reward-note')), findsOneWidget);
      expect(find.byKey(const Key('as-of')), findsOneWidget);
    });

    testWidgets('sharing sends the link and records a pending invite', (
      tester,
    ) async {
      usePhoneSurface(tester);
      await pumpApp(tester, deps.app(initialLocation: AppRoutes.referral));
      await tapIt(tester, find.byKey(const Key('referral-whatsapp')));
      await settle(tester);

      expect(deps.sharer.shared, hasLength(1));
      expect(deps.sharer.shared.single, contains('KISAN123'));
      expect(
        deps.sharer.shared.single,
        contains('https://kisan.farmerapp.in/r/KISAN123'),
      );
      expect(deps.market.calls, contains('POST /v1/me/referral/invites'));
    });

    testWidgets('SMS opens an sms: link carrying the message', (tester) async {
      usePhoneSurface(tester);
      await pumpApp(tester, deps.app(initialLocation: AppRoutes.referral));
      await tapIt(tester, find.byKey(const Key('referral-sms')));
      await settle(tester);

      expect(deps.urls.opened, hasLength(1));
      expect(deps.urls.opened.single, startsWith('sms:?body='));
      expect(
        Uri.decodeComponent(deps.urls.opened.single),
        contains('KISAN123'),
      );
    });

    testWidgets('a tenant with referrals off hides the share buttons', (
      tester,
    ) async {
      final off = KisanDeps()..seedWorld();
      off.market.referralBody = referralBody(enabled: false);
      await off.signIn();
      await off.primeMarket();
      usePhoneSurface(tester);
      await pumpApp(tester, off.app(initialLocation: AppRoutes.referral));

      expect(find.byKey(const Key('referral-off')), findsOneWidget);
      expect(find.byKey(const Key('referral-whatsapp')), findsNothing);
      await off.dispose();
    });

    testWidgets('Me opens the invite screen', (tester) async {
      usePhoneSurface(tester);
      await pumpApp(tester, deps.app(initialLocation: AppRoutes.me));
      await scrollTo(tester, find.byKey(const Key('me-referral')));
      await tapIt(tester, find.byKey(const Key('me-referral')));
      expect(find.byKey(const Key('referral-code')), findsOneWidget);
    });
  });

  group('registration carries the code', () {
    late KisanDeps deps;

    setUp(() async {
      deps = KisanDeps()..seedWorld();
      deps.seedMarket();
      await deps.signIn();
    });
    tearDown(() => deps.dispose());

    testWidgets('signing in claims the code the invite link left behind', (
      tester,
    ) async {
      final c = deps.container();
      await c
          .read(marketRepositoryProvider)
          .rememberCode('https://kisan.farmerapp.in/r/friend01');
      c.dispose();

      // routeAfterLogin claims it on the way in (start.dart), so opening the
      // app after an invite link is what attributes the referral.
      usePhoneSurface(tester);
      await pumpApp(tester, deps.app());
      final again = deps.container();
      expect(
        await again.read(marketRepositoryProvider).claim(),
        isNull,
        reason: 'the pending code was claimable',
      );
      again.dispose();

      expect(deps.market.calls, contains('POST /v1/me/referral/claim'));
      expect(deps.market.writes.last.$2['code'], 'FRIEND01');
    });
  });
}

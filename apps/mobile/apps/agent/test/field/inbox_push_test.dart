import 'package:farmerapp_agent/router.dart';
import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../farmers/agent_harness.dart';
import 'field_test_support.dart';

void main() {
  group('A13 inbox', () {
    testWidgets('renders the server rows in the app language', (tester) async {
      final deps = AgentDeps();
      addTearDown(deps.dispose);
      await seedFieldCaches(deps);
      await tester.pumpWidget(deps.app(initialLocation: AppRoutes.inbox));
      await tester.pumpAndSettle();

      // The server sends only i18n keys; the app renders its own copy.
      expect(find.text("Today's beat plan is ready"), findsOneWidget);
      expect(find.text('Expense claim decision'), findsOneWidget);
      expect(find.text('Your claim was approved.'), findsOneWidget);
      expect(find.text('1 unread'), findsOneWidget);
    });

    testWidgets('tapping a row marks it read and follows the deep link', (
      tester,
    ) async {
      final deps = AgentDeps();
      addTearDown(deps.dispose);
      await seedFieldCaches(deps);
      await tester.pumpWidget(deps.app(initialLocation: AppRoutes.inbox));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('inbox-item-notif-1')));
      await tester.pumpAndSettle();

      // `/beat/<date>` is the officer app's A11.
      expect(find.text("Today's beat"), findsOneWidget);

      final c = deps.container();
      addTearDown(c.dispose);
      final inbox = await c.read(fieldRepositoryProvider).inbox();
      expect(inbox.unread, 0);
      final rows = await SyncStore(deps.db).opsIn(<String>['queued']);
      final op = SyncStore.toOp(
        rows.firstWhere((r) => r.entity == FieldEntities.notification),
      );
      expect(op.entityId, 'notif-1');
      expect(op.action, SyncAction.update);
      expect(op.payload['read_at'], isA<String>());
    });

    testWidgets('mark all read clears the badge offline', (tester) async {
      final deps = AgentDeps(online: false);
      addTearDown(deps.dispose);
      await seedFieldCaches(deps);
      deps.field.offline = true;
      deps.api.offline = true;
      await tester.pumpWidget(deps.app(initialLocation: AppRoutes.inbox));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('inbox-mark-all-read')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('inbox-mark-all-read')), findsNothing);
      final c = deps.container();
      addTearDown(c.dispose);
      expect((await c.read(fieldRepositoryProvider).inbox()).unread, 0);
    });

    testWidgets('an empty inbox says so', (tester) async {
      final deps = AgentDeps();
      addTearDown(deps.dispose);
      await tester.pumpWidget(deps.app(initialLocation: AppRoutes.inbox));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('inbox-empty')), findsOneWidget);
    });

    testWidgets('the unread count badges Home and the bottom nav', (
      tester,
    ) async {
      final deps = AgentDeps();
      addTearDown(deps.dispose);
      await seedFieldCaches(deps);
      await tester.pumpWidget(deps.app(initialLocation: AppRoutes.home));
      await tester.pumpAndSettle();

      final badge = tester.widget<Badge>(
        find.byKey(const Key('home-inbox-badge')),
      );
      expect(badge.isLabelVisible, isTrue);
      final navBadge = tester.widget<Badge>(
        find.byKey(const Key('nav-me-badge')),
      );
      expect(navBadge.isLabelVisible, isTrue);

      await tester.tap(find.byKey(const Key('home-inbox')));
      await tester.pumpAndSettle();
      expect(find.text('Notifications'), findsOneWidget);
    });
  });

  group('FA-007 deep links', () {
    test('every server route the officer app can answer', () {
      expect(deepLinkFor('/beat/2026-09-20'), AppRoutes.beat);
      expect(deepLinkFor('/duty'), AppRoutes.myDay);
      expect(deepLinkFor('/flags/abc'), AppRoutes.myFlags);
      expect(deepLinkFor('/travel/claims/abc'), AppRoutes.travel);
      expect(deepLinkFor('/visits/v1/confirm'), '/visits/v1/confirm');
      expect(deepLinkFor('/orders/o1'), '/orders/o1');
      expect(deepLinkFor('/diagnoses/d1'), '/scouting/d1');
      expect(deepLinkFor('/credit-approvals/a1'), '/orders');
      // Unknown kinds land on the inbox rather than nowhere.
      expect(deepLinkFor('/something-new/1'), AppRoutes.inbox);
      expect(deepLinkFor(''), AppRoutes.inbox);
    });
  });

  group('FA-007 push registration', () {
    test('the token is registered after login and cleared on logout', () async {
      final deps = AgentDeps();
      addTearDown(deps.dispose);
      final c = deps.container();
      addTearDown(c.dispose);
      final registrar = c.read(pushRegistrarProvider);

      expect(await registrar.registerAfterLogin(), 'fcm-token-1');
      expect(deps.field.registeredTokens, <String>['fcm-token-1']);

      await registrar.clear();
      expect(deps.field.removedTokens, <String>['fcm-token-1']);
      expect(deps.push.deletes, 1);
      expect(registrar.registeredToken, isNull);
    });

    test(
      'a build without Firebase registers nothing and still works',
      () async {
        final deps = AgentDeps();
        addTearDown(deps.dispose);
        deps.push.available = false;
        final c = deps.container();
        addTearDown(c.dispose);

        expect(
          await c.read(pushRegistrarProvider).registerAfterLogin(),
          isNull,
        );
        expect(deps.field.registeredTokens, isEmpty);
      },
    );

    test('an unreachable server does not lose the session', () async {
      final deps = AgentDeps();
      addTearDown(deps.dispose);
      deps.field.offline = true;
      final c = deps.container();
      addTearDown(c.dispose);

      expect(await c.read(pushRegistrarProvider).registerAfterLogin(), isNull);
      // Clearing is best effort too: the server disables a dead token itself.
      await c.read(pushRegistrarProvider).clear();
      expect(deps.push.deletes, 1);
    });

    test('a foreground data message refreshes the inbox', () async {
      final deps = AgentDeps();
      addTearDown(deps.dispose);
      deps.field.inbox = inboxFixture();
      final c = deps.container();
      addTearDown(c.dispose);
      final registrar = c.read(pushRegistrarProvider);
      await registrar.listen();

      deps.push.deliver(<String, String>{
        'notification_id': 'notif-1',
        'kind': 'beat_plan_ready',
        'route': '/beat/$testDate',
      });
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect((await c.read(fieldRepositoryProvider).inbox()).items, isNotEmpty);
    });

    test('a tapped push hands its route to the app', () async {
      final deps = AgentDeps();
      addTearDown(deps.dispose);
      final routes = <String>[];
      final registrar = PushRegistrar(
        push: deps.push,
        api: deps.field,
        onRoute: routes.add,
      );
      addTearDown(registrar.dispose);
      deps.push.initial = const PushMessage(<String, String>{
        'route': '/visits/v1/confirm',
      });
      await registrar.listen();
      expect(routes, <String>['/visits/v1/confirm']);

      deps.push.open(<String, String>{
        'kind': 'flag_assigned',
        'route': '/flags/f1',
      });
      await Future<void>.delayed(Duration.zero);
      expect(routes.last, '/flags/f1');
    });

    test('a data message with no route falls back to the inbox', () {
      expect(
        const PushMessage(<String, String>{'kind': 'unknown'}).route,
        PushMessage.inboxRoute,
      );
    });
  });

  group('A63 log out', () {
    testWidgets('clears the push token, the caches and the session', (
      tester,
    ) async {
      final deps = AgentDeps();
      addTearDown(deps.dispose);
      await seedFieldCaches(deps);
      await tester.pumpWidget(deps.app(initialLocation: AppRoutes.settings));
      await tester.pumpAndSettle();
      final c = deps.container();
      addTearDown(c.dispose);
      await c.read(pushRegistrarProvider).registerAfterLogin();

      await tester.scrollUntilVisible(
        find.byKey(const Key('logout-setting')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(const Key('logout-setting')));
      await tester.pumpAndSettle();

      expect(deps.field.removedTokens, <String>['fcm-token-1']);
      expect(await deps.tokens.read(), isNull);
      expect((await c.read(fieldRepositoryProvider).flags()).value, isNull);
    });
  });
}

import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:farmerapp_farmer/router.dart';
import 'package:farmerapp_farmer/security.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'kisan_harness.dart';

/// FA-007 in the farmer app: the FCM token is registered after login and
/// withdrawn on logout, data messages land in the inbox, the badge counts
/// the unread ones and every deep link opens the right screen.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('push token', () {
    late KisanDeps deps;

    setUp(() async {
      deps = KisanDeps()..seedWorld();
      await deps.signIn();
    });
    tearDown(() => deps.dispose());

    test('is registered after login and cleared on logout', () async {
      final c = deps.container();
      addTearDown(c.dispose);
      final push = c.read(pushControllerProvider);

      expect(await push.signedIn(), KisanWrite.done);
      expect(deps.push.permissionAsks, 1);
      expect(deps.advisory.pushTokens, hasLength(1));
      expect(deps.advisory.pushTokens.single['token'], 'fcm-token-1');
      expect(deps.advisory.pushTokens.single['platform'], 'android');
      expect(deps.advisory.pushTokens.single['device_id'], 'dev-1');
      expect(
        await c.read(advisoryRepositoryProvider).registeredPushToken(),
        'fcm-token-1',
      );

      expect(await push.signedOut(), KisanWrite.done);
      expect(deps.advisory.removedPushTokens, <String>['fcm-token-1']);
      expect(deps.advisory.pushTokens, isEmpty);
      expect(deps.push.deletes, 1);
      expect(
        await c.read(advisoryRepositoryProvider).registeredPushToken(),
        isNull,
      );
    });

    test('a rotated token is registered again', () async {
      final c = deps.container();
      addTearDown(c.dispose);
      final push = c.read(pushControllerProvider);
      await push.signedIn();

      deps.push.rotate('fcm-token-2');
      await Future<void>.delayed(Duration.zero);
      expect(
        deps.advisory.pushTokens.map((t) => t['token']),
        contains('fcm-token-2'),
      );
    });

    test('a refused permission registers nothing', () async {
      deps.push.permission = PushPermission.denied;
      final c = deps.container();
      addTearDown(c.dispose);
      expect(
        await c.read(pushControllerProvider).signedIn(),
        KisanWrite.refused,
      );
      expect(deps.advisory.pushTokens, isEmpty);
    });

    test('the token is withdrawn by the remote wipe step', () async {
      final c = deps.container();
      addTearDown(c.dispose);
      final push = c.read(pushControllerProvider);
      await push.signedIn();

      await pushTokenWipeStep(push).run();
      expect(deps.advisory.removedPushTokens, <String>['fcm-token-1']);
    });
  });

  group('deep links', () {
    test('every kind opens its own screen', () {
      expect(
        farmerDeepLink(
          kind: NotificationKinds.diagnosisReviewed,
          route: '/diagnoses/d-9',
        ),
        AppRoutes.cropResult('d-9'),
      );
      expect(
        farmerDeepLink(
          kind: NotificationKinds.diagnosisReady,
          data: const <String, String>{'diagnosis_id': 'd-3'},
        ),
        AppRoutes.cropResult('d-3'),
      );
      expect(
        farmerDeepLink(
          kind: NotificationKinds.orderStatus,
          route: '/orders/o-7',
          data: const <String, String>{'status': 'ready'},
        ),
        AppRoutes.order('o-7'),
      );
      expect(
        farmerDeepLink(
          kind: NotificationKinds.visitConfirmRequest,
          route: '/visits/v-2/confirm',
        ),
        AppRoutes.visit('v-2'),
      );
      expect(
        farmerDeepLink(
          kind: NotificationKinds.cropTaskReminder,
          route: '/inbox',
          data: const <String, String>{'crop_plot_id': 'plot-1'},
        ),
        AppRoutes.calendar('plot-1'),
      );
      expect(
        farmerDeepLink(kind: NotificationKinds.outbreakAlert, route: '/inbox'),
        AppRoutes.alerts,
      );
      expect(
        farmerDeepLink(kind: 'something_new', route: '/inbox'),
        AppRoutes.inbox,
      );
    });
  });

  group('inbox', () {
    late KisanDeps deps;

    setUp(() async {
      deps = KisanDeps()..seedWorld();
      deps.seedAdvisory();
      deps.advisory
        ..addNotification(
          id: 'n-1',
          kind: NotificationKinds.diagnosisReviewed,
          route: '/diagnoses/d-9',
          data: const <String, Object?>{'diagnosis_id': 'd-9'},
        )
        ..addNotification(
          id: 'n-2',
          kind: NotificationKinds.cropTaskReminder,
          route: '/inbox',
          data: const <String, Object?>{
            'crop_plot_id': 'plot-1',
            'task_id': 'task-3',
          },
        )
        ..addNotification(
          id: 'n-3',
          kind: NotificationKinds.orderStatus,
          route: '/orders/o-1',
          data: const <String, Object?>{'order_id': 'o-1'},
          read: true,
        );
      await deps.signIn();
      await deps.primeAdvisory();
    });
    tearDown(() => deps.dispose());

    testWidgets('lists the rows, badges the unread ones and marks read', (
      tester,
    ) async {
      usePhoneSurface(tester);
      await pumpApp(tester, deps.app());
      // The badge on F10 counts the two unread rows.
      expect(find.byKey(const Key('home-inbox-badge')), findsOneWidget);
      expect(find.text('2'), findsWidgets);

      await tapIt(tester, find.byKey(const Key('home-inbox')));
      expect(find.byKey(const Key('inbox-n-1')), findsOneWidget);
      expect(find.byKey(const Key('inbox-unread-n-1')), findsOneWidget);
      expect(find.byKey(const Key('inbox-unread-n-3')), findsNothing);
      expect(find.text('Our expert checked your photo'), findsOneWidget);

      await tapIt(tester, find.byKey(const Key('inbox-read-all')));
      expect(
        deps.advisory.notificationRows.every((n) => n['read_at'] != null),
        isTrue,
      );
    });

    testWidgets('a reminder row opens the crop calendar', (tester) async {
      usePhoneSurface(tester);
      await pumpApp(tester, deps.app(initialLocation: AppRoutes.inbox));
      await tapIt(tester, find.byKey(const Key('inbox-n-2')));
      expect(find.byKey(const Key('calendar-week-1')), findsOneWidget);
    });

    testWidgets('an arriving push is filed and opens its screen', (
      tester,
    ) async {
      usePhoneSurface(tester);
      await pumpApp(tester, deps.app());

      deps.push.deliver(
        const PushMessage(
          kind: NotificationKinds.outbreakAlert,
          notificationId: 'n-9',
          route: '/inbox',
          data: <String, String>{
            'kind': NotificationKinds.outbreakAlert,
            'notification_id': 'n-9',
          },
        ),
      );
      await real(tester, () => Future<void>.delayed(Duration.zero));
      await settle(tester);

      // The deep link opened F44 by itself ...
      expect(find.byKey(const Key('alert-alert-1')), findsOneWidget);
      // ... and the push was filed in the inbox.
      await pumpApp(tester, deps.app(initialLocation: AppRoutes.inbox));
      expect(find.byKey(const Key('inbox-n-9')), findsOneWidget);
    });

    testWidgets('offline, the inbox is read from the cache and marks queue', (
      tester,
    ) async {
      deps.advisory.offline = true;
      deps.connectivity.online = false;
      usePhoneSurface(tester);
      await pumpApp(tester, deps.app(initialLocation: AppRoutes.inbox));
      expect(find.byKey(const Key('inbox-n-1')), findsOneWidget);
      expect(find.byType(OfflineBanner), findsOneWidget);

      final c = deps.container();
      addTearDown(c.dispose);
      expect(
        await c.read(advisoryRepositoryProvider).markRead('n-1'),
        KisanWrite.queued,
      );
      final rows = await c.read(outboxProvider).store.openOps();
      expect(rows.single.entity, SyncEntities.notification);
      expect(rows.single.entityId, 'n-1');
    });
  });
}

import 'package:farmerapp_agent/router.dart';
import 'package:farmerapp_agent/screens/home/home_screen.dart';
import 'package:farmerapp_agent/screens/onboarding/device_registered_screen.dart';
import 'package:farmerapp_agent/screens/onboarding/disclosure_screen.dart';
import 'package:farmerapp_agent/screens/onboarding/permissions_screen.dart';
import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../farmers/agent_harness.dart';
import 'duty_test_support.dart';

/// FA-011 A05 → A06 → A07 → A10: the acceptance is stored and queued, the
/// permissions are asked in order, and the duty toggle is usable only
/// after "I agree".
void main() {
  testWidgets('A05 shows the four points, the policy sheet and blocks until '
      '"I agree"; then A06 asks permissions in order; A07; A10 unblocked', (
    tester,
  ) async {
    usePhoneSurface(tester);
    final deps = AgentDeps();
    addTearDown(deps.dispose);
    deps.now = dutyT0;
    await tester.pumpWidget(deps.app(initialLocation: AppRoutes.disclosure));
    await tester.pumpAndSettle();

    expect(find.byType(DisclosureScreen), findsOneWidget);
    expect(find.text('Your location and data'), findsOneWidget);
    expect(
      find.text('We collect your location and visit photos.'),
      findsOneWidget,
    );
    expect(
      find.text('Location is collected only while you are on duty.'),
      findsOneWidget,
    );
    expect(
      find.text('It is used for travel allowance and visit credit.'),
      findsOneWidget,
    );
    expect(
      find.text('Your manager and owner can see it. Farmers cannot.'),
      findsOneWidget,
    );
    expect(find.text('Policy version 2026-09-v1'), findsOneWidget);
    expect(find.byKey(const Key('disclosure-updated')), findsNothing);

    // Full policy in a sheet.
    await tester.ensureVisible(find.byKey(const Key('disclosure-policy-link')));
    await tester.tap(find.byKey(const Key('disclosure-policy-link')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('policy-sheet')), findsOneWidget);
    expect(
      find.textContaining('Mitra location policy (version 2026-09-v1)'),
      findsOneWidget,
    );
    await tester.tapAt(const Offset(180, 20));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('policy-sheet')), findsNothing);

    // Read aloud exists (no TTS yet).
    await tester.ensureVisible(find.byKey(const Key('disclosure-read-aloud')));
    await tester.tap(find.byKey(const Key('disclosure-read-aloud')));
    await tester.pump();
    expect(find.text('Coming soon'), findsOneWidget);
    // Let the snackbar go: entrance animation, then its 4-second timer.
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);

    // Nothing accepted yet.
    expect(await SyncStore(deps.db).opsIn(<String>['queued']), isEmpty);

    await tester.tap(find.byKey(const Key('disclosure-agree')));
    await tester.pumpAndSettle();
    expect(find.byType(PermissionsScreen), findsOneWidget);
    final ops = await SyncStore(deps.db).opsIn(<String>['queued']);
    expect(ops.single.entity, 'policy_acceptance');
    final payload = SyncStore.payloadOf(ops.single);
    expect(payload['version'], '2026-09-v1');
    expect(payload['text_hash'], LocationPolicyDoc.bundled().textHash);
    expect(payload['device_id'], 'device-1');

    // A06: location first; background is disabled until location is granted.
    expect(find.text('Permissions Mitra needs'), findsOneWidget);
    Finder allowIn(String key) => find.descendant(
      of: find.byKey(Key(key)),
      matching: find.byType(AppButton),
    );
    final backgroundButton = tester.widget<AppButton>(
      allowIn('perm-backgroundLocation'),
    );
    expect(backgroundButton.onPressed, isNull);
    Future<void> allow(String key) async {
      await tester.ensureVisible(allowIn(key));
      await tester.tap(allowIn(key));
      await tester.pumpAndSettle();
    }

    await allow('perm-location');
    expect(deps.permissions.requests, <AppPermission>[AppPermission.location]);
    await allow('perm-backgroundLocation');
    await allow('perm-camera');
    await allow('perm-notifications');
    expect(deps.permissions.requests, <AppPermission>[
      AppPermission.location,
      AppPermission.backgroundLocation,
      AppPermission.camera,
      AppPermission.notifications,
    ]);
    expect(find.text('Allowed'), findsNWidgets(4));

    await tester.tap(find.byKey(const Key('permissions-continue')));
    await tester.pumpAndSettle();
    expect(find.byType(DeviceRegisteredScreen), findsOneWidget);
    expect(find.text('Device registered'), findsOneWidget);
    await tester.tap(find.byKey(const Key('registered-start')));
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
    final toggle = tester.widget<DutyToggle>(find.byType(DutyToggle));
    expect(toggle.blockedReason, isNull);
    expect(toggle.onChanged, isNotNull);
  });

  testWidgets('a permanently denied permission offers "Open settings"', (
    tester,
  ) async {
    usePhoneSurface(tester);
    final deps = AgentDeps();
    addTearDown(deps.dispose);
    deps.permissions.answers[AppPermission.camera] =
        PermissionOutcome.permanentlyDenied;
    await tester.pumpWidget(deps.app(initialLocation: AppRoutes.permissions));
    await tester.pumpAndSettle();
    final camera = find.descendant(
      of: find.byKey(const Key('perm-camera')),
      matching: find.byType(AppButton),
    );
    await tester.ensureVisible(camera);
    await tester.tap(camera);
    await tester.pumpAndSettle();
    expect(find.text('Open settings'), findsOneWidget);
    await tester.tap(camera);
    await tester.pumpAndSettle();
    expect(deps.permissions.settingsOpened, 1);
  });

  testWidgets('A05 comes back with an "updated" notice when the server has '
      'a newer version, and A10 stays blocked until re-accepted', (
    tester,
  ) async {
    usePhoneSurface(tester);
    final deps = AgentDeps();
    addTearDown(deps.dispose);
    deps.now = dutyT0;
    await acceptPolicy(deps);
    deps.policyApi.location = const LocationPolicyDoc(
      version: '2026-10-v2',
      textHash: 'h2',
      text: <String, String>{'en': 'Version two text'},
    );
    await tester.pumpWidget(deps.app(initialLocation: AppRoutes.home));
    await tester.pumpAndSettle();
    final ctx = tester.element(find.byType(HomeScreen));
    final container = ProviderScope.containerOf(ctx);
    expect(
      await container.read(locationPolicyProvider.notifier).refresh(),
      isTrue,
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Accept the location policy to go on duty'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('duty-blocked-action')));
    await tester.pumpAndSettle();
    expect(find.byType(DisclosureScreen), findsOneWidget);
    expect(find.byKey(const Key('disclosure-updated')), findsOneWidget);
    expect(find.text('Policy version 2026-10-v2'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('disclosure-policy-link')));
    await tester.tap(find.byKey(const Key('disclosure-policy-link')));
    await tester.pumpAndSettle();
    expect(find.text('Version two text'), findsOneWidget);
    await tester.tapAt(const Offset(180, 20));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('disclosure-agree')));
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.text('Accept the location policy to go on duty'), findsNothing);
    final ops = await SyncStore(deps.db).opsIn(<String>['queued']);
    expect(ops, hasLength(2));
    expect(SyncStore.payloadOf(ops.last)['version'], '2026-10-v2');
  });
}

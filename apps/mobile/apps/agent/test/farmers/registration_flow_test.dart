import 'package:farmerapp_agent/screens/farmers/add_farmer_wizard_screen.dart';
import 'package:farmerapp_agent/screens/farmers/farmer_profile_screen.dart';
import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'agent_harness.dart';

/// FA-012 + FA-013 end to end, offline: A20 → A21a–e through the UI with
/// two farms and three crop plots → outbox ops in order with the right
/// payloads and consent records → A22; then online sync applies all and
/// the local rows are clean.
void main() {
  late AgentDeps deps;

  setUp(() async {
    deps = AgentDeps(online: false);
    await seedVillage(deps.db);
  });

  tearDown(() => deps.dispose());

  Future<void> tapKey(WidgetTester tester, String key) async {
    final finder = find.byKey(Key(key));
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
    // Let any snackbar (blocked Next, resumed draft) time out.
    if (find.byType(SnackBar).evaluate().isNotEmpty) {
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    }
  }

  Future<void> typeKey(WidgetTester tester, String key, String text) async {
    final finder = find.descendant(
      of: find.byKey(Key(key)),
      matching: find.byType(TextField),
    );
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.enterText(finder, text);
    await tester.pumpAndSettle();
  }

  /// Taps four corners on the map around its centre (tap mode).
  Future<void> tapCorners(WidgetTester tester, double half) async {
    await tapKey(tester, 'reg-mode-tap');
    final map = find.byKey(const Key('reg-map'));
    await tester.ensureVisible(map);
    await tester.pumpAndSettle();
    final c = tester.getCenter(map);
    for (final d in <Offset>[
      Offset(-half, -half),
      Offset(half, -half),
      Offset(half, half),
      Offset(-half, half),
    ]) {
      await tester.tapAt(c + d);
      await tester.pump(const Duration(milliseconds: 400));
    }
    await tester.pumpAndSettle();
  }

  Future<void> pickSowingDate(WidgetTester tester, int plot) async {
    await tapKey(tester, 'reg-sowing-$plot');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
  }

  testWidgets('offline registration with 2 farms and 3 plots, then sync', (
    tester,
  ) async {
    usePhoneSurface(tester);
    await tester.pumpWidget(deps.app());
    await tester.pumpAndSettle();
    expect(find.text('No farmers yet'), findsOneWidget);
    expect(
      find.text('You are offline. Your work is saved and will sync later.'),
      findsOneWidget,
    );

    await tapKey(tester, 'farmers-add');
    expect(find.byType(AddFarmerWizardScreen), findsOneWidget);
    expect(find.text('Step 1 of 5'), findsOneWidget);

    // A21a: incomplete → Next blocked with issues.
    await tapKey(tester, 'reg-next');
    expect(find.text('Step 1 of 5'), findsOneWidget);
    expect(find.text('Enter the farmer name'), findsOneWidget);

    await typeKey(tester, 'reg-name', 'Ramesh Reddy');
    await typeKey(tester, 'reg-phone', '9876543210');
    // Offline: no OTP; "verify later" is offered.
    expect(find.byKey(const Key('reg-verify-later')), findsOneWidget);
    await tapKey(tester, 'reg-verify-later');
    expect(find.byKey(const Key('reg-verify-later-chosen')), findsOneWidget);
    expect(deps.verify.sent, isEmpty);

    await tapKey(tester, 'reg-village');
    await tester.tap(find.text('Kondapur · Sangareddy').last);
    await tester.pumpAndSettle();
    await typeKey(tester, 'reg-landmark', 'Near the temple');
    await tapKey(tester, 'reg-lang-te');
    await tapKey(tester, 'reg-own-own');
    await tapKey(tester, 'reg-next');
    expect(find.text('Step 2 of 5'), findsOneWidget);

    // A21b farm 1: four corners, declared area far off → VA-F03 warning.
    await tapCorners(tester, 60);
    expect(find.byKey(const Key('reg-computed-area')), findsOneWidget);
    await typeKey(tester, 'reg-area', '10');
    expect(find.byKey(const Key('reg-area-warning')), findsOneWidget);
    await tapKey(tester, 'reg-use-measured');
    expect(find.byKey(const Key('reg-area-warning')), findsNothing);
    await typeKey(tester, 'reg-farm-name', 'Home farm');
    await tapKey(tester, 'reg-soil-black');
    await tapKey(tester, 'reg-irrigation-borewell');
    await tapKey(tester, 'reg-next');
    expect(find.text('Step 3 of 5'), findsOneWidget);

    // A21c farm 1: one plot.
    await tapKey(tester, 'reg-next');
    expect(find.text('Step 3 of 5'), findsOneWidget); // blocked: no crop
    await tapKey(tester, 'reg-add-crop');
    await tapKey(tester, 'reg-crop-0-cotton');
    await typeKey(tester, 'reg-variety-0', 'Bt');
    await pickSowingDate(tester, 0);
    expect(find.textContaining('Season:'), findsOneWidget);

    // FA-013: second farm.
    await tapKey(tester, 'reg-add-farm');
    expect(find.text('Step 2 of 5'), findsOneWidget);
    expect(find.text('Farm 2'), findsOneWidget);
    await tapCorners(tester, 40);
    await tapKey(tester, 'reg-use-measured');
    await tapKey(tester, 'reg-next');
    await tapKey(tester, 'reg-add-crop');
    await tapKey(tester, 'reg-crop-0-paddy');
    await pickSowingDate(tester, 0);
    await tapKey(tester, 'reg-add-crop');
    await tapKey(tester, 'reg-crop-1-chilli');
    await pickSowingDate(tester, 1);
    expect(find.text('2 farms'), findsOneWidget);
    await tapKey(tester, 'reg-next');
    expect(find.text('Step 4 of 5'), findsOneWidget);

    // A21d: data consent required, marketing optional.
    await tapKey(tester, 'reg-next');
    expect(find.text('Step 4 of 5'), findsOneWidget);
    expect(find.text('Data consent is required to register'), findsOneWidget);
    await tapKey(tester, 'consent-data');
    await tapKey(tester, 'consent-marketing');
    await tapKey(tester, 'reg-next');
    expect(find.text('Step 5 of 5'), findsOneWidget);

    // A21e review.
    expect(find.byKey(const Key('reg-review-farm-0')), findsOneWidget);
    expect(find.byKey(const Key('reg-review-farm-1')), findsOneWidget);
    expect(find.byKey(const Key('reg-will-sync')), findsOneWidget);
    expect(find.textContaining('Will be verified later'), findsOneWidget);
    await tapKey(tester, 'reg-save');

    // A22.
    expect(find.byType(FarmerProfileScreen), findsOneWidget);
    expect(find.text('Ramesh Reddy'), findsOneWidget);
    expect(find.byKey(const Key('profile-pending-sync')), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Farm 2'),
      160,
      scrollable: find.descendant(
        of: find.byKey(const Key('profile-overview')),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Home farm'), findsOneWidget);
    expect(find.text('Farm 2'), findsOneWidget);

    // Outbox: farmer, farm, plot, farm, plot, plot, consent, consent.
    final store = SyncStore(deps.db);
    final ops = await store.opsIn(<String>['queued']);
    expect(ops.map((o) => '${o.entity}:${o.action}'), <String>[
      'farmer:create',
      'farm:create',
      'crop_plot:create',
      'farm:create',
      'crop_plot:create',
      'crop_plot:create',
      'consent_record:create',
      'consent_record:create',
    ]);
    final farmer = SyncStore.payloadOf(ops[0]);
    expect(farmer['name'], 'Ramesh Reddy');
    expect(farmer['phone'], '+919876543210');
    expect(farmer['village_id'], 'village-1');
    expect(farmer['landmark'], 'Near the temple');
    expect(farmer['language'], 'te');
    expect(farmer['land_ownership'], 'own');
    expect(farmer['phone_verified'], isFalse);
    expect(farmer['consent_marketing'], isTrue);
    expect(farmer.containsKey(phoneVerificationTokenKey), isFalse);
    final farm1 = SyncStore.payloadOf(ops[1]);
    expect(farm1['farmer_id'], farmer['id']);
    expect(farm1['name'], 'Home farm');
    expect(farm1['soil'], 'black');
    expect(farm1['irrigation'], 'borewell');
    expect(farm1['ownership'], 'own');
    expect((farm1['boundary']! as Map)['type'], 'Polygon');
    expect(farm1['area_acres'], closeTo(4.6, 1.0));
    final plot1 = SyncStore.payloadOf(ops[2]);
    expect(plot1['farm_id'], farm1['id']);
    expect(plot1['crop_id'], 'pilot:cotton');
    expect(plot1['variety'], 'Bt');
    expect(plot1['season'], isNotNull);
    expect(plot1['sowing_date'], matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')));
    final farm2 = SyncStore.payloadOf(ops[3]);
    expect(farm2['area_acres'], closeTo(2.0, 0.6));
    expect(SyncStore.payloadOf(ops[4])['crop_id'], 'pilot:paddy');
    expect(SyncStore.payloadOf(ops[5])['crop_id'], 'pilot:chilli');
    expect(SyncStore.payloadOf(ops[5])['farm_id'], farm2['id']);
    final consentData = SyncStore.payloadOf(ops[6]);
    expect(consentData['purpose'], 'data');
    expect(consentData['granted'], isTrue);
    expect(consentData['farmer_id'], farmer['id']);
    expect(consentData['language'], 'te');
    final consentMarketing = SyncStore.payloadOf(ops[7]);
    expect(consentMarketing['purpose'], 'marketing');
    expect(consentMarketing['granted'], isTrue);
    expect(await deps.db.getValue(RegistrationDraft.kvKey), isNull);
    expect(await deps.db.select(deps.db.consentRecords).get(), hasLength(2));

    // Back online: sync applies everything; rows clean; profile calm.
    final container = ProviderScope.containerOf(
      tester.element(find.byType(FarmerProfileScreen)),
    );
    deps.connectivity.online = true;
    final report = await container.read(syncEngineProvider).syncNow();
    expect(report.ok, isTrue);
    expect(report.applied, 8);
    expect(deps.api.appliedOps, hasLength(8));
    expect(deps.api.appliedOps.first.entity, 'farmer');
    expect(await store.opsIn(<String>['queued', 'rejected']), isEmpty);
    expect((await deps.db.select(deps.db.farmers).getSingle()).dirty, isFalse);
    expect(
      (await deps.db.select(deps.db.farms).get()).every(
        (f) => !f.dirty && f.version == 1,
      ),
      isTrue,
    );
    expect((await deps.db.select(deps.db.cropPlots).get()).length, 3);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('profile-pending-sync')), findsNothing);
  });

  testWidgets('an interrupted wizard resumes where it stopped', (tester) async {
    usePhoneSurface(tester);
    await tester.pumpWidget(deps.app(initialLocation: '/farmers/new'));
    await tester.pumpAndSettle();
    await typeKey(tester, 'reg-name', 'Lakshmi Devi');
    await typeKey(tester, 'reg-phone', '9000011122');
    await tapKey(tester, 'reg-verify-later');
    await tapKey(tester, 'reg-village');
    await tester.tap(find.text('Kondapur · Sangareddy').last);
    await tester.pumpAndSettle();
    await tapKey(tester, 'reg-lang-kn');
    await tapKey(tester, 'reg-next');
    expect(find.text('Step 2 of 5'), findsOneWidget);

    // "App killed": a fresh ProviderScope over the same database.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(deps.app(initialLocation: '/farmers/new'));
    await tester.pumpAndSettle();
    expect(find.text('Step 2 of 5'), findsOneWidget);
    expect(find.text('Continuing where you left off'), findsOneWidget);
    await tapKey(tester, 'reg-back');
    expect(find.text('Lakshmi Devi'), findsOneWidget);
    expect(find.text('9000011122'), findsOneWidget);
    expect(find.text('ಕನ್ನಡ'), findsOneWidget);

    await tapKey(tester, 'reg-discard');
    await tester.pumpAndSettle();
    expect(find.text('Farmers'), findsOneWidget);
    expect(await deps.db.getValue(RegistrationDraft.kvKey), isNull);
  });

  testWidgets('online: OTP to the farmer verifies the phone', (tester) async {
    deps.connectivity.online = true;
    usePhoneSurface(tester);
    await tester.pumpWidget(deps.app(initialLocation: '/farmers/new'));
    await tester.pumpAndSettle();
    await typeKey(tester, 'reg-phone', '9876543210');
    expect(find.byKey(const Key('reg-verify-later')), findsNothing);
    await tapKey(tester, 'reg-send-otp');
    expect(deps.verify.sent, <String>['+919876543210']);
    expect(
      find.text('OTP sent to the farmer. Ask them for the code.'),
      findsOneWidget,
    );
    final otp = find.descendant(
      of: find.byType(OtpInput),
      matching: find.byType(TextField),
    );
    await tester.enterText(otp, '000000');
    await tester.pumpAndSettle();
    expect(find.textContaining('Incorrect OTP'), findsOneWidget);
    await tester.enterText(otp, '');
    await tester.pump();
    await tester.enterText(otp, '123456');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('reg-phone-verified')), findsOneWidget);
    expect(find.text('Phone verified'), findsOneWidget);
    // Leave the OTP resend timer behind before the test ends.
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a local duplicate phone is blocked with a link', (tester) async {
    await seedSyncedFarmer(
      deps.db,
      id: 'f-existing',
      phone: '+919876543210',
      name: 'Existing Farmer',
    );
    usePhoneSurface(tester);
    await tester.pumpWidget(deps.app(initialLocation: '/farmers/new'));
    await tester.pumpAndSettle();
    await typeKey(tester, 'reg-name', 'Someone Else');
    await typeKey(tester, 'reg-phone', '9876543210');
    expect(
      find.text('A farmer with this number already exists'),
      findsOneWidget,
    );
    final send = tester.widget<AppButton>(
      find.byKey(const Key('reg-send-otp')),
    );
    expect(send.onPressed, isNull);
    await tapKey(tester, 'reg-verify-later');
    await tapKey(tester, 'reg-village');
    await tester.tap(find.text('Kondapur · Sangareddy').last);
    await tester.pumpAndSettle();
    await tapKey(tester, 'reg-lang-te');
    await tapKey(tester, 'reg-next');
    expect(find.text('Step 1 of 5'), findsOneWidget);

    await tapKey(tester, 'reg-open-duplicate');
    expect(find.byType(FarmerProfileScreen), findsOneWidget);
    expect(find.text('Existing Farmer'), findsOneWidget);
  });
}

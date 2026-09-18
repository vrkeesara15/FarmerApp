import 'package:farmerapp_agent/screens/farmers/farm_edit_screen.dart';
import 'package:farmerapp_agent/screens/farmers/farmer_profile_screen.dart';
import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'agent_harness.dart';

/// A22 / A23: overview facts, placeholder tabs and actions, the
/// "Duplicate — merge?" banner after a server rejection with a link to the
/// existing farmer, and adding / editing a farm (FA-013).
void main() {
  late AgentDeps deps;

  setUp(() async {
    deps = AgentDeps();
    await seedVillage(deps.db);
    await seedSyncedFarmer(deps.db, id: 'f-1', phone: '+919876543210');
  });

  tearDown(() => deps.dispose());

  /// Scrolls the Overview list until [finder] is built and visible.
  Future<void> reveal(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(
      finder,
      160,
      scrollable: find.descendant(
        of: find.byKey(const Key('profile-overview')),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('overview shows facts, crops, farm map and disabled actions', (
    tester,
  ) async {
    usePhoneSurface(tester);
    await tester.pumpWidget(deps.app(initialLocation: '/farmers/f-1'));
    await tester.pumpAndSettle();
    expect(find.text('Ramesh Reddy'), findsOneWidget);
    expect(find.text('9876543210 · Phone verified'), findsOneWidget);
    expect(find.text('Kondapur'), findsOneWidget);
    expect(find.text('Near the temple'), findsOneWidget);
    expect(find.text('తెలుగు'), findsOneWidget);
    await reveal(tester, find.text('Home farm'));
    expect(find.text('Home farm'), findsOneWidget);
    expect(find.byType(MapPanel), findsOneWidget);
    expect(
      find.text('2.50 acres · 2 crops · Black · Borewell'),
      findsOneWidget,
    );
    expect(find.text('Cotton'), findsWidgets);
    // FA-014: Start visit is live; the other actions arrive later.
    final start = tester.widget<AppButton>(
      find.byKey(const Key('profile-start-visit')),
    );
    expect(start.onPressed, isNotNull);
    for (final label in <String>['Scout', 'New order', 'Collect']) {
      final button = tester.widget<AppButton>(
        find.ancestor(of: find.text(label), matching: find.byType(AppButton)),
      );
      expect(button.onPressed, isNull, reason: label);
    }
    expect(find.byKey(const Key('profile-pending-sync')), findsNothing);
    expect(find.byKey(const Key('profile-duplicate')), findsNothing);

    await tester.tap(find.text('Visits'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('profile-visits-empty')), findsOneWidget);
    expect(find.text('No visits yet'), findsOneWidget);
  });

  testWidgets(
    'rejected as duplicate after sync: banner links to the existing farmer',
    (tester) async {
      // A second officer registered the same phone offline; the server rejects it.
      await Outbox(
        deps.db,
        clock: () => t0.add(const Duration(hours: 1)),
      ).enqueueCreate(SyncEntities.farmer, 'f-dup', <String, Object?>{
        'name': 'Ramesh R',
        'phone': '+919876543210',
        'village_id': 'village-1',
      });
      deps.api.validate = (op) => op.entityId == 'f-dup'
          ? const SyncError(farmerPhoneExistsCode, 'phone already registered')
          : null;
      usePhoneSurface(tester);
      await tester.pumpWidget(deps.app(initialLocation: '/farmers/f-dup'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('profile-pending-sync')), findsOneWidget);
      expect(find.byKey(const Key('profile-duplicate')), findsNothing);

      final container = ProviderScope.containerOf(
        tester.element(find.byType(FarmerProfileScreen)),
      );
      final report = await container.read(syncEngineProvider).syncNow();
      expect(report.rejected, 1);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('profile-duplicate')), findsOneWidget);
      expect(find.textContaining('Duplicate — merge?'), findsOneWidget);

      await tester.tap(find.byKey(const Key('profile-open-duplicate')));
      await tester.pumpAndSettle();
      expect(find.text('Ramesh Reddy'), findsOneWidget);
      expect(find.byKey(const Key('profile-duplicate')), findsNothing);
    },
  );

  testWidgets('A23: add a second farm queues farm + plot ops', (tester) async {
    usePhoneSurface(tester);
    await tester.pumpWidget(deps.app(initialLocation: '/farmers/f-1'));
    await tester.pumpAndSettle();
    await reveal(tester, find.byKey(const Key('profile-add-farm')));
    await tester.tap(find.byKey(const Key('profile-add-farm')));
    await tester.pumpAndSettle();
    expect(find.byType(FarmEditScreen), findsOneWidget);
    expect(find.text('Add farm'), findsOneWidget);
    expect(find.text('Step 1 of 2'), findsOneWidget);

    // Drive the boundary through the notifier (tap capture is covered by
    // the registration flow test) and the rest through the UI.
    final container = ProviderScope.containerOf(
      tester.element(find.byType(FarmEditScreen)),
    );
    final wizard = container.read(registrationProvider.notifier);
    for (final p in squareHectare) {
      await wizard.addCorner(p);
    }
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('reg-use-measured')));
    await tester.tap(find.byKey(const Key('reg-use-measured')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('farm-next')));
    await tester.tap(find.byKey(const Key('farm-next')));
    await tester.pumpAndSettle();
    expect(find.text('Step 2 of 2'), findsOneWidget);
    expect(find.byKey(const Key('reg-add-farm')), findsNothing);
    await tester.tap(find.byKey(const Key('reg-add-crop')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('reg-crop-0-maize')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('reg-sowing-0')));
    await tester.tap(find.byKey(const Key('reg-sowing-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('farm-save')));
    await tester.tap(find.byKey(const Key('farm-save')));
    await tester.pumpAndSettle();

    expect(find.byType(FarmerProfileScreen), findsOneWidget);
    await reveal(tester, find.text('Farm 2'));
    expect(find.byType(MapPanel), findsWidgets);
    final ops = await SyncStore(deps.db).opsIn(<String>['queued']);
    expect(ops.map((o) => '${o.entity}:${o.action}'), <String>[
      'farm:create',
      'crop_plot:create',
    ]);
    expect(SyncStore.payloadOf(ops[0])['farmer_id'], 'f-1');
    expect(SyncStore.payloadOf(ops[0])['area_acres'], closeTo(2.47, 0.01));
    expect(SyncStore.payloadOf(ops[1])['crop_id'], 'pilot:maize');
  });

  testWidgets('A23: edit farm loads the farm and queues an update', (
    tester,
  ) async {
    usePhoneSurface(tester);
    await tester.pumpWidget(deps.app(initialLocation: '/farmers/f-1'));
    await tester.pumpAndSettle();
    await reveal(tester, find.byKey(const Key('profile-edit-farm-farm-f-1')));
    await tester.tap(find.byKey(const Key('profile-edit-farm-farm-f-1')));
    await tester.pumpAndSettle();
    expect(find.text('Edit farm'), findsOneWidget);
    expect(find.text('4 points'), findsOneWidget);
    expect(find.text('2.5'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('reg-area')));
    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('reg-area')),
        matching: find.byType(TextField),
      ),
      '3',
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('farm-next')));
    await tester.tap(find.byKey(const Key('farm-next')));
    await tester.pumpAndSettle();
    expect(find.text('Crop 1'), findsOneWidget);
    expect(find.text('Crop 2'), findsOneWidget);
    await tester.tap(find.byKey(const Key('reg-remove-crop-1')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('farm-save')));
    await tester.tap(find.byKey(const Key('farm-save')));
    await tester.pumpAndSettle();
    final ops = await SyncStore(deps.db).opsIn(<String>['queued']);
    expect(ops.map((o) => '${o.entity}:${o.action}:${o.entityId}'), <String>[
      'farm:update:farm-f-1',
      'crop_plot:update:plot-f-1-0',
      'crop_plot:delete:plot-f-1-1',
    ]);
    expect(SyncStore.payloadOf(ops[0])['area_acres'], 3);
    expect(ops[0].baseVersion, 1);
  });
}

import 'package:farmerapp_agent/screens/farmers/add_farmer_wizard_screen.dart';
import 'package:farmerapp_agent/screens/farmers/farmer_profile_screen.dart';
import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'agent_harness.dart';

/// A20: FarmerCards from the local tables, search by name / phone digits /
/// village, filters, FAB to A21, card to A22.
void main() {
  late AgentDeps deps;

  setUp(() async {
    deps = AgentDeps();
    await seedVillage(deps.db);
    await seedVillage(
      deps.db,
      id: 'village-2',
      name: 'Nallagutta',
      mandal: 'Medak',
    );
    await seedSyncedFarmer(deps.db, id: 'f-1', phone: '+919876543210');
    await seedSyncedFarmer(
      deps.db,
      id: 'f-2',
      phone: '+919000011122',
      name: 'Lakshmi Devi',
      villageId: 'village-2',
      withFarm: false,
    );
  });

  tearDown(() => deps.dispose());

  testWidgets('lists farmers with village and crops; search narrows', (
    tester,
  ) async {
    usePhoneSurface(tester);
    await tester.pumpWidget(deps.app());
    await tester.pumpAndSettle();
    expect(find.text('2 farmers'), findsOneWidget);
    expect(find.byType(FarmerCard), findsNWidgets(2));
    expect(find.text('Ramesh Reddy'), findsOneWidget);
    expect(find.text('Kondapur'), findsOneWidget);
    expect(find.text('Cotton'), findsOneWidget);
    expect(find.text('Chilli'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('farmers-search')), 'laksh');
    await tester.pumpAndSettle();
    expect(find.byType(FarmerCard), findsOneWidget);
    expect(find.text('Lakshmi Devi'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('farmers-search')), '3210');
    await tester.pumpAndSettle();
    expect(find.text('Ramesh Reddy'), findsOneWidget);
    expect(find.text('Lakshmi Devi'), findsNothing);

    await tester.enterText(find.byKey(const Key('farmers-search')), 'nalla');
    await tester.pumpAndSettle();
    expect(find.text('Lakshmi Devi'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('farmers-search')), 'zzz');
    await tester.pumpAndSettle();
    expect(find.text('No farmers match your search'), findsOneWidget);
  });

  testWidgets('village and crop filters', (tester) async {
    usePhoneSurface(tester);
    await tester.pumpWidget(deps.app());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('farmers-filter-village')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nallagutta').last);
    await tester.pumpAndSettle();
    expect(find.byType(FarmerCard), findsOneWidget);
    expect(find.text('Lakshmi Devi'), findsOneWidget);
    expect(find.text('Village: Nallagutta'), findsOneWidget);

    await tester.tap(find.byKey(const Key('farmers-filter-village')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('All').last);
    await tester.pumpAndSettle();
    expect(find.byType(FarmerCard), findsNWidgets(2));

    await tester.tap(find.byKey(const Key('farmers-filter-crop')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Paddy').last);
    await tester.pumpAndSettle();
    expect(find.text('No farmers match your search'), findsOneWidget);
  });

  testWidgets('offline farmers show the pending note; FAB and cards navigate', (
    tester,
  ) async {
    await Outbox(
      deps.db,
      clock: () => t0.add(const Duration(hours: 1)),
    ).enqueueCreate(SyncEntities.farmer, 'f-3', <String, Object?>{
      'name': 'Venkat Rao',
      'phone': '+919111122233',
      'village_id': 'village-1',
    });
    usePhoneSurface(tester);
    await tester.pumpWidget(deps.app());
    await tester.pumpAndSettle();
    expect(find.text('Venkat Rao'), findsOneWidget);
    expect(find.text('Will sync when online'), findsOneWidget);

    await tester.tap(find.byKey(const Key('farmer-card-f-1')));
    await tester.pumpAndSettle();
    expect(find.byType(FarmerProfileScreen), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('farmers-add')));
    await tester.pumpAndSettle();
    expect(find.byType(AddFarmerWizardScreen), findsOneWidget);
  });

  testWidgets('A20 in Telugu', (tester) async {
    usePhoneSurface(tester);
    await tester.pumpWidget(deps.app(locale: const Locale('te')));
    await tester.pumpAndSettle();
    expect(find.text('రైతులు'), findsOneWidget);
    expect(find.text('పత్తి'), findsOneWidget);
  });
}

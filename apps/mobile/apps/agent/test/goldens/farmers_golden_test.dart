// Goldens for A20, A21a–e, A22 and A23 in Light and Sunlight at 360x800.
// Regenerate with: flutter test --update-goldens test/goldens
import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../farmers/agent_harness.dart';

/// Seeds a complete draft at [step] (two farms, three plots) into `kv` so
/// the wizard resumes there.
Future<void> seedDraft(AgentDeps deps, RegistrationStep step) async {
  final container = deps.container();
  final wizard = container.read(registrationProvider.notifier);
  await wizard.start(language: 'en');
  await wizard.setName('Ramesh Reddy');
  await wizard.setPhone('9876543210');
  await wizard.setVillage('village-1', name: 'Kondapur');
  await wizard.setLandmark('Near the temple');
  await wizard.setLanguage('te');
  await wizard.setLandOwnership('own');
  await wizard.sendOtp();
  await wizard.confirmOtp('123456');
  for (final p in squareHectare) {
    await wizard.addCorner(p);
  }
  await wizard.setDeclaredAcres(10);
  await wizard.setFarmName('Home farm');
  await wizard.setSoil('black');
  await wizard.setIrrigation('borewell');
  await wizard.addPlot();
  await wizard.updatePlot(
    wizard.state.draft!.farm!.plots.last.id,
    cropId: 'pilot:cotton',
    variety: 'Bt',
    sowingDate: DateTime(2026, 6, 15),
  );
  await wizard.addPlot();
  await wizard.updatePlot(
    wizard.state.draft!.farm!.plots.last.id,
    cropId: 'pilot:chilli',
    sowingDate: DateTime(2026, 7, 2),
  );
  await wizard.addFarm();
  for (final p in <GeoPoint>[
    offsetPoint(300, 0),
    offsetPoint(500, 0),
    offsetPoint(500, 200),
    offsetPoint(300, 200),
  ]) {
    await wizard.addCorner(p);
  }
  await wizard.useComputedAcres();
  await wizard.addPlot();
  await wizard.updatePlot(
    wizard.state.draft!.farm!.plots.last.id,
    cropId: 'pilot:paddy',
    sowingDate: DateTime(2026, 7, 10),
  );
  await wizard.selectFarm(0);
  await wizard.setConsentData(granted: true);
  await wizard.goTo(step);
  container.dispose();
}

void main() {
  for (final mode in AppThemeMode.values) {
    group(mode.name, () {
      testWidgets('a20_farmer_list', (tester) async {
        usePhoneSurface(tester);
        final deps = AgentDeps();
        addTearDown(deps.dispose);
        await seedVillage(deps.db);
        await seedSyncedFarmer(deps.db, id: 'f-1', phone: '+919876543210');
        await seedSyncedFarmer(
          deps.db,
          id: 'f-2',
          phone: '+919000011122',
          name: 'Lakshmi Devi',
          withFarm: false,
        );
        await Outbox(
          deps.db,
          clock: () => t0.add(const Duration(hours: 1)),
        ).enqueueCreate(SyncEntities.farmer, 'f-3', <String, Object?>{
          'name': 'Venkat Rao',
          'phone': '+919111122233',
          'village_id': 'village-1',
        });
        await tester.pumpWidget(deps.app(theme: mode));
        await tester.pumpAndSettle();
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/a20_farmer_list_${mode.name}.png'),
        );
      });

      for (final (name, step) in <(String, RegistrationStep)>[
        ('a21a_basics', RegistrationStep.basics),
        ('a21b_boundary', RegistrationStep.boundary),
        ('a21c_crops', RegistrationStep.crops),
        ('a21d_consent', RegistrationStep.consent),
        ('a21e_review', RegistrationStep.review),
      ]) {
        testWidgets(name, (tester) async {
          usePhoneSurface(tester);
          final deps = AgentDeps();
          addTearDown(deps.dispose);
          await seedVillage(deps.db);
          await seedDraft(deps, step);
          await tester.pumpWidget(
            deps.app(initialLocation: '/farmers/new', theme: mode),
          );
          await tester.pumpAndSettle();
          // The "continuing where you left off" snackbar times out.
          await tester.pump(const Duration(seconds: 5));
          await tester.pumpAndSettle();
          await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile('goldens/${name}_${mode.name}.png'),
          );
        });
      }

      testWidgets('a22_farmer_profile', (tester) async {
        usePhoneSurface(tester);
        final deps = AgentDeps();
        addTearDown(deps.dispose);
        await seedVillage(deps.db);
        await seedSyncedFarmer(deps.db, id: 'f-1', phone: '+919876543210');
        await tester.pumpWidget(
          deps.app(initialLocation: '/farmers/f-1', theme: mode),
        );
        await tester.pumpAndSettle();
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/a22_farmer_profile_${mode.name}.png'),
        );
      });

      testWidgets('a23_edit_farm', (tester) async {
        usePhoneSurface(tester);
        final deps = AgentDeps();
        addTearDown(deps.dispose);
        await seedVillage(deps.db);
        await seedSyncedFarmer(deps.db, id: 'f-1', phone: '+919876543210');
        await tester.pumpWidget(
          deps.app(initialLocation: '/farmers/f-1/farms/farm-f-1', theme: mode),
        );
        await tester.pumpAndSettle();
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/a23_edit_farm_${mode.name}.png'),
        );
      });
    });
  }
}

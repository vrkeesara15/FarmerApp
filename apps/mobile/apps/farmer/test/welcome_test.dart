import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:farmerapp_farmer/router.dart';
import 'package:farmerapp_farmer/screens/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'kisan_harness.dart';

/// FM-003: F05 shows an officer-registered farmer's farms and crops to
/// confirm or change with tap-only tiles; everyone else gets the quick
/// setup (crop tiles + village from a list, then size and sowing time).
void main() {
  late KisanDeps deps;

  setUp(() async {
    deps = KisanDeps()..seedWorld();
    await deps.signIn(welcomeDone: false);
    final c = deps.container();
    await c.read(kisanRepositoryProvider).refreshProfile();
    c.dispose();
  });
  tearDown(() => deps.dispose());

  testWidgets('officer-registered: prefilled from Ramesh, map, crops and '
      'stages; confirm goes home once', (tester) async {
    usePhoneSurface(tester);
    await pumpApp(tester, deps.app(initialLocation: AppRoutes.welcome));

    expect(
      find.text('Your farm details from Ramesh (field officer)'),
      findsOneWidget,
    );
    expect(find.byType(MapPanel), findsOneWidget);
    expect(find.text('Home farm'), findsOneWidget);
    expect(find.text('2.5 acres'), findsOneWidget);
    expect(find.text('Borewell'), findsOneWidget);
    expect(find.text('Black'), findsOneWidget);
    expect(find.text('Cotton'), findsOneWidget);
    expect(find.text('Chilli'), findsOneWidget);
    expect(find.text('Flowering'), findsOneWidget);
    // Read-only until "change": no edit affordances on the farm.
    expect(
      find.descendant(
        of: find.byKey(const Key('farm-farm-1')),
        matching: find.byIcon(Icons.edit_outlined),
      ),
      findsNothing,
    );

    await tapIt(tester, find.byKey(const Key('welcome-confirm')));
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(await deps.db.getValue(KisanRepository.welcomeDoneKey), 'true');
    expect(deps.kisan.writes.where((w) => w.$1.startsWith('PATCH')), isEmpty);
  });

  testWidgets('officer-registered: change the crop stage and irrigation with '
      'icon tiles (PATCH with the row version)', (tester) async {
    usePhoneSurface(tester);
    await pumpApp(tester, deps.app(initialLocation: AppRoutes.welcome));
    await tapIt(tester, find.byKey(const Key('welcome-edit')));
    expect(find.byIcon(Icons.edit_outlined), findsWidgets);

    await tapIt(tester, find.byKey(const Key('plot-plot-1')));
    expect(find.text('What stage is the crop in?'), findsOneWidget);
    await tapIt(tester, find.byKey(const Key('choice-fruiting')));
    expect(deps.kisan.writes.last.$1, 'PATCH /v1/crop-plots/plot-1');
    expect(deps.kisan.writes.last.$2, <String, Object?>{
      'version': 1,
      'stage': 'fruiting',
    });
    expect(find.text('Fruiting'), findsOneWidget);

    await tapIt(tester, find.byKey(const Key('farm-irrigation-farm-1')));
    await tapIt(tester, find.byKey(const Key('choice-drip')));
    expect(deps.kisan.writes.last.$1, 'PATCH /v1/farms/farm-1');
    expect(deps.kisan.writes.last.$2, <String, Object?>{
      'version': 2,
      'irrigation': 'drip',
    });
    expect(find.text('Drip'), findsOneWidget);
    // No text field anywhere in the edit (NF-010).
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('officer-registered offline: a change says it needs internet '
      'and keeps the value', (tester) async {
    usePhoneSurface(tester);
    await pumpApp(tester, deps.app(initialLocation: AppRoutes.welcome));
    deps.kisan.offline = true;
    await tapIt(tester, find.byKey(const Key('welcome-edit')));
    await tapIt(tester, find.byKey(const Key('plot-plot-1')));
    await tapIt(tester, find.byKey(const Key('choice-maturity')));
    expect(
      find.text('This needs internet. Try again when online.'),
      findsOneWidget,
    );
    expect(find.text('Flowering'), findsOneWidget);
  });

  testWidgets('not registered by an officer: quick setup with crop tiles and '
      'village list, then size and sowing time', (tester) async {
    usePhoneSurface(tester);
    deps.kisan.farmerRecord = farmerRecord(officerRegistered: false);
    await real(tester, () => seedVillage(deps.db));
    final c = deps.container();
    await real(tester, c.read(kisanRepositoryProvider).refreshProfile);
    c.dispose();
    await pumpApp(tester, deps.app(initialLocation: AppRoutes.welcome));

    expect(find.text('Which crop do you grow?'), findsOneWidget);
    final next = find.byKey(const Key('setup-next'));
    expect(tester.widget<AppButton>(next).onPressed, isNull);
    await tapIt(tester, find.byKey(const Key('setup-crop-cotton')));
    await tapIt(tester, find.byKey(const Key('setup-village-village-2')));
    await tapIt(tester, next);

    expect(find.text('How much land?'), findsOneWidget);
    await tapIt(tester, find.byKey(const Key('setup-acres-2')));
    await tapIt(tester, find.byKey(const Key('setup-sown-15')));
    await tapIt(tester, next);

    expect(find.byType(HomeScreen), findsOneWidget);
    final patch = deps.kisan.writes.firstWhere(
      (w) => w.$1 == 'PATCH /v1/farmers/f-1',
    );
    expect(patch.$2['village_id'], 'village-2');
    final farm = deps.kisan.writes.firstWhere(
      (w) => w.$1 == 'POST /v1/farmers/f-1/farms',
    );
    expect(farm.$2['area_acres'], 2.0);
    final plot = (farm.$2['crop_plots']! as List).single as Map;
    expect(plot['crop_id'], 'pilot:cotton');
    expect(plot['sowing_date'], '2026-09-04');
    expect(plot['season'], 'kharif');
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('quick setup can be skipped', (tester) async {
    usePhoneSurface(tester);
    deps.kisan.farmerRecord = farmerRecord(officerRegistered: false);
    final c = deps.container();
    await real(tester, c.read(kisanRepositoryProvider).refreshProfile);
    c.dispose();
    await pumpApp(tester, deps.app(initialLocation: AppRoutes.welcome));
    expect(
      find.textContaining('Village list not on this phone'),
      findsOneWidget,
    );
    await tapIt(tester, find.byKey(const Key('setup-skip')));
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(deps.kisan.writes.where((w) => w.$1.contains('/farms')), isEmpty);
  });
}

/// Inserts two synced villages (`village-1` Kondapur, `village-2` Gachibowli).
Future<void> seedVillage(AppDatabase db) async {
  final entities = LocalEntities(db);
  for (final (id, name) in <(String, String)>[
    ('village-1', 'Kondapur'),
    ('village-2', 'Gachibowli'),
  ]) {
    await entities.writeRef(
      SyncEntities.village,
      id,
      <String, Object?>{
        'name': name,
        'district': 'Medak',
        'mandal': 'Patancheru',
      },
      version: 1,
      now: t0,
    );
  }
}

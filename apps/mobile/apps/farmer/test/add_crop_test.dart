import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:farmerapp_farmer/router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'kisan_harness.dart';

/// F41 Add a crop (FM-007): tap-only tiles and a sowing-date calendar,
/// and the crop calendar is regenerated once the plot is saved.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late KisanDeps deps;

  setUp(() async {
    deps = KisanDeps()..seedWorld();
    deps.seedAdvisory();
    await deps.signIn();
    await deps.primeAdvisory();
  });
  tearDown(() => deps.dispose());

  testWidgets('saves a crop from tiles and a calendar, and regenerates', (
    tester,
  ) async {
    usePhoneSurface(tester);
    await pumpApp(tester, deps.app(initialLocation: AppRoutes.addCrop));

    // NF-010: nothing on the screen asks the farmer to type.
    expect(find.byType(EditableText, skipOffstage: false), findsNothing);

    await tapIt(tester, find.byKey(const Key('add-crop-paddy')));
    await scrollTo(tester, find.byKey(const Key('add-crop-date')));
    await tapIt(tester, find.text('15'));
    await scrollTo(tester, find.byKey(const Key('add-irrigation-borewell')));
    await tapIt(tester, find.byKey(const Key('add-irrigation-borewell')));
    await scrollTo(tester, find.byKey(const Key('add-soil-black')));
    await tapIt(tester, find.byKey(const Key('add-soil-black')));
    await scrollTo(tester, find.byKey(const Key('add-crop-save')));
    await tapIt(tester, find.byKey(const Key('add-crop-save')));

    final created = deps.kisan.writes
        .where((w) => w.$1 == 'POST /v1/farms/farm-1/crop-plots')
        .toList();
    expect(created, hasLength(1));
    expect(created.single.$2['crop_id'], '${CropRef.pilotIdPrefix}paddy');
    expect(created.single.$2['sowing_date'], '2026-09-15');
    expect(created.single.$2['season'], Seasons.kharif);
    expect(
      deps.advisory.calls,
      contains('GET /v1/me/calendar'),
      reason: 'the calendar is pulled again after the crop is added',
    );
  });

  testWidgets('the save button waits for a crop and a date', (tester) async {
    usePhoneSurface(tester);
    await pumpApp(tester, deps.app(initialLocation: AppRoutes.addCrop));
    await scrollTo(tester, find.byKey(const Key('add-crop-save')));
    final button = tester.widget<AppButton>(
      find.byKey(const Key('add-crop-save')),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('F40 opens F41 from the add button', (tester) async {
    usePhoneSurface(tester);
    await pumpApp(tester, deps.app(initialLocation: AppRoutes.crops));
    await tapIt(tester, find.byKey(const Key('crops-add')));
    expect(find.text('Which crop did you sow?'), findsOneWidget);
  });
}

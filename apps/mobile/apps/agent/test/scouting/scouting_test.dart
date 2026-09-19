import 'dart:typed_data';

import 'package:farmerapp_agent/router.dart';
import 'package:farmerapp_agent/screens/orders/cart_screen.dart';
import 'package:farmerapp_agent/screens/scouting/scouting_screens.dart';
import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../farmers/agent_harness.dart';
import '../orders/commerce_test_support.dart' show containerOf, tapIt;
import '../visits/visit_test_support.dart' show testJpeg;

/// FA-019 scouting (A40–A43): from A22 Scout or Home, the crop plot, the
/// same camera + quality gate, the `diagnosis` create op for the farmer and
/// the plot, A42 queued offline, A43 high-confidence and provisional
/// variants, "Create order for farmer" with the SKU and its label claim,
/// and the A22 Diagnoses tab.
void main() {
  late AgentDeps deps;

  setUp(() async {
    deps = AgentDeps();
    await seedVillage(deps.db);
    await seedSyncedFarmer(deps.db, id: 'f-1', phone: '+919876543210');
  });
  tearDown(() => deps.dispose());

  Future<void> open(WidgetTester tester, String location) async {
    usePhoneSurface(tester);
    await tester.pumpWidget(deps.app(initialLocation: location));
    await tester.pumpAndSettle();
  }

  Future<List<OutboxRow>> ops(String entity) async =>
      (await deps.db.select(deps.db.outboxTable).get())
          .where((o) => o.entity == entity)
          .toList();

  Future<void> shoot(WidgetTester tester) async {
    await tester.tap(find.byKey(GuidedCameraView.shutterKey));
    await tester.pumpAndSettle();
  }

  /// A22 → Scout → plot → A40 → shot → A41 use → submit.
  Future<void> scout(WidgetTester tester, {int shots = 1}) async {
    for (var i = 0; i < shots; i++) {
      deps.guidedCamera.enqueue(Uint8List.fromList(testJpeg()));
    }
    await open(tester, AppRoutes.farmerPath('f-1'));
    await tapIt(tester, find.byKey(const Key('profile-scout')));
    expect(find.byType(ScoutPlotScreen), findsOneWidget);
    await tapIt(tester, find.byKey(const Key('scout-plot-plot-f-1-0')));
    expect(find.byType(ScoutCameraScreen), findsOneWidget);
    expect(find.byType(CameraGuideOverlay), findsOneWidget);
  }

  Future<void> useAndSubmit(WidgetTester tester) async {
    await tapIt(tester, find.text('Use photo'));
    await tapIt(tester, find.byKey(const Key('scout-review-submit')));
    await tester.pumpAndSettle();
  }

  testWidgets('A40/A41: the gate refuses a blurry photo; the result (A43, '
      'high) is attached to the farmer and the plot; Create order for '
      'farmer carries the SKU and its label claim', (tester) async {
    deps.quality.enqueue(ScriptedQualityModel.blurry);
    await scout(tester, shots: 2);
    await shoot(tester);
    expect(find.byType(ScoutReviewScreen), findsOneWidget);
    expect(find.text('Blurry'), findsOneWidget);
    expect(
      tester
          .widget<AppButton>(find.widgetWithText(AppButton, 'Use photo'))
          .onPressed,
      isNull,
    );
    await tapIt(tester, find.text('Retake'));
    expect(find.byKey(CameraGuideOverlay.tipMessageKey), findsOneWidget);
    await shoot(tester);
    await useAndSubmit(tester);

    final create = deps.diagnosisServer.creates.single;
    expect(create.entity, SyncEntities.diagnosis);
    expect(create.payload['farmer_id'], 'f-1');
    expect(create.payload['crop_plot_id'], 'plot-f-1-0');
    expect(create.payload['on_device_model'], 'ondevice-v1.0');
    expect(create.payload['on_device'], <String, Object?>{
      'model': 'crop_quality',
      'model_version': 'ondevice-v1.0',
      'plant_score': 0.99,
      'quality': <String, Object?>{'ok': 0.96, 'blurry': 0.02, 'dark': 0.02},
      'crop_scores': <String, Object?>{
        'paddy': 0.03,
        'chilli': 0.93,
        'other': 0.04,
      },
      'latency_ms': 40,
    }, reason: 'DX-001 / DX-005 on-device block');
    expect(find.byType(ScoutResultScreen), findsOneWidget);
    expect(find.text('For Ramesh Reddy · Cotton'), findsOneWidget);
    expect(find.text('High confidence'), findsOneWidget);
    expect(find.text('Anthracnose (fruit rot)'), findsOneWidget);
    expect(find.byType(TreatmentCard), findsWidgets);
    expect(find.byType(ProductCard), findsWidgets);
    expect(find.byType(OwnBrandBadge), findsWidgets);
    await tester.scrollUntilVisible(
      find.byKey(const Key('scout-provenance')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Model ondevice-v1.0 · corpus v7'), findsOneWidget);
    // Stored with its confidence and model versions (DX-005).
    final stored = (await deps.db.select(deps.db.syncDocs).get())
        .where((r) => r.entity == SyncEntities.diagnosis)
        .single;
    expect(stored.data, contains('"confidence":"high"'));
    expect(stored.data, contains('"on_device":"ondevice-v1.0"'));

    expect(find.byKey(DiagnosisKeys.buy), findsOneWidget);
    expect(find.text('Create order for farmer'), findsWidgets);
    deps.connectivity.online = false;
    deps.api.offline = true;
    await tapIt(tester, find.byKey(DiagnosisKeys.buy));
    expect(find.byType(CartScreen), findsOneWidget);
    await tapIt(
      tester,
      find.descendant(
        of: find.byKey(const Key('cart-bar')),
        matching: find.byType(AppButton),
      ),
    );
    await tapIt(tester, find.byKey(const Key('payment-method-cash')));
    await tapIt(tester, find.byKey(const Key('checkout-submit')));
    final order = SyncStore.payloadOf((await ops('order')).single);
    expect(order['farmer_id'], 'f-1');
    expect(order['store_id'], 'store-1');
    expect(order['lines'], <Object?>[
      <String, Object?>{
        'sku_id': 'sku-azoxy',
        'qty': 1,
        'label_claim_id': 'lc-azoxy',
      },
    ]);
  });

  testWidgets('A43 provisional: no buy action anywhere, treatments still '
      'shown, ask an expert', (tester) async {
    deps.diagnosisServer.next = FakeDiagnosisOutcome.provisional;
    await scout(tester);
    await shoot(tester);
    await useAndSubmit(tester);
    expect(find.text('Provisional — expert will confirm'), findsOneWidget);
    expect(
      find.text('Our expert will confirm within 24 hours'),
      findsOneWidget,
    );
    void noBuy() {
      expect(find.byKey(DiagnosisKeys.buy), findsNothing);
      expect(find.text('Create order for farmer'), findsNothing);
      expect(find.byKey(DiagnosisKeys.orderProduct('sku-azoxy')), findsNothing);
      expect(find.byKey(DiagnosisKeys.orderProduct('sku-neem')), findsNothing);
    }

    noBuy();
    await tapIt(tester, find.text('Chemical'));
    await tester.scrollUntilVisible(
      find.byKey(DiagnosisKeys.treatment('sku-azoxy')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('15 ml'), findsWidgets);
    noBuy();
    await tapIt(tester, find.byKey(DiagnosisKeys.talkToOfficer));
    expect(deps.urls.opened.last, 'tel:+919876543210');
    await tapIt(tester, find.byKey(DiagnosisKeys.askExpert));
    expect(find.text('Our expert already has your photos'), findsOneWidget);
  });

  testWidgets('A42 offline: queued with the photos, then applied by sync; '
      'the A22 Diagnoses tab lists it', (tester) async {
    deps.connectivity.online = false;
    deps.api.offline = true;
    await scout(tester);
    await shoot(tester);
    await useAndSubmit(tester);
    expect(find.byKey(const Key('scout-queued')), findsOneWidget);
    expect(
      find.text('Queued. It will be sent when the phone is online.'),
      findsOneWidget,
    );
    expect(await ops(SyncEntities.diagnosis), hasLength(1));
    expect(deps.photos.files, hasLength(1));

    deps.connectivity.online = true;
    deps.api.offline = false;
    await tester.runAsync(() async {
      final c = containerOf(tester);
      await c.read(syncEngineProvider).syncNow();
    });
    await tester.pumpAndSettle();
    expect(find.text('Anthracnose (fruit rot)'), findsOneWidget);
    final create = deps.diagnosisServer.creates.single.payload;
    expect(create['crop_plot_id'], 'plot-f-1-0');
    final images = create['images']! as List;
    expect('${(images.single as Map)['blob_uri']}', startsWith('blob://'));

    await tester.pumpWidget(const SizedBox());
    await open(tester, AppRoutes.farmerPath('f-1'));
    await tapIt(tester, find.text('Diagnoses'));
    expect(find.byKey(const Key('profile-diagnoses')), findsOneWidget);
    expect(find.text('Anthracnose (fruit rot)'), findsOneWidget);
  });

  testWidgets('Home Scout picks a farmer first', (tester) async {
    await open(tester, AppRoutes.home);
    await tester.scrollUntilVisible(
      find.byKey(const Key('home-scout')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tapIt(tester, find.byKey(const Key('home-scout')));
    await tapIt(tester, find.byKey(const Key('pick-farmer-f-1')));
    expect(find.byType(ScoutPlotScreen), findsOneWidget);
    expect(find.byKey(const Key('scout-plot-plot-f-1-0')), findsOneWidget);
  });
}

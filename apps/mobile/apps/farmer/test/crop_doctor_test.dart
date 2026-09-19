import 'dart:typed_data';

import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:farmerapp_farmer/router.dart';
import 'package:farmerapp_farmer/screens/crop_doctor/crop_camera_screen.dart';
import 'package:farmerapp_farmer/screens/crop_doctor/diagnosis_result_screen.dart';
import 'package:farmerapp_farmer/screens/orders/cart_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'kisan_harness.dart';

/// A leaf-like textured photo (the scripted gate decides its verdict).
Uint8List leafShot([int seed = 1]) {
  final image = img.Image(width: 640, height: 480);
  for (var y = 0; y < 480; y++) {
    for (var x = 0; x < 640; x++) {
      final v = ((x * 7 + y * 13 + seed * 31) % 97) + 60;
      image.setPixelRgb(x, y, v ~/ 3, v, v ~/ 4);
    }
  }
  return Uint8List.fromList(img.encodeJpg(image, quality: 85));
}

/// FM-004 .. FM-006 crop doctor, F20–F28, on the farmer app.
void main() {
  late KisanDeps deps;

  setUp(() async {
    deps = KisanDeps()..seedWorld();
    await deps.signIn();
  });
  tearDown(() => deps.dispose());

  Future<void> loadProfile(WidgetTester tester) => real(tester, () async {
    final c = deps.container();
    await c.read(kisanRepositoryProvider).refreshProfile();
    c.dispose();
  });

  Future<void> shoot(WidgetTester tester) async {
    await tester.tap(find.byKey(GuidedCameraView.shutterKey));
    await settle(tester);
  }

  /// F20 → F21 → one good photo → F22 "Use photo".
  Future<void> oneGoodPhoto(WidgetTester tester) async {
    deps.camera.enqueue(leafShot());
    await pumpApp(tester, deps.app(initialLocation: AppRoutes.cropDoctor));
    await tapIt(tester, find.byKey(const Key('crop-doctor-start')));
    expect(find.byType(CropCameraScreen), findsOneWidget);
    await shoot(tester);
    await tapIt(tester, find.text('Use photo'));
  }

  /// F22 Continue → F23 → a crop tile → "Check my crop" → result screen.
  Future<void> chooseCropAndSubmit(
    WidgetTester tester, {
    String tile = 'crop-tile-cotton',
  }) async {
    await tapIt(tester, find.byKey(const Key('photo-check-continue')));
    await tapIt(tester, find.byKey(Key(tile)));
    await tapIt(tester, find.byKey(const Key('crop-choose-submit')));
    await pumpUntilFound(tester, find.byType(DiagnosisResultScreen));
  }

  testWidgets('F21/F22: blurry, dark and not-a-plant photos are refused with '
      'the matching tip and audio; the overlay lights the tip on retake', (
    tester,
  ) async {
    usePhoneSurface(tester);
    deps.quality
      ..enqueue(ScriptedQualityModel.blurry)
      ..enqueue(ScriptedQualityModel.dark)
      ..enqueue(ScriptedQualityModel.notPlant);
    for (var i = 0; i < 4; i++) {
      deps.camera.enqueue(leafShot(i));
    }
    await pumpApp(tester, deps.app(initialLocation: AppRoutes.cropDoctor));
    expect(find.byKey(const Key('crop-doctor-tips')), findsOneWidget);
    expect(find.byKey(const Key('audio-f20_intro')), findsOneWidget);
    await tapIt(tester, find.byKey(const Key('crop-doctor-start')));
    expect(find.byKey(const Key('fake-camera-preview')), findsOneWidget);
    expect(find.byType(CameraGuideOverlay), findsOneWidget);
    expect(find.text('Photo 1 of 3'), findsOneWidget);

    for (final (tip, badge, text) in <(String, String, String)>[
      (
        'photo_tip_blurry',
        'Blurry',
        'Hold the phone steady, tap the leaf to focus and take it again',
      ),
      (
        'photo_tip_dark',
        'Too dark',
        'Move into better light, away from shade, and take it again',
      ),
      (
        'photo_tip_not_plant',
        'No leaf seen',
        'Point the camera at the sick leaf and take it again',
      ),
    ]) {
      await shoot(tester);
      expect(find.byType(PhotoCheckScreen), findsOneWidget);
      expect(find.text(badge), findsOneWidget);
      expect(find.text(text), findsWidgets);
      expect(deps.audio.played.last.promptId, tip, reason: 'tip read aloud');
      final use = find.widgetWithText(AppButton, 'Use photo');
      expect(tester.widget<AppButton>(use).onPressed, isNull);
      expect(find.byKey(const Key('photo-check-continue')), findsNothing);
      await tapIt(tester, find.text('Retake'));
      expect(find.byType(CropCameraScreen), findsOneWidget);
      expect(find.byKey(CameraGuideOverlay.tipMessageKey), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(CameraGuideOverlay.tipMessageKey),
          matching: find.text(text),
        ),
        findsOneWidget,
      );
    }
    await shoot(tester);
    expect(find.text('Good photo'), findsOneWidget);
    await tapIt(tester, find.text('Use photo'));
    expect(find.text('1 of 3 photos ready'), findsOneWidget);
    expect(find.byKey(const Key('photo-check-add')), findsOneWidget);
    expect(deps.quality.calls, 4);
  });

  testWidgets('F23 manual crop tiles (the farmer\'s plots first); the '
      'diagnosis is attached to that plot; F25 with Order and the order '
      'carries the SKU and its label claim', (tester) async {
    usePhoneSurface(tester);
    await loadProfile(tester);
    await oneGoodPhoto(tester);
    await tapIt(tester, find.byKey(const Key('photo-check-continue')));
    expect(find.text('Which crop is this?'), findsWidgets);
    expect(
      find.byKey(const Key('crop-detected')),
      findsNothing,
      reason: 'on_device_crop_guess is off by default',
    );
    expect(find.byKey(const Key('crop-tile-cotton')), findsOneWidget);
    expect(find.byKey(const Key('crop-tile-unknown')), findsOneWidget);
    await tapIt(tester, find.byKey(const Key('crop-tile-chilli')));
    await tapIt(tester, find.byKey(const Key('crop-choose-submit')));
    await pumpUntilFound(tester, find.byKey(DiagnosisKeys.buy));

    final create = deps.diagnosisServer.creates.single.payload;
    expect(create['crop_plot_id'], 'plot-2');
    expect(create.containsKey('farmer_id'), isFalse, reason: 'own request');
    expect(create.containsKey('crop_guess'), isFalse);
    expect(create['on_device_model'], 'ondevice-v1.0');
    expect(create['images']! as List, hasLength(1));

    // F25: name, confidence in words, signs, products at the store.
    expect(find.text('We found the problem'), findsOneWidget);
    expect(find.text('Anthracnose (fruit rot)'), findsOneWidget);
    expect(find.text('High confidence'), findsOneWidget);
    expect(find.text('Sunken dark spots on the fruit'), findsOneWidget);
    await scrollTo(tester, find.byKey(DiagnosisKeys.store));
    expect(find.text('Products at FCC Kondapur'), findsOneWidget);
    expect(find.byType(OwnBrandBadge), findsWidgets);
    expect(find.byKey(DiagnosisKeys.talkToOfficer), findsOneWidget);

    // Order: the recommended chemical goes to the cart, then to the store.
    await tapIt(tester, find.byKey(DiagnosisKeys.buy));
    expect(find.byType(CartScreen), findsOneWidget);
    expect(find.text('Amistar 250 ml'), findsWidgets);
    await tapIt(
      tester,
      find.descendant(
        of: find.byKey(const Key('cart-bar')),
        matching: find.byType(AppButton),
      ),
    );
    await tapIt(tester, find.byKey(const Key('pay-store')));
    await tapIt(tester, find.byKey(const Key('pay-place')));
    final order = deps.kisan.writes.lastWhere((w) => w.$1 == 'POST /v1/orders');
    final lines = (order.$2 as Map)['lines']! as List;
    expect(lines.single, <String, Object?>{
      'sku_id': 'sku-azoxy',
      'qty': 1,
      'label_claim_id': 'lc-azoxy',
    });
    expect((order.$2 as Map)['store_id'], 'store-1');
  });

  testWidgets('F25: every chemical shows dose per acre and per 15 L tank '
      '(tank pictogram), PHI and PPE pictograms; a product card orders '
      'that SKU', (tester) async {
    usePhoneSurface(tester);
    await oneGoodPhoto(tester);
    await chooseCropAndSubmit(tester);
    await pumpUntilFound(tester, find.byKey(DiagnosisKeys.buy));
    await scrollTo(tester, find.text('Chemical'));
    await tapIt(tester, find.text('Chemical'));
    final card = find.byKey(DiagnosisKeys.treatment('sku-azoxy'));
    await scrollTo(tester, card);
    for (final text in <String>[
      '200 ml',
      '15 ml',
      'Wait 5 days before harvest',
      'Gloves',
      'Mask',
      'Goggles',
      'Full sleeves',
    ]) {
      expect(
        find.descendant(of: card, matching: find.text(text)),
        findsOneWidget,
        reason: text,
      );
    }
    expect(
      find.descendant(
        of: card,
        matching: find.byKey(const Key('treatment-tank')),
      ),
      findsOneWidget,
    );
    final orderMyclo = find.byKey(
      DiagnosisKeys.orderProduct('sku-mitra-myclo'),
    );
    await scrollTo(tester, orderMyclo);
    expect(
      tester.widget<AppButton>(orderMyclo).onPressed,
      isNull,
      reason: 'out of stock at the store',
    );
    final orderAzoxy = find.byKey(DiagnosisKeys.orderProduct('sku-azoxy'));
    await scrollTo(tester, orderAzoxy);
    await tapIt(tester, orderAzoxy);
    expect(find.byType(CartScreen), findsOneWidget);
  });

  testWidgets('F26 provisional: expert will confirm, no buy action at all, '
      'Talk to your field officer calls the officer', (tester) async {
    usePhoneSurface(tester);
    await loadProfile(tester);
    deps.diagnosisServer.next = FakeDiagnosisOutcome.provisional;
    await oneGoodPhoto(tester);
    await chooseCropAndSubmit(tester);
    await pumpUntilFound(tester, find.byKey(DiagnosisKeys.talkToOfficer));
    expect(find.text('Provisional — expert will confirm'), findsOneWidget);
    expect(
      find.text('Our expert will confirm within 24 hours'),
      findsOneWidget,
    );
    void noBuy() {
      expect(find.byKey(DiagnosisKeys.buy), findsNothing);
      expect(find.text('Order'), findsNothing);
      expect(find.byKey(DiagnosisKeys.orderProduct('sku-azoxy')), findsNothing);
      expect(find.byKey(DiagnosisKeys.orderProduct('sku-neem')), findsNothing);
    }

    noBuy();
    await scrollTo(tester, find.text('Chemical'));
    await tapIt(tester, find.text('Chemical'));
    await scrollTo(tester, find.byKey(DiagnosisKeys.treatment('sku-azoxy')));
    noBuy();
    await tapIt(tester, find.byKey(DiagnosisKeys.talkToOfficer));
    expect(deps.urls.opened.last, 'tel:+919100000001');
    // Ask an expert: already with the expert.
    await tapIt(tester, find.byKey(DiagnosisKeys.askExpert));
    expect(find.text('Our expert already has your photos'), findsOneWidget);
  });

  testWidgets('F24 offline: saved on the phone, "we\'ll check when you\'re '
      'online"; back online the sync applies the result', (tester) async {
    usePhoneSurface(tester);
    deps.connectivity.online = false;
    deps.syncApi.offline = true;
    await oneGoodPhoto(tester);
    await chooseCropAndSubmit(tester);
    expect(find.byKey(const Key('diagnosis-queued')), findsOneWidget);
    expect(find.text('Saved on your phone'), findsOneWidget);
    expect(find.text('We’ll check when you’re online'), findsOneWidget);
    expect(deps.diagnosisServer.creates, isEmpty);
    expect(deps.photos.files, hasLength(1), reason: 'photo kept on the phone');

    deps.syncApi.offline = false;
    deps.connectivity.online = true;
    deps.releaseDiagnosisPoll();
    await pumpUntilFound(tester, find.byKey(DiagnosisKeys.buy));
    expect(deps.diagnosisServer.creates, hasLength(1));
    expect(find.text('Anthracnose (fruit rot)'), findsOneWidget);
  });

  testWidgets('F27: the agronomist\'s review arrives by sync; home and the '
      'crop doctor flag it, the result shows the banner and the earlier '
      'answer, and buying becomes possible', (tester) async {
    usePhoneSurface(tester);
    deps.diagnosisServer.next = FakeDiagnosisOutcome.provisional;
    await oneGoodPhoto(tester);
    await chooseCropAndSubmit(tester);
    await pumpUntilFound(tester, find.byKey(DiagnosisKeys.talkToOfficer));
    final id = deps.diagnosisServer.creates.single.entityId;

    deps.diagnosisServer.review(id);
    await real(tester, () async {
      final c = deps.container();
      await c.read(kisanFlushProvider)();
      c.dispose();
    });
    await tester.pumpWidget(const SizedBox());
    await pumpApp(tester, deps.app());
    expect(find.byKey(const Key('home-diagnosis-updated')), findsOneWidget);
    expect(
      find.text('Crop check updated: Anthracnose (fruit rot)'),
      findsOneWidget,
    );
    await tapIt(tester, find.byKey(const Key('home-diagnosis-updated')));
    await pumpUntilFound(tester, find.byKey(DiagnosisKeys.updatedBanner));
    expect(find.text('Your result was updated'), findsOneWidget);
    expect(find.text('Our expert confirmed this result'), findsWidgets);
    expect(find.byKey(DiagnosisKeys.buy), findsOneWidget);
    await scrollTo(tester, find.text('Earlier answers'));
    expect(
      find.text('Earlier: Anthracnose (fruit rot) · Medium confidence'),
      findsOneWidget,
    );
  });

  testWidgets('F28 not a plant: friendly message, ask an expert, no buy', (
    tester,
  ) async {
    usePhoneSurface(tester);
    deps.diagnosisServer.next = FakeDiagnosisOutcome.notAPlant;
    await oneGoodPhoto(tester);
    await chooseCropAndSubmit(tester, tile: 'crop-tile-unknown');
    await pumpUntilFound(tester, find.byKey(DiagnosisKeys.outOfScope));
    expect(find.text('We could not see a plant in the photo'), findsOneWidget);
    expect(find.byKey(DiagnosisKeys.buy), findsNothing);
    expect(deps.diagnosisServer.creates.single.payload['crop_id'], 'unknown');
    await tapIt(tester, find.byKey(DiagnosisKeys.askExpert));
    expect(find.text('Our expert already has your photos'), findsOneWidget);
  });

  testWidgets('crop guess behind the flag: detected crop pre-selected, the '
      'farmer overrides it with a tile', (tester) async {
    usePhoneSurface(tester);
    await loadProfile(tester);
    deps.cropGuessFlag = true;
    await oneGoodPhoto(tester);
    // Detected chilli: F22 shows it with "Change crop".
    expect(find.text('Crop: Chilli'), findsOneWidget);
    await tapIt(tester, find.byKey(const Key('photo-check-change-crop')));
    expect(find.byKey(const Key('crop-detected')), findsOneWidget);
    expect(
      find.text('Looks like Chilli. Tap another crop if this is wrong.'),
      findsOneWidget,
    );
    await tapIt(tester, find.byKey(const Key('crop-tile-cotton')));
    await tapIt(tester, find.byKey(const Key('crop-choose-submit')));
    await pumpUntilFound(tester, find.byType(DiagnosisResultScreen));
    final create = deps.diagnosisServer.creates.single.payload;
    expect(create['crop_plot_id'], 'plot-1', reason: 'the farmer\'s choice');
    expect(create['crop_guess'], <String, Object?>{
      'code': 'chilli',
      'confidence': 0.93,
    });
  });

  testWidgets('results stay readable offline (NF-002)', (tester) async {
    usePhoneSurface(tester);
    await oneGoodPhoto(tester);
    await chooseCropAndSubmit(tester);
    await pumpUntilFound(tester, find.byKey(DiagnosisKeys.buy));
    final id = deps.diagnosisServer.creates.single.entityId;
    deps.connectivity.online = false;
    deps.diagnosisApi.offline = true;
    await tester.pumpWidget(const SizedBox());
    await pumpApp(tester, deps.app(initialLocation: AppRoutes.cropDoctor));
    await scrollTo(tester, find.byKey(Key('crop-check-$id')));
    expect(find.text('My crop checks'), findsOneWidget);
    await tapIt(tester, find.byKey(Key('crop-check-$id')));
    await pumpUntilFound(tester, find.text('Anthracnose (fruit rot)'));
    expect(find.byType(OfflineBanner), findsOneWidget);
  });

  testWidgets('F62 without the officer contact: graceful, buttons off', (
    tester,
  ) async {
    usePhoneSurface(tester);
    deps.kisan.farmerRecord = farmerRecord(withOfficerContact: false);
    await loadProfile(tester);
    await pumpApp(tester, deps.app(initialLocation: AppRoutes.officer));
    expect(find.text('Your field officer'), findsOneWidget);
    expect(
      tester.widget<AppButton>(find.byKey(const Key('officer-call'))).onPressed,
      isNull,
    );
    expect(
      find.text(
        'The officer’s phone is not in the app yet. Ask at your store.',
      ),
      findsOneWidget,
    );
  });
}

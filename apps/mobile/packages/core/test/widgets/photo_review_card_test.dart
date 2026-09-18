import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import '../helpers/harness.dart';

const PhotoQualityResult _ok = PhotoQualityResult(
  isBlurry: false,
  blurScore: 240,
  isTooDark: false,
  brightness: 0.45,
  tipKey: PhotoTipKeys.ok,
);
const PhotoQualityResult _blurry = PhotoQualityResult(
  isBlurry: true,
  blurScore: 12,
  isTooDark: false,
  brightness: 0.45,
  tipKey: PhotoTipKeys.blurry,
);
const PhotoQualityResult _dark = PhotoQualityResult(
  isBlurry: true,
  blurScore: 1,
  isTooDark: true,
  brightness: 0.05,
  tipKey: PhotoTipKeys.dark,
);

Widget _card({
  PhotoQualityResult? quality,
  VoidCallback? onRetake,
  VoidCallback? onUse,
  ImageProvider<Object>? thumbnail,
  int? index,
  int? total,
}) {
  return PhotoReviewCard(
    sizeBytes: 186 * 1024 + 400,
    width: 1280,
    height: 960,
    quality: quality,
    thumbnail: thumbnail,
    index: index,
    total: total,
    onRetake: onRetake ?? () {},
    onUse: onUse ?? () {},
  );
}

bool _useEnabled(WidgetTester tester) {
  final button = tester.widget<AppButton>(
    find.widgetWithText(AppButton, 'Use photo'),
  );
  return button.onPressed != null;
}

void main() {
  testWidgets('good photo: badge, size, dimensions, use enabled', (
    tester,
  ) async {
    var used = 0;
    await tester.pumpWidget(
      harness(_card(quality: _ok, index: 1, total: 3, onUse: () => used++)),
    );
    expect(find.text('Photo 1 of 3'), findsOneWidget);
    expect(find.text('Good photo'), findsOneWidget);
    expect(find.text('Photo looks good'), findsOneWidget);
    expect(find.text('186 KB'), findsOneWidget);
    expect(find.text('1280 × 960 px'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
    expect(_useEnabled(tester), isTrue);
    await tester.tap(find.text('Use photo'));
    expect(used, 1);
  });

  testWidgets('blurry photo: retake tip, use disabled, retake works', (
    tester,
  ) async {
    var retakes = 0;
    var used = 0;
    await tester.pumpWidget(
      harness(
        _card(quality: _blurry, onRetake: () => retakes++, onUse: () => used++),
      ),
    );
    expect(find.text('Check your photo'), findsOneWidget);
    expect(find.text('Blurry'), findsOneWidget);
    expect(
      find.text(
        'Hold the phone steady, tap the leaf to focus and take it again',
      ),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.blur_on), findsOneWidget);
    expect(_useEnabled(tester), isFalse);
    await tester.tap(find.text('Use photo'), warnIfMissed: false);
    expect(used, 0);
    await tester.tap(find.text('Retake'));
    expect(retakes, 1);
  });

  testWidgets('dark photo: light tip and use disabled', (tester) async {
    await tester.pumpWidget(harness(_card(quality: _dark)));
    expect(find.text('Too dark'), findsOneWidget);
    expect(
      find.text('Move into better light, away from shade, and take it again'),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.brightness_low_outlined), findsOneWidget);
    expect(_useEnabled(tester), isFalse);
  });

  testWidgets('checking state while the quality gate runs', (tester) async {
    await tester.pumpWidget(harness(_card()));
    expect(find.text('Checking photo'), findsOneWidget);
    expect(find.byIcon(Icons.hourglass_top_outlined), findsOneWidget);
    expect(_useEnabled(tester), isFalse);
    // Retake is always available.
    expect(
      tester
          .widget<AppButton>(find.widgetWithText(AppButton, 'Retake'))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('thumbnail renders when given, placeholder otherwise', (
    tester,
  ) async {
    await tester.pumpWidget(harness(_card(quality: _ok)));
    expect(find.byIcon(Icons.photo_outlined), findsOneWidget);
    expect(find.byType(Image), findsNothing);

    final tiny = img.encodePng(
      img.Image(width: 4, height: 3)..clear(img.ColorRgb8(40, 120, 40)),
    );
    await tester.pumpWidget(
      harness(_card(quality: _ok, thumbnail: MemoryImage(tiny))),
    );
    expect(find.byType(Image), findsOneWidget);
    expect(find.byIcon(Icons.photo_outlined), findsNothing);
  });

  testWidgets('touch targets and semantics', (tester) async {
    await tester.pumpWidget(harness(_card(quality: _ok, index: 2, total: 3)));
    final retake = tester.getSize(find.widgetWithText(AppButton, 'Retake'));
    expect(retake.height, greaterThanOrEqualTo(Tokens.sizeTouchTargetMin));
    expect(
      find.bySemanticsLabel(RegExp('Photo 2 of 3.*Good photo.*186 KB')),
      findsOneWidget,
    );
  });

  testWidgets('Telugu strings resolve', (tester) async {
    await tester.pumpWidget(
      harness(
        _card(quality: _blurry, index: 1, total: 3),
        locale: const Locale('te'),
      ),
    );
    expect(find.text('ఫోటో 1 / 3'), findsOneWidget);
    expect(find.text('మసకగా ఉంది'), findsOneWidget);
    expect(find.text('మళ్ళీ తీయండి'), findsOneWidget);
    expect(find.text('ఈ ఫోటో వాడండి'), findsOneWidget);
  });
}

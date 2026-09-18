import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/harness.dart';

void main() {
  testWidgets('default overlay shows the frame label and three tips', (
    tester,
  ) async {
    await tester.pumpWidget(harness(const CameraGuideOverlay(), padded: false));
    expect(find.text('Place the leaf inside the frame'), findsOneWidget);
    expect(find.text('Hold steady'), findsOneWidget);
    expect(find.text('Good light'), findsOneWidget);
    expect(find.text('Fill the frame'), findsOneWidget);
    expect(find.byKey(CameraGuideOverlay.tipMessageKey), findsNothing);
  });

  testWidgets('blurry result highlights "hold steady" with its tip', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(
        const CameraGuideOverlay(tipKey: PhotoTipKeys.blurry),
        padded: false,
      ),
    );
    expect(
      find.text(
        'Hold the phone steady, tap the leaf to focus and take it again',
      ),
      findsOneWidget,
    );
    expect(CameraGuideOverlay.highlightedTip(PhotoTipKeys.blurry), 0);
  });

  testWidgets('dark result highlights "good light" with its tip', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(
        const CameraGuideOverlay(tipKey: PhotoTipKeys.dark),
        padded: false,
      ),
    );
    expect(
      find.text('Move into better light, away from shade, and take it again'),
      findsOneWidget,
    );
    expect(CameraGuideOverlay.highlightedTip(PhotoTipKeys.dark), 1);
  });

  testWidgets('ok result shows the good-photo line', (tester) async {
    await tester.pumpWidget(
      harness(const CameraGuideOverlay(tipKey: PhotoTipKeys.ok), padded: false),
    );
    expect(find.text('Photo looks good'), findsOneWidget);
    expect(CameraGuideOverlay.highlightedTip(PhotoTipKeys.ok), isNull);
  });

  testWidgets('Hindi tip resolves', (tester) async {
    await tester.pumpWidget(
      harness(
        const CameraGuideOverlay(tipKey: PhotoTipKeys.dark),
        padded: false,
        locale: const Locale('hi'),
      ),
    );
    expect(
      find.text('अच्छी रोशनी में जाएँ, छाया से बाहर आएँ और फिर से लें'),
      findsOneWidget,
    );
  });
}

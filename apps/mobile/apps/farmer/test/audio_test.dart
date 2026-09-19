import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:farmerapp_farmer/router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'kisan_harness.dart';

/// NF-009 / FM-001: speaker buttons next to key instructions play through
/// the `AudioPrompt` seam (device TTS now, recorded clips later) in the
/// right language; a language without a voice says "audio unavailable".
void main() {
  late KisanDeps deps;

  setUp(() => deps = KisanDeps()..seedWorld(dataConsent: false));
  tearDown(() => deps.dispose());

  testWidgets('F01: each tile speaks its own short prompt in its own '
      'language; the title speaker reads the instruction', (tester) async {
    usePhoneSurface(tester);
    await pumpApp(tester, deps.app(initialLocation: AppRoutes.language));
    await tapIt(tester, find.text('వినండి'));
    await tapIt(tester, find.text('सुनें'));
    await tapIt(tester, find.byKey(const Key('audio-f01_choose_language')));
    expect(
      deps.audio.played.map((p) => (p.promptId, p.locale.languageCode)),
      <(String, String)>[
        ('f01_language', 'te'),
        ('f01_language', 'hi'),
        ('f01_choose_language', 'en'),
      ],
    );
    expect(
      deps.audio.played.first.text,
      'మీరు తెలుగు ఎంచుకున్నారు. కొనసాగించు నొక్కండి.',
    );
    expect(deps.audio.played.last.text, contains('Choose your language'));
    // Listening never switches the language: only the tile itself does.
    expect(find.text('Choose your language'), findsOneWidget);
  });

  testWidgets('F01: a language with no voice on the phone shows "audio '
      'unavailable" in that language and cannot be tapped', (tester) async {
    usePhoneSurface(tester);
    deps.audio.unavailable.add('kn');
    await pumpApp(tester, deps.app(initialLocation: AppRoutes.language));
    expect(find.text('ಧ್ವನಿ ಲಭ್ಯವಿಲ್ಲ'), findsOneWidget);
    expect(
      find.byIcon(Icons.volume_off_outlined, skipOffstage: false),
      findsOneWidget,
    );
    // The other four tiles and the instruction speaker still play.
    expect(
      find.byIcon(Icons.volume_up_outlined, skipOffstage: false),
      findsNWidgets(5),
    );
    // The disabled speaker plays nothing (the tap falls to the tile, which
    // selects Kannada: then the instruction speaker has no voice either).
    await tester.tap(find.text('ಧ್ವನಿ ಲಭ್ಯವಿಲ್ಲ'));
    await settle(tester);
    expect(deps.audio.played, isEmpty);
    expect(
      find.byIcon(Icons.volume_off_outlined, skipOffstage: false),
      findsNWidgets(2),
    );
  });

  testWidgets('F04 in Telugu: read aloud speaks the Telugu card text; with '
      'no Telugu voice the button says so', (tester) async {
    usePhoneSurface(tester);
    await real(tester, deps.signIn);
    await pumpApp(
      tester,
      deps.app(initialLocation: AppRoutes.consent, locale: const Locale('te')),
    );
    final te = lookupCoreLocalizations(const Locale('te'));
    await tapIt(tester, find.byKey(const Key('audio-f04_data')));
    expect(deps.audio.played.single.locale, const Locale('te'));
    expect(deps.audio.played.single.text, startsWith(te.consentDataCardTitle));
    expect(deps.audio.played.single.text, contains(te.kisanConsentDataNotice));

    deps.audio.unavailable.add('te');
    await pumpApp(
      tester,
      deps.app(initialLocation: AppRoutes.welcome, locale: const Locale('te')),
    );
    await pumpApp(
      tester,
      deps.app(initialLocation: AppRoutes.consent, locale: const Locale('te')),
    );
    expect(find.text(te.audioUnavailable), findsWidgets);
    expect(find.byKey(const Key('audio-f04_data')), findsOneWidget);
    final disabled = tester.widget<TextButton>(
      find.byKey(const Key('audio-f04_data')),
    );
    expect(disabled.onPressed, isNull);
  });

  test('SilentAudioPrompt is never available', () async {
    const silent = SilentAudioPrompt();
    expect(await silent.isAvailable(const Locale('te')), isFalse);
    expect(
      await silent.play(promptId: 'x', text: 'y', locale: const Locale('te')),
      AudioPlayResult.unavailable,
    );
  });
}

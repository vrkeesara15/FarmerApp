import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/harness.dart';

const List<Locale> _five = <Locale>[
  Locale('te'),
  Locale('kn'),
  Locale('hi'),
  Locale('mr'),
  Locale('en'),
];

void main() {
  for (final locale in _five) {
    testWidgets('renders all five tiles under locale ${locale.languageCode}', (
      tester,
    ) async {
      usePhoneSurface(tester);
      await tester.pumpWidget(
        harness(
          SingleChildScrollView(
            child: LanguagePicker(onSelected: (_) {}, onPlayAudio: (_) {}),
          ),
          locale: locale,
        ),
      );
      // Script names are literal so anyone can find their language.
      for (final option in LanguageOption.launchLanguages) {
        expect(find.text(option.nativeName), findsAtLeastNWidgets(1));
      }
      // The caption (English name) is in the current UI language.
      final l10n = lookupCoreLocalizations(locale);
      for (final name in <String>[
        l10n.languageTeluguName,
        l10n.languageKannadaName,
        l10n.languageHindiName,
        l10n.languageMarathiName,
        l10n.languageEnglishName,
      ]) {
        expect(find.text(name), findsAtLeastNWidgets(1));
      }
      // Each speaker icon is paired with a "Listen" label in the tile's own
      // language (NF-009: icons always carry a text label).
      expect(find.byIcon(Icons.volume_up_outlined), findsNWidgets(5));
      for (final option in LanguageOption.launchLanguages) {
        expect(
          find.text(lookupCoreLocalizations(option.locale).languagePlayAudio),
          findsOneWidget,
        );
      }
    });
  }

  testWidgets('tap selects, speaker plays, selection is announced', (
    tester,
  ) async {
    usePhoneSurface(tester);
    Locale? selected;
    Locale? played;
    await tester.pumpWidget(
      harness(
        SingleChildScrollView(
          child: LanguagePicker(
            selected: const Locale('kn'),
            onSelected: (l) => selected = l,
            onPlayAudio: (l) => played = l,
          ),
        ),
      ),
    );
    await tester.tap(find.text('हिन्दी'));
    expect(selected, const Locale('hi'));
    await tester.tap(
      find.text(lookupCoreLocalizations(const Locale('te')).languagePlayAudio),
    );
    expect(played, const Locale('te'));
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
    // Tile announces "<native>, <english>"; speaker announces "Listen <native>".
    expect(find.bySemanticsLabel('ಕನ್ನಡ, Kannada'), findsOneWidget);
    expect(find.bySemanticsLabel('వినండి తెలుగు'), findsOneWidget);
  });

  testWidgets('speaker buttons hide when no audio callback', (tester) async {
    usePhoneSurface(tester);
    await tester.pumpWidget(
      harness(SingleChildScrollView(child: LanguagePicker(onSelected: (_) {}))),
    );
    expect(find.byIcon(Icons.volume_up_outlined), findsNothing);
  });
}

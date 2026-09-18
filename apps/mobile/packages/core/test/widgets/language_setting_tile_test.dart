import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/harness.dart';

void main() {
  testWidgets('shows the current language and changes it from a sheet', (
    tester,
  ) async {
    usePhoneSurface(tester);
    Locale? changed;
    await tester.pumpWidget(
      harness(
        LanguageSettingTile(
          value: const Locale('te'),
          onChanged: (l) => changed = l,
        ),
        locale: const Locale('te'),
      ),
    );
    final l10n = lookupCoreLocalizations(const Locale('te'));
    expect(find.text(l10n.settingsLanguage), findsOneWidget);
    expect(find.text('తెలుగు'), findsOneWidget);
    expect(find.byType(LanguagePicker), findsNothing);

    await tester.tap(find.byKey(const Key('language-setting')));
    await tester.pumpAndSettle();
    expect(find.byType(LanguagePicker), findsOneWidget);
    expect(find.text(l10n.languagePickerTitle), findsOneWidget);

    await tester.tap(find.text('ಕನ್ನಡ'));
    await tester.pumpAndSettle();
    expect(changed, const Locale('kn'));
    expect(find.byType(LanguagePicker), findsNothing);
  });

  testWidgets('falls back to the picker title when nothing is chosen', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(LanguageSettingTile(value: null, onChanged: (_) {})),
    );
    final l10n = lookupCoreLocalizations(const Locale('en'));
    expect(find.text(l10n.languagePickerTitle), findsOneWidget);
  });
}

import 'package:farmerapp_agent/app.dart';
import 'package:farmerapp_agent/router.dart';
import 'package:farmerapp_agent/screens/phone_screen.dart';
import 'package:farmerapp_agent/screens/splash_screen.dart';
import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// FA-004: language switch without restart, persisted across app starts,
/// and the A63 setting drives the same provider.
final CoreLocalizations te = lookupCoreLocalizations(const Locale('te'));
final CoreLocalizations kn = lookupCoreLocalizations(const Locale('kn'));
final CoreLocalizations en = lookupCoreLocalizations(const Locale('en'));

Future<void> _pastSplash(WidgetTester tester) async {
  await tester.pump(SplashScreen.hold + const Duration(milliseconds: 100));
  await tester.pumpAndSettle();
  expect(find.byType(LanguagePicker), findsOneWidget);
}

void main() {
  testWidgets('A02: choosing Telugu re-localises the login screen live', (
    tester,
  ) async {
    await tester.pumpWidget(const ProviderScope(child: MitraApp()));
    await _pastSplash(tester);
    expect(find.text(en.languagePickerTitle), findsOneWidget);

    await tester.tap(find.text('తెలుగు'));
    await tester.pumpAndSettle();
    // Same screen, same app instance: strings are Telugu already.
    expect(find.text(te.languagePickerTitle), findsOneWidget);
    expect(find.text(en.languagePickerTitle), findsNothing);
    expect(find.text(te.actionContinue), findsOneWidget);

    await tester.tap(find.text(te.actionContinue));
    await tester.pumpAndSettle();
    expect(find.byType(PhoneScreen), findsOneWidget);
    expect(find.text(te.phoneLoginTitle), findsOneWidget);
    expect(find.text(te.phoneSendOtp), findsOneWidget);

    // The Material locale follows, and the theme carries the Indic scale.
    final ctx = tester.element(find.byType(PhoneScreen));
    expect(Localizations.localeOf(ctx), const Locale('te'));
    expect(ctx.app.text.body.height, closeTo(24 * 1.15 / 16, 1e-9));
  });

  testWidgets('MaterialApp lists the five launch locales and delegates', (
    tester,
  ) async {
    await tester.pumpWidget(const ProviderScope(child: MitraApp()));
    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.supportedLocales.map((l) => l.languageCode).toSet(), <String>{
      'en',
      'te',
      'kn',
      'hi',
      'mr',
    });
    expect(app.localizationsDelegates, contains(CoreLocalizations.delegate));
    expect(
      app.localizationsDelegates,
      contains(GlobalMaterialLocalizations.delegate),
    );
    expect(
      app.localizationsDelegates,
      contains(GlobalWidgetsLocalizations.delegate),
    );
    expect(
      app.localizationsDelegates,
      contains(GlobalCupertinoLocalizations.delegate),
    );
  });

  testWidgets('the chosen language is restored on the next app start', (
    tester,
  ) async {
    final db = openInMemoryDatabase();
    addTearDown(db.close);
    final store = KvSettingsStore(db);

    await tester.pumpWidget(
      ProviderScope(
        overrides: await settingsOverrides(store),
        child: const MitraApp(),
      ),
    );
    await _pastSplash(tester);
    await tester.tap(find.text('తెలుగు'));
    await tester.pumpAndSettle();
    expect((await store.load()).locale, const Locale('te'));

    // "Restart": a fresh ProviderScope bootstrapped from the same database.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      ProviderScope(
        overrides: await settingsOverrides(store),
        child: const MitraApp(),
      ),
    );
    await _pastSplash(tester);
    expect(find.text(te.languagePickerTitle), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
    final button = tester.widget<AppButton>(find.byType(AppButton));
    expect(button.onPressed, isNotNull);
  });

  testWidgets('A63 settings changes the language through the same provider', (
    tester,
  ) async {
    final store = InMemorySettingsStore(
      const AppSettings(locale: Locale('en')),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...await settingsOverrides(store),
          routerProvider.overrideWithValue(
            buildRouter(initialLocation: AppRoutes.settings),
          ),
        ],
        child: const MitraApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(en.settingsTitle), findsOneWidget);
    expect(find.text('English'), findsOneWidget);

    await tester.tap(find.byKey(const Key('language-setting')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ಕನ್ನಡ'));
    await tester.pumpAndSettle();

    expect(find.text(kn.settingsTitle), findsOneWidget);
    expect(find.text(kn.settingsLanguage), findsOneWidget);
    expect(find.text('ಕನ್ನಡ'), findsOneWidget);
    expect((await store.load()).locale, const Locale('kn'));

    await tester.tap(find.byKey(const Key('theme-setting')));
    await tester.pumpAndSettle();
    expect(find.text(kn.themeSunlight), findsOneWidget);
    expect((await store.load()).themeMode, AppThemeMode.sunlight);
  });
}

import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:farmerapp_farmer/app.dart';
import 'package:farmerapp_farmer/router.dart';
import 'package:farmerapp_farmer/screens/phone_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// FA-004: language switch without restart, persisted across app starts,
/// and the F70 setting drives the same provider.
final CoreLocalizations hi = lookupCoreLocalizations(const Locale('hi'));
final CoreLocalizations mr = lookupCoreLocalizations(const Locale('mr'));
final CoreLocalizations en = lookupCoreLocalizations(const Locale('en'));

void main() {
  testWidgets('F01: choosing Hindi re-localises the login screen live', (
    tester,
  ) async {
    await tester.pumpWidget(const ProviderScope(child: KisanApp()));
    await tester.pumpAndSettle();
    expect(find.text(en.languagePickerTitle), findsOneWidget);

    await tester.tap(find.text('हिन्दी'));
    await tester.pumpAndSettle();
    expect(find.text(hi.languagePickerTitle), findsOneWidget);
    expect(find.text(en.languagePickerTitle), findsNothing);
    expect(find.text(hi.appNameFarmer), findsOneWidget);

    await tester.tap(find.text(hi.actionContinue));
    await tester.pumpAndSettle();
    expect(find.byType(PhoneScreen), findsOneWidget);
    expect(find.text(hi.phoneLoginTitle), findsOneWidget);
    expect(find.text(hi.phoneSendOtp), findsOneWidget);

    final ctx = tester.element(find.byType(PhoneScreen));
    expect(Localizations.localeOf(ctx), const Locale('hi'));
    expect(ctx.app.text.body.height, closeTo(24 * 1.15 / 16, 1e-9));
    expect(
      ctx.app.text.body.fontFamilyFallback,
      contains('Noto Sans Devanagari'),
    );
  });

  testWidgets('MaterialApp lists the five launch locales and delegates', (
    tester,
  ) async {
    await tester.pumpWidget(const ProviderScope(child: KisanApp()));
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
        child: const KisanApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('हिन्दी'));
    await tester.pumpAndSettle();
    expect((await store.load()).locale, const Locale('hi'));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      ProviderScope(
        overrides: await settingsOverrides(store),
        child: const KisanApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(hi.languagePickerTitle), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
    final button = tester.widget<AppButton>(find.byType(AppButton));
    expect(button.onPressed, isNotNull);
  });

  testWidgets('F70 Me changes the language through the same provider', (
    tester,
  ) async {
    final store = InMemorySettingsStore(
      const AppSettings(locale: Locale('hi')),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...await settingsOverrides(store),
          routerProvider.overrideWithValue(
            buildRouter(initialLocation: AppRoutes.settings),
          ),
        ],
        child: const KisanApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(hi.settingsTitle), findsOneWidget);
    expect(find.text('हिन्दी'), findsOneWidget);

    await tester.tap(find.byKey(const Key('language-setting')));
    await tester.pumpAndSettle();
    // The sheet keeps the speaker buttons (NF-009 audio, playback later).
    expect(find.byIcon(Icons.volume_up_outlined), findsNWidgets(5));
    // In the Hindi UI the Marathi caption is also "मराठी"; tap the title.
    await tester.tap(find.text('मराठी').first);
    await tester.pumpAndSettle();

    expect(find.text(mr.settingsTitle), findsOneWidget);
    expect(find.text(mr.settingsLanguage), findsOneWidget);
    expect(find.text('मराठी'), findsOneWidget);
    expect((await store.load()).locale, const Locale('mr'));
  });
}

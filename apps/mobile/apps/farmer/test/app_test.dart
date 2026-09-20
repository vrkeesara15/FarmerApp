import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:farmerapp_farmer/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = openInMemoryDatabase());
  tearDown(() => db.close());

  // The app arms the FA-007 push listener on start, so even this bare
  // F01 scope needs the encrypted database.
  Widget app() => ProviderScope(
    overrides: <Override>[appDatabaseProvider.overrideWithValue(db)],
    child: const KisanApp(),
  );

  testWidgets('opens on the language picker with audio buttons', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.byType(LanguagePicker), findsOneWidget);
    expect(find.text('తెలుగు'), findsOneWidget);
    // Every tile has a speaker button paired with a label.
    expect(find.byIcon(Icons.volume_up_outlined), findsNWidgets(6));
  });

  testWidgets('continue is disabled until a language is chosen', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    final button = tester.widget<AppButton>(find.byType(AppButton));
    expect(button.onPressed, isNull);

    await tester.tap(find.text('తెలుగు'));
    await tester.pumpAndSettle();
    final enabled = tester.widget<AppButton>(find.byType(AppButton));
    expect(enabled.onPressed, isNotNull);
    // Telugu strings are now active.
    expect(find.text('కొనసాగించు'), findsOneWidget);
  });
}

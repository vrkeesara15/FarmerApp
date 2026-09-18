import 'package:farmerapp_agent/app.dart';
import 'package:farmerapp_agent/screens/splash_screen.dart';
import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('splash leads to the language picker', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: MitraApp()));
    expect(find.byType(SplashScreen), findsOneWidget);

    await tester.pump(SplashScreen.hold + const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
    expect(find.byType(LanguagePicker), findsOneWidget);
    expect(find.text('తెలుగు'), findsOneWidget);
  });

  testWidgets('theme toggle switches to Sunlight', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: MitraApp()));
    await tester.pump(SplashScreen.hold + const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Light'));
    await tester.pumpAndSettle();
    expect(find.text('Sunlight'), findsOneWidget);
    final context = tester.element(find.byType(LanguagePicker));
    expect(Theme.of(context).extension<AppThemeData>()!.isSunlight, isTrue);
  });
}

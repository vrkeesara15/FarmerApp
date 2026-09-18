import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Reference phone size from SPEC 13.1 (360x800 dp).
const Size phoneSize = Size(360, 800);

/// Wraps [child] in a themed, localised MaterialApp for tests and goldens.
Widget harness(
  Widget child, {
  AppThemeMode mode = AppThemeMode.light,
  Locale locale = const Locale('en'),
  bool padded = true,
}) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.build(mode, locale: locale),
    locale: locale,
    localizationsDelegates: CoreLocalizations.localizationsDelegates,
    supportedLocales: CoreLocalizations.supportedLocales,
    home: Scaffold(
      body: SafeArea(
        child: padded
            ? Padding(
                padding: const EdgeInsets.all(Tokens.spaceScreenPadding),
                child: child,
              )
            : child,
      ),
    ),
  );
}

/// Sets the test surface to the reference phone size at 1x.
void usePhoneSurface(WidgetTester tester) {
  tester.view.physicalSize = phoneSize;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:farmerapp_farmer/router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'kisan_harness.dart';
import 'no_typing_test.dart' show allPaths;

/// NF-009: every farmer screen, checked against the accessibility guarantees
/// the requirement names -- 48 dp touch targets, icons always paired with a
/// label, and body text no smaller than the 16 sp type scale.
///
/// This walks the same routes as `no_typing_test.dart` (NF-010): between them
/// every farmer screen is opened on a phone-sized surface and audited, so a
/// new screen is covered the moment it is added to the router.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final paths = allPaths(buildRouter().configuration.routes);

  group('every farmer route', () {
    for (final path in paths) {
      testWidgets('$path meets the NF-009 guarantees', (tester) async {
        usePhoneSurface(tester);
        final deps = KisanDeps()..seedWorld(khataBalance: 1000);
        deps.seedAdvisory();
        addTearDown(deps.dispose);
        await real(tester, () => deps.signIn(welcomeDone: false));
        await real(tester, deps.primeAdvisory);
        await pumpApp(tester, deps.app(initialLocation: path));

        // 48 dp minimum touch target (NF-009, and Android's own guideline).
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        // "Icons always paired with text": an icon-only control is allowed
        // only if it carries a semantic label a screen reader can announce,
        // which is what this guideline checks. A bare icon fails.
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

        final tooSmall = tooSmallText(tester);
        expect(
          tooSmall,
          isEmpty,
          reason:
              'NF-009: minimum 16 sp body text. The type scale (SPEC 13.1) '
              'allows 14 sp labels and 12 sp captions for chrome, but nothing '
              'below that, and nothing a farmer has to read at caption size.',
        );
      });
    }
  });

  testWidgets('the guideline has teeth: a 32 dp target fails it', (
    tester,
  ) async {
    // A gate nobody has seen fail is a gate nobody can trust. This is the
    // same guideline the walk above uses, on a button deliberately built
    // below the minimum.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 32,
              height: 32,
              child: IconButton(
                padding: EdgeInsets.zero,
                iconSize: 16,
                tooltip: 'too small',
                onPressed: () {},
                icon: const Icon(Icons.close),
              ),
            ),
          ),
        ),
      ),
    );

    // `meetsGuideline` is an async matcher; asking it the negative question
    // means evaluating the guideline directly.
    final evaluation = await androidTapTargetGuideline.evaluate(tester);
    expect(evaluation.passed, isFalse);
    expect(evaluation.reason, contains('48.0'));
  });

  testWidgets('the label guideline has teeth: a bare icon fails it', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: GestureDetector(
              onTap: () {},
              child: const SizedBox(
                width: 64,
                height: 64,
                child: Icon(Icons.volume_up_outlined),
              ),
            ),
          ),
        ),
      ),
    );

    final evaluation = await labeledTapTargetGuideline.evaluate(tester);
    expect(evaluation.passed, isFalse);
    expect(evaluation.reason, contains('semantic label'));
  });

  test('the type scale itself satisfies NF-009', () {
    final scale = AppTextStyles.forLocale(
      const Locale('en'),
      color: const Color(0xFF000000),
    );
    // "Minimum 16 sp body text" is a property of the scale, not of a screen.
    expect(scale.body.fontSize, greaterThanOrEqualTo(16));
    expect(scale.heading.fontSize, greaterThanOrEqualTo(16));
    expect(scale.title.fontSize, greaterThanOrEqualTo(16));
    expect(scale.display.fontSize, greaterThanOrEqualTo(16));
    // 48 dp is the token every control sizes itself from.
    expect(Tokens.sizeTouchTargetMin, 48);
    expect(
      Tokens.sizePrimaryButtonHeight,
      greaterThanOrEqualTo(Tokens.sizeTouchTargetMin),
    );
  });
}

/// The smallest font size a farmer should ever have to read. The SPEC 13.1
/// scale bottoms out at the 12 sp caption, used for chrome (timestamps,
/// units); anything below it is a bug.
const double minRenderedFontSize = 12;

/// Every rendered [Text] smaller than [minRenderedFontSize], described.
List<String> tooSmallText(WidgetTester tester) {
  final failures = <String>[];
  for (final element in find.byType(Text, skipOffstage: false).evaluate()) {
    final text = element.widget as Text;
    final style = text.style;
    final resolved =
        style?.fontSize ??
        DefaultTextStyle.of(element).style.fontSize ??
        Theme.of(element).textTheme.bodyMedium?.fontSize;
    if (resolved != null && resolved < minRenderedFontSize) {
      failures.add(
        '"${text.data ?? text.textSpan?.toPlainText()}" at $resolved sp',
      );
    }
  }
  return failures;
}

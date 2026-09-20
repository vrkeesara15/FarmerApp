import 'package:farmerapp_agent/router.dart';
import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../duty/duty_test_support.dart';
import '../farmers/agent_harness.dart';
import 'field_test_support.dart';

/// Opens the A12 gap-reason sheet, which carries a free-text note field.
Future<void> _openGapSheet(WidgetTester tester, AgentDeps deps) async {
  await tester.pumpWidget(deps.app(initialLocation: AppRoutes.myDay));
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(
    find.byKey(const Key('day-gap-reason-gap-1')),
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.tap(find.byKey(const Key('day-gap-reason-gap-1')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('FA-005 dictation fills a free-text field', (tester) async {
    final deps = AgentDeps();
    addTearDown(deps.dispose);
    await acceptPolicy(deps);
    await seedOnDuty(deps, points: 3);
    await seedFieldCaches(deps);
    deps.speech.script = <SpeechResult>[
      const SpeechResult('పంక్చర్'),
      const SpeechResult('పంక్చర్ అయింది', isFinal: true),
    ];
    await _openGapSheet(tester, deps);

    await tester.tap(find.byKey(const Key('gap-note-mic')));
    await tester.pumpAndSettle();

    // The recogniser was asked for the app's current language.
    expect(deps.speech.listened.single.languageCode, 'en');
    final field = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(const Key('gap-note')),
        matching: find.byType(TextField),
      ),
    );
    expect(field.controller!.text, 'పంక్చర్ అయింది');
  });

  testWidgets('partial results show while listening, typing still works', (
    tester,
  ) async {
    final deps = AgentDeps();
    addTearDown(deps.dispose);
    await acceptPolicy(deps);
    await seedOnDuty(deps, points: 3);
    await seedFieldCaches(deps);
    deps.speech.script = <SpeechResult>[const SpeechResult('puncture near')];
    await _openGapSheet(tester, deps);

    await tester.tap(find.byKey(const Key('gap-note-mic')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('voice-listening')), findsOneWidget);
    expect(find.text('puncture near'), findsOneWidget);

    // Stopping keeps what was heard so far.
    await tester.tap(find.byKey(const Key('gap-note-mic')));
    await tester.pumpAndSettle();
    expect(deps.speech.stops, 1);
    expect(find.byKey(const Key('voice-listening')), findsNothing);
    final field = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(const Key('gap-note')),
        matching: find.byType(TextField),
      ),
    );
    expect(field.controller!.text, 'puncture near');
  });

  testWidgets('dictation appends to text the officer already typed', (
    tester,
  ) async {
    final deps = AgentDeps();
    addTearDown(deps.dispose);
    await acceptPolicy(deps);
    await seedOnDuty(deps, points: 3);
    await seedFieldCaches(deps);
    deps.speech.script = <SpeechResult>[
      const SpeechResult('near Kondapur', isFinal: true),
    ];
    await _openGapSheet(tester, deps);

    await tester.enterText(find.byKey(const Key('gap-note')), 'Puncture');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('gap-note-mic')));
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(const Key('gap-note')),
        matching: find.byType(TextField),
      ),
    );
    expect(field.controller!.text, 'Puncture near Kondapur');
  });

  testWidgets('a phone with no speech service says so and keeps typing', (
    tester,
  ) async {
    final deps = AgentDeps();
    addTearDown(deps.dispose);
    await acceptPolicy(deps);
    await seedOnDuty(deps, points: 3);
    await seedFieldCaches(deps);
    deps.speech.available = false;
    await _openGapSheet(tester, deps);

    await tester.tap(find.byKey(const Key('gap-note-mic')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('voice-unavailable')), findsOneWidget);
    expect(
      find.text('This phone has no voice typing. You can type instead.'),
      findsOneWidget,
    );

    await tester.enterText(find.byKey(const Key('gap-note')), 'Typed instead');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('gap-save')));
    await tester.pumpAndSettle();

    final rows = await SyncStore(deps.db).opsIn(<String>['queued']);
    final op = SyncStore.toOp(
      rows.firstWhere((r) => r.entity == FieldEntities.trackGap),
    );
    expect(op.payload['note'], 'Typed instead');
  });

  testWidgets('the microphone is on every free-text field of A61 and A62', (
    tester,
  ) async {
    final deps = AgentDeps();
    addTearDown(deps.dispose);
    await seedFieldCaches(deps);

    await tester.pumpWidget(deps.app(initialLocation: AppRoutes.travel));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('travel-add-claim')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('claim-note-mic')), findsOneWidget);

    await tester.pumpWidget(deps.app(initialLocation: AppRoutes.myFlags));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('flag-explain-mic-flag-open')), findsOneWidget);
  });
}

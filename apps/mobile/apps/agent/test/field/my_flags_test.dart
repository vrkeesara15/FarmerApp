import 'package:farmerapp_agent/router.dart';
import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../farmers/agent_harness.dart';
import 'field_test_support.dart';

void main() {
  testWidgets('A62 shows only the officer own flags', (tester) async {
    final deps = AgentDeps();
    addTearDown(deps.dispose);
    await seedFieldCaches(deps);
    await tester.pumpWidget(deps.app(initialLocation: AppRoutes.myFlags));
    await tester.pumpAndSettle();

    // Both rows come from GET /v1/flags/mine; the screen has no other
    // source of flags, so no other officer's flag can appear.
    expect(find.byKey(const Key('flag-flag-open')), findsOneWidget);
    expect(find.byKey(const Key('flag-flag-resolved')), findsOneWidget);
    expect(find.text('Duty with no activity'), findsOneWidget);
    expect(find.text('My flags'), findsOneWidget);
  });

  testWidgets('an open flag hides the outcome and offers an explanation', (
    tester,
  ) async {
    final deps = AgentDeps();
    addTearDown(deps.dispose);
    await seedFieldCaches(deps);
    await tester.pumpWidget(deps.app(initialLocation: AppRoutes.myFlags));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('flag-outcome-hidden-flag-open')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('flag-outcome-flag-open')), findsNothing);
    expect(
      find.byKey(const Key('flag-explain-field-flag-open')),
      findsOneWidget,
    );

    await tester.enterText(
      find.byKey(const Key('flag-explain-field-flag-open')),
      'I was waiting for the farmer at the bus stop.',
    );
    await tester.tap(find.byKey(const Key('flag-explain-send-flag-open')));
    await tester.pumpAndSettle();

    expect(deps.field.explanations, <(String, String)>[
      ('flag-open', 'I was waiting for the farmer at the bus stop.'),
    ]);
    expect(find.text('Sent to your cluster head.'), findsOneWidget);
  });

  testWidgets('a resolved flag shows its outcome and no explain field', (
    tester,
  ) async {
    final deps = AgentDeps();
    addTearDown(deps.dispose);
    await seedFieldCaches(deps);
    await tester.pumpWidget(deps.app(initialLocation: AppRoutes.myFlags));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const Key('flag-outcome-flag-resolved')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Explained'), findsOneWidget);
    expect(find.text('Bus fare, not vehicle km.'), findsOneWidget);
    expect(
      find.byKey(const Key('flag-explain-field-flag-resolved')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('flag-outcome-hidden-flag-resolved')),
      findsNothing,
    );
  });

  testWidgets('explaining offline says so instead of queueing blind', (
    tester,
  ) async {
    final deps = AgentDeps(online: false);
    addTearDown(deps.dispose);
    await seedFieldCaches(deps);
    deps.field.offline = true;
    await tester.pumpWidget(deps.app(initialLocation: AppRoutes.myFlags));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('flag-explain-field-flag-open')),
      'Vehicle broke down.',
    );
    await tester.tap(find.byKey(const Key('flag-explain-send-flag-open')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('flag-explain-offline')), findsOneWidget);
    expect(deps.field.explanations, isEmpty);
  });

  testWidgets('no flags is a calm empty state', (tester) async {
    final deps = AgentDeps();
    addTearDown(deps.dispose);
    deps.field.flags = const <MyFlag>[];
    await seedFieldCaches(deps, flags: false);
    final c = deps.container();
    addTearDown(c.dispose);
    await c.read(fieldRepositoryProvider).refreshFlags();
    await tester.pumpWidget(deps.app(initialLocation: AppRoutes.myFlags));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('flags-empty')), findsOneWidget);
    expect(
      find.text('You only ever see flags about yourself.'),
      findsOneWidget,
    );
  });
}

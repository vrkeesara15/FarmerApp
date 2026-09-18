import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/harness.dart';

void main() {
  testWidgets('off duty shows Off duty and the location note', (tester) async {
    await tester.pumpWidget(
      harness(DutyToggle(onDuty: false, onChanged: (_) {})),
    );
    expect(find.text('Off duty'), findsOneWidget);
    expect(find.text('Go on duty'), findsOneWidget);
    expect(
      find.text('Location is on only while you are on duty'),
      findsOneWidget,
    );
    expect(find.textContaining('On duty for'), findsNothing);
  });

  testWidgets('on duty shows elapsed time', (tester) async {
    await tester.pumpWidget(
      harness(
        DutyToggle(
          onDuty: true,
          elapsed: const Duration(hours: 2, minutes: 5),
          onChanged: (_) {},
        ),
      ),
    );
    expect(find.text('On duty'), findsOneWidget);
    expect(find.text('On duty for 2:05'), findsOneWidget);
    expect(find.text('Go off duty'), findsOneWidget);
  });

  testWidgets('tapping the switch requests the opposite state', (tester) async {
    bool? requested;
    await tester.pumpWidget(
      harness(DutyToggle(onDuty: false, onChanged: (v) => requested = v)),
    );
    await tester.tap(find.byType(Switch));
    expect(requested, isTrue);

    await tester.pumpWidget(
      harness(DutyToggle(onDuty: true, onChanged: (v) => requested = v)),
    );
    await tester.tap(find.text('On duty'));
    expect(requested, isFalse);
  });

  testWidgets('loading hides the switch and blocks taps', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      harness(
        DutyToggle(onDuty: false, loading: true, onChanged: (_) => calls++),
      ),
    );
    expect(find.byType(Switch), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.tap(find.text('Off duty'));
    expect(calls, 0);
  });

  testWidgets('blocked: reason and "Review policy" link, switch disabled '
      '(FA-011)', (tester) async {
    var reviewed = 0;
    bool? requested;
    await tester.pumpWidget(
      harness(
        DutyToggle(
          onDuty: false,
          onChanged: (v) => requested = v,
          blockedReason: 'Accept the location policy to go on duty',
          blockedActionLabel: 'Review policy',
          onBlockedAction: () => reviewed += 1,
        ),
      ),
    );
    expect(
      find.text('Accept the location policy to go on duty'),
      findsOneWidget,
    );
    await tester.tap(find.byType(Switch));
    await tester.pump();
    expect(requested, isNull);
    final sw = tester.widget<Switch>(find.byType(Switch));
    expect(sw.onChanged, isNull);
    await tester.tap(find.byKey(const Key('duty-blocked-action')));
    await tester.pump();
    expect(reviewed, 1);
  });
}

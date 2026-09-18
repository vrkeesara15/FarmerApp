import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/harness.dart';

/// Finds the visible digit box showing [d] (not the hidden EditableText).
Finder digit(String d) =>
    find.byWidgetPredicate((w) => w is Text && w.data == d);

void main() {
  testWidgets('auto-advances through the six boxes and completes', (
    tester,
  ) async {
    String? completed;
    final changes = <String>[];
    await tester.pumpWidget(
      harness(
        OtpInput(onChanged: changes.add, onCompleted: (v) => completed = v),
      ),
    );
    await tester.pump();

    final field = find.byType(TextField);
    expect(field, findsOneWidget);

    await tester.enterText(field, '1');
    await tester.pump();
    expect(digit('1'), findsOneWidget);
    expect(changes.last, '1');
    expect(completed, isNull);

    await tester.enterText(field, '123');
    await tester.pump();
    expect(digit('3'), findsOneWidget);
    expect(completed, isNull);

    await tester.enterText(field, '123456');
    await tester.pump();
    expect(completed, '123456');
    for (final d in <String>['1', '2', '3', '4', '5', '6']) {
      expect(digit(d), findsOneWidget);
    }
  });

  testWidgets('rejects non-digits and caps at six', (tester) async {
    await tester.pumpWidget(harness(const OtpInput()));
    await tester.pump();
    await tester.enterText(find.byType(TextField), '12ab3456789');
    await tester.pump();
    final ctrl = tester.widget<TextField>(find.byType(TextField)).controller!;
    expect(ctrl.text, '123456');
  });

  testWidgets('resend timer counts down then enables resend', (tester) async {
    var resent = 0;
    await tester.pumpWidget(
      harness(
        OtpInput(
          resendAfter: const Duration(seconds: 3),
          onResend: () => resent++,
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Resend in 3 s'), findsOneWidget);
    expect(find.text('Resend OTP'), findsNothing);

    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Resend in 2 s'), findsOneWidget);

    await tester.pump(const Duration(seconds: 3));
    expect(find.text('Resend OTP'), findsOneWidget);

    await tester.tap(find.text('Resend OTP'));
    await tester.pump();
    expect(resent, 1);
    expect(find.text('Resend in 3 s'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('shows the error text', (tester) async {
    await tester.pumpWidget(
      harness(
        const OtpInput(errorText: 'Incorrect OTP', resendAfter: Duration.zero),
      ),
    );
    await tester.pump();
    expect(find.text('Incorrect OTP'), findsOneWidget);
  });
}

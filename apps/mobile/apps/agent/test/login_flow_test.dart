import 'package:farmerapp_agent/app.dart';
import 'package:farmerapp_agent/router.dart';
import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Phone -> OTP flow (FA-001) against a [FakeAuthApi] that mimics the API.
Widget _app(FakeAuthApi api) => ProviderScope(
  overrides: [
    authApiProvider.overrideWithValue(api),
    routerProvider.overrideWithValue(
      buildRouter(initialLocation: AppRoutes.phone),
    ),
  ],
  child: const MitraApp(),
);

Future<void> _sendOtp(WidgetTester tester) async {
  await tester.enterText(find.byType(TextField).first, '9000000004');
  await tester.tap(find.text('Send OTP'));
  await tester.pumpAndSettle();
  expect(find.byType(OtpInput), findsOneWidget);
}

Future<void> _enterCode(WidgetTester tester, String code) async {
  final field = find.byType(TextField).last;
  await tester.enterText(field, '');
  await tester.pump();
  await tester.enterText(field, code);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('happy path reaches done with 123456', (tester) async {
    await tester.pumpWidget(_app(FakeAuthApi()));
    await tester.pumpAndSettle();
    await _sendOtp(tester);
    expect(find.text('Sent to +91 9000000004'), findsOneWidget);
    await _enterCode(tester, '123456');
    expect(find.text('Done'), findsOneWidget);
    final ctx = tester.element(find.byType(OtpInput));
    final flow = ProviderScope.containerOf(ctx).read(authFlowProvider);
    expect(flow.step, AuthStep.done);
    expect(flow.session, isNotNull);
  });

  testWidgets('five wrong codes show the lockout state', (tester) async {
    await tester.pumpWidget(_app(FakeAuthApi()));
    await tester.pumpAndSettle();
    await _sendOtp(tester);
    for (var i = 0; i < 4; i++) {
      await _enterCode(tester, '00000$i');
      expect(
        find.text('Incorrect OTP. Please try again. ${4 - i} attempts left'),
        findsOneWidget,
      );
    }
    await _enterCode(tester, '000009');
    expect(
      find.text('Too many wrong attempts. Try again in 15 min.'),
      findsOneWidget,
    );
    final otp = tester.widget<OtpInput>(find.byType(OtpInput));
    expect(otp.enabled, isFalse);
  });

  testWidgets('unregistered number and rate limit copy', (tester) async {
    await tester.pumpWidget(_app(FakeAuthApi(rateLimitAfter: 1)));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '1234567890');
    await tester.tap(find.text('Send OTP'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a valid 10-digit mobile number'), findsOneWidget);
    await _sendOtp(tester);
    // Resend timer must elapse before resend is offered.
    await tester.pump(const Duration(seconds: 31));
    await tester.tap(find.text('Resend OTP'));
    await tester.pumpAndSettle();
    expect(
      find.text('Too many codes requested. Try again in 15 min.'),
      findsOneWidget,
    );
  });
}

import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:farmerapp_farmer/router.dart';
import 'package:farmerapp_farmer/screens/consent_screen.dart';
import 'package:farmerapp_farmer/screens/home_screen.dart';
import 'package:farmerapp_farmer/screens/language_screen.dart';
import 'package:farmerapp_farmer/screens/otp_screen.dart';
import 'package:farmerapp_farmer/screens/phone_screen.dart';
import 'package:farmerapp_farmer/screens/welcome_screen.dart';
import 'package:farmerapp_farmer/widgets/kisan_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'kisan_harness.dart';

/// FM-001 / FA-001: phone → OTP against the fake API, and the whole first
/// run (F01 → F02 → F03 → F04 → F05 → F10) made measurable: the number of
/// screens, the user actions and the decisions per screen (≤ 2, SPEC
/// 13.3). The < 60 s on a low-end phone check is a manual human gate
/// (docs/prs/M6-farmer-app.md).

/// Choice groups a farmer has to decide on the current screen: a switch,
/// a language picker, a grid of tiles or a rating each count as one.
int decisionsOnScreen(WidgetTester tester) =>
    <Type>[Switch, LanguagePicker, ChoiceGrid, Rating]
        .map((t) => find.byType(t, skipOffstage: false).evaluate().length)
        .fold(0, (a, n) => a + n);

Future<void> _sendOtp(WidgetTester tester) async {
  await tester.enterText(find.byType(TextField).first, '9000000004');
  await tester.tap(find.text('Send OTP'));
  await settle(tester);
  expect(find.byType(OtpInput), findsOneWidget);
}

Future<void> _enterCode(WidgetTester tester, String code) async {
  final field = find.byType(TextField).last;
  await tester.enterText(field, '');
  await tester.pump();
  await tester.enterText(field, code);
  await settle(tester);
}

void main() {
  late KisanDeps deps;

  setUp(() => deps = KisanDeps());
  tearDown(() => deps.dispose());

  testWidgets('FM-001 first run: 5 screens to home, ≤ 2 decisions each, '
      'no typing but phone and OTP', (tester) async {
    usePhoneSurface(tester);
    deps.seedWorld(dataConsent: false);
    await pumpApp(tester, deps.app(initialLocation: AppRoutes.language));

    final visited = <Type>[];
    final decisions = <Type, int>{};
    var actions = 0;
    var typed = 0;
    void onScreen(Type screen) {
      visited.add(screen);
      decisions[screen] = decisionsOnScreen(tester);
    }

    // F01: pick Telugu (the audio prompt is optional), Continue.
    expect(find.byType(LanguageScreen), findsOneWidget);
    onScreen(LanguageScreen);
    await tapIt(tester, find.text('తెలుగు'));
    await tapIt(tester, find.byType(AppButton));
    actions += 2;

    // F02: phone number (typing allowed), Send OTP.
    expect(find.byType(PhoneScreen), findsOneWidget);
    onScreen(PhoneScreen);
    await tester.enterText(find.byType(TextField).first, '9000000004');
    await tester.tap(find.byType(AppButton));
    await settle(tester);
    actions += 2;
    typed += 1;

    // F03: the six digits; a correct code continues by itself.
    expect(find.byType(OtpScreen), findsOneWidget);
    onScreen(OtpScreen);
    await tester.enterText(find.byType(TextField).last, '123456');
    await pumpUntilFound(tester, find.byType(ConsentScreen));
    actions += 1;
    typed += 1;

    // F04: agree to the required card, leave offers off, Continue.
    expect(find.byType(ConsentScreen), findsOneWidget);
    onScreen(ConsentScreen);
    await tapIt(tester, find.byKey(const Key('consent-data')));
    await tapIt(tester, find.byKey(const Key('consent-continue')));
    actions += 2;

    // F05: the officer's details are right.
    expect(find.byType(WelcomeScreen), findsOneWidget);
    onScreen(WelcomeScreen);
    await tapIt(tester, find.byKey(const Key('welcome-confirm')));
    actions += 1;

    expect(find.byType(HomeScreen), findsOneWidget);
    expect(visited, <Type>[
      LanguageScreen,
      PhoneScreen,
      OtpScreen,
      ConsentScreen,
      WelcomeScreen,
    ]);
    for (final e in decisions.entries) {
      expect(e.value, lessThanOrEqualTo(2), reason: '${e.key} decisions');
    }
    expect(decisions[LanguageScreen], 1);
    expect(decisions[ConsentScreen], 2);
    expect(actions, 8, reason: 'taps + inputs from F01 to home');
    expect(typed, 2, reason: 'phone and OTP only');
    // The consent went to the API in Telugu, data granted, offers refused.
    final consentWrites = deps.kisan.writes
        .where((w) => w.$1.endsWith('/consents'))
        .map((w) => (w.$2['purpose'], w.$2['granted'], w.$2['language']))
        .toList();
    expect(consentWrites, <(Object?, Object?, Object?)>[
      ('data', true, 'te'),
      ('marketing', false, 'te'),
    ]);
  });

  testWidgets('a returning farmer with consent and welcome done goes home', (
    tester,
  ) async {
    usePhoneSurface(tester);
    deps.seedWorld();
    await deps.db.setValue(KisanRepository.welcomeDoneKey, 'true');
    await pumpApp(tester, deps.app(initialLocation: AppRoutes.phone));
    await _sendOtp(tester);
    final field = find.byType(TextField).last;
    await tester.enterText(field, '123456');
    await pumpUntilFound(tester, find.byType(HomeScreen));
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.text('Namaste, Lakshmi'), findsOneWidget);
  });

  testWidgets('five wrong codes show the lockout state', (tester) async {
    deps.seedWorld();
    await pumpApp(tester, deps.app(initialLocation: AppRoutes.phone));
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
    deps.auth = FakeAuthApi(role: 'farmer', rateLimitAfter: 1);
    await pumpApp(tester, deps.app(initialLocation: AppRoutes.phone));
    await tester.enterText(find.byType(TextField).first, '1234567890');
    await tester.tap(find.text('Send OTP'));
    await settle(tester);
    expect(find.text('Enter a valid 10-digit mobile number'), findsOneWidget);
    await _sendOtp(tester);
    // Resend timer must elapse before resend is offered.
    await tester.pump(const Duration(seconds: 31));
    await tester.tap(find.text('Resend OTP'));
    await settle(tester);
    expect(
      find.text('Too many codes requested. Try again in 15 min.'),
      findsOneWidget,
    );
  });
}

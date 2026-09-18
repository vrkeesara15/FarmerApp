import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

ProviderContainer _container(AuthApi api) {
  final container = ProviderContainer(
    overrides: [authApiProvider.overrideWithValue(api)],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  test('happy path: phone -> otp -> done with a session', () async {
    final c = _container(FakeAuthApi());
    final n = c.read(authFlowProvider.notifier);
    await n.requestOtp('9000000004');
    expect(c.read(authFlowProvider).step, AuthStep.otp);
    await n.verifyOtp('123456');
    final s = c.read(authFlowProvider);
    expect(s.step, AuthStep.done);
    expect(s.failure, AuthFailure.none);
    expect(s.session!.user.phone, '+919000000004');
  });

  test('invalid number is rejected locally', () async {
    final c = _container(FakeAuthApi());
    await c.read(authFlowProvider.notifier).requestOtp('12345');
    final s = c.read(authFlowProvider);
    expect(s.failure, AuthFailure.invalidNumber);
    expect(s.phoneError, isTrue);
    expect(s.step, AuthStep.phone);
  });

  test('wrong codes count down then lock', () async {
    final c = _container(FakeAuthApi(maxAttempts: 3));
    final n = c.read(authFlowProvider.notifier);
    await n.requestOtp('9000000004');
    await n.verifyOtp('000000');
    var s = c.read(authFlowProvider);
    expect(s.failure, AuthFailure.wrongCode);
    expect(s.attemptsLeft, 2);
    expect(s.otpError, isTrue);
    await n.verifyOtp('000000');
    await n.verifyOtp('000000');
    s = c.read(authFlowProvider);
    expect(s.failure, AuthFailure.locked);
    expect(s.locked, isTrue);
    expect(s.retryAfterMinutes, 15);
    // Locked: the correct code is not even sent, and resend is refused too.
    await n.verifyOtp('123456');
    expect(c.read(authFlowProvider).step, AuthStep.otp);
    await n.resendOtp();
    expect(c.read(authFlowProvider).failure, AuthFailure.locked);
  });

  test('rate limit on resend keeps the OTP step and reports minutes', () async {
    final c = _container(FakeAuthApi(rateLimitAfter: 2));
    final n = c.read(authFlowProvider.notifier);
    await n.requestOtp('9000000004');
    await n.resendOtp();
    expect(c.read(authFlowProvider).failure, AuthFailure.none);
    await n.resendOtp();
    final s = c.read(authFlowProvider);
    expect(s.failure, AuthFailure.rateLimited);
    expect(s.step, AuthStep.otp);
    expect(s.retryAfterMinutes, 15);
  });

  test('reset returns to the phone step', () async {
    final c = _container(FakeAuthApi());
    final n = c.read(authFlowProvider.notifier);
    await n.requestOtp('9000000004');
    n.reset();
    expect(c.read(authFlowProvider), isA<AuthFlowState>());
    expect(c.read(authFlowProvider).step, AuthStep.phone);
  });
}

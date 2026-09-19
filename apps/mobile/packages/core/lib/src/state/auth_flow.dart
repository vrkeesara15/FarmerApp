import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_api.dart';
import '../auth/token_store.dart';
import '../security/security_providers.dart' show tenantSettingsSyncProvider;

/// Provides the [TokenStore]. Apps override this with [SecureTokenStore].
final Provider<TokenStore> tokenStoreProvider = Provider<TokenStore>(
  (ref) => InMemoryTokenStore(),
);

/// Provides the [AuthApi]. Apps override this with [HttpAuthApi].
final Provider<AuthApi> authApiProvider = Provider<AuthApi>(
  (ref) => FakeAuthApi(latency: const Duration(milliseconds: 300)),
);

/// Where the phone + OTP flow is.
enum AuthStep {
  /// Entering the phone number.
  phone,

  /// OTP sent; entering the code.
  otp,

  /// Verified.
  done,
}

/// Why the last request failed (drives the error copy on A03/A04, F02/F03).
enum AuthFailure {
  /// Nothing wrong.
  none,

  /// Not a valid Indian mobile number.
  invalidNumber,

  /// Too many codes requested; wait.
  rateLimited,

  /// Too many wrong codes; wait.
  locked,

  /// The code did not match.
  wrongCode,

  /// The code timed out.
  expired,

  /// No account for this number.
  notFound,

  /// This phone is not the officer's bound device (SEC-020).
  deviceNotBound,

  /// Could not reach the server.
  network,
}

/// State of the onboarding login flow (A03/A04, F02/F03).
@immutable
class AuthFlowState {
  /// Creates the state.
  const AuthFlowState({
    this.step = AuthStep.phone,
    this.phone = '',
    this.busy = false,
    this.failure = AuthFailure.none,
    this.attemptsLeft,
    this.retryAfter,
    this.session,
  });

  /// Current step.
  final AuthStep step;

  /// 10-digit mobile number without +91.
  final String phone;

  /// A request is in flight.
  final bool busy;

  /// Why the last call failed.
  final AuthFailure failure;

  /// Wrong attempts left before lockout (after a wrong code).
  final int? attemptsLeft;

  /// How long to wait when [failure] is rate limited or locked.
  final Duration? retryAfter;

  /// The signed-in session once [step] is [AuthStep.done].
  final AuthSession? session;

  /// The number was rejected (any failure while on the phone step).
  bool get phoneError => step == AuthStep.phone && failure != AuthFailure.none;

  /// The OTP was rejected (any failure while on the OTP step).
  bool get otpError => step == AuthStep.otp && failure != AuthFailure.none;

  /// The phone is locked out; further codes are pointless until [retryAfter].
  bool get locked => failure == AuthFailure.locked;

  /// Minutes to wait, rounded up (for the lockout / rate-limit copy).
  int get retryAfterMinutes {
    final seconds = retryAfter?.inSeconds ?? 15 * 60;
    return seconds <= 0 ? 1 : (seconds + 59) ~/ 60;
  }

  /// Copy with overrides.
  AuthFlowState copyWith({
    AuthStep? step,
    String? phone,
    bool? busy,
    AuthFailure? failure,
    int? attemptsLeft,
    Duration? retryAfter,
    AuthSession? session,
    bool clearHints = false,
  }) {
    return AuthFlowState(
      step: step ?? this.step,
      phone: phone ?? this.phone,
      busy: busy ?? this.busy,
      failure: failure ?? this.failure,
      attemptsLeft: clearHints ? null : (attemptsLeft ?? this.attemptsLeft),
      retryAfter: clearHints ? null : (retryAfter ?? this.retryAfter),
      session: session ?? this.session,
    );
  }
}

/// Drives the phone + OTP screens against [authApiProvider].
class AuthFlowNotifier extends Notifier<AuthFlowState> {
  static final RegExp _indianMobile = RegExp(r'^[6-9]\d{9}$');

  @override
  AuthFlowState build() => const AuthFlowState();

  /// Validates locally without calling the API.
  static bool isValidPhone(String phone) => _indianMobile.hasMatch(phone);

  /// Requests an OTP for [phone]; moves to [AuthStep.otp] on success.
  Future<void> requestOtp(String phone) async {
    if (!isValidPhone(phone)) {
      state = state.copyWith(
        phone: phone,
        failure: AuthFailure.invalidNumber,
        clearHints: true,
      );
      return;
    }
    state = state.copyWith(
      phone: phone,
      busy: true,
      failure: AuthFailure.none,
      clearHints: true,
    );
    final outcome = await ref.read(authApiProvider).requestOtp(phone);
    final failure = switch (outcome.result) {
      OtpRequestResult.sent => AuthFailure.none,
      OtpRequestResult.invalidNumber => AuthFailure.invalidNumber,
      OtpRequestResult.notFound => AuthFailure.notFound,
      OtpRequestResult.rateLimited => AuthFailure.rateLimited,
      OtpRequestResult.locked => AuthFailure.locked,
      OtpRequestResult.network => AuthFailure.network,
    };
    state = state.copyWith(
      busy: false,
      failure: failure,
      retryAfter: outcome.retryAfter,
      // A resend from the OTP step that fails keeps the user on the OTP step
      // so the message shows next to the code boxes.
      step: failure == AuthFailure.none ? AuthStep.otp : state.step,
    );
  }

  /// Re-sends the OTP for the current phone.
  Future<void> resendOtp() => requestOtp(state.phone);

  /// Verifies [otp]; moves to [AuthStep.done] on success.
  Future<void> verifyOtp(String otp) async {
    if (state.locked) return;
    state = state.copyWith(
      busy: true,
      failure: AuthFailure.none,
      clearHints: true,
    );
    final outcome = await ref.read(authApiProvider).verifyOtp(state.phone, otp);
    final failure = switch (outcome.result) {
      OtpVerifyResult.ok => AuthFailure.none,
      OtpVerifyResult.invalid => AuthFailure.wrongCode,
      OtpVerifyResult.expired => AuthFailure.expired,
      OtpVerifyResult.notFound => AuthFailure.expired,
      OtpVerifyResult.locked => AuthFailure.locked,
      OtpVerifyResult.deviceNotBound => AuthFailure.deviceNotBound,
      OtpVerifyResult.network => AuthFailure.network,
    };
    if (failure == AuthFailure.none) _pullTenantSettings();
    state = state.copyWith(
      busy: false,
      failure: failure,
      attemptsLeft: outcome.attemptsLeft,
      retryAfter: outcome.retryAfter,
      session: outcome.session,
      step: failure == AuthFailure.none ? AuthStep.done : AuthStep.otp,
    );
  }

  /// Tenant settings on login (M2 follow-up): best effort, in the
  /// background; the cached / default values stay when it fails.
  void _pullTenantSettings() {
    try {
      unawaited(
        ref
            .read(tenantSettingsSyncProvider)
            .pull()
            .then<void>((_) {}, onError: (Object _) {}),
      );
    } on Object {
      // No database in this scope (widget tests of the login screens).
    }
  }

  /// Goes back to the phone step.
  void reset() {
    state = const AuthFlowState();
  }
}

/// Auth flow provider.
final NotifierProvider<AuthFlowNotifier, AuthFlowState> authFlowProvider =
    NotifierProvider<AuthFlowNotifier, AuthFlowState>(AuthFlowNotifier.new);

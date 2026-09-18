import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_api.dart';

/// Provides the [AuthApi]. Apps override this with the real client.
final Provider<AuthApi> authApiProvider = Provider<AuthApi>(
  (ref) => const FakeAuthApi(latency: Duration(milliseconds: 300)),
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

/// State of the onboarding login flow (A03/A04, F02/F03).
@immutable
class AuthFlowState {
  /// Creates the state.
  const AuthFlowState({
    this.step = AuthStep.phone,
    this.phone = '',
    this.busy = false,
    this.phoneError = false,
    this.otpError = false,
  });

  /// Current step.
  final AuthStep step;

  /// 10-digit mobile number without +91.
  final String phone;

  /// A request is in flight.
  final bool busy;

  /// The number was rejected.
  final bool phoneError;

  /// The OTP was rejected.
  final bool otpError;

  /// Copy with overrides.
  AuthFlowState copyWith({
    AuthStep? step,
    String? phone,
    bool? busy,
    bool? phoneError,
    bool? otpError,
  }) {
    return AuthFlowState(
      step: step ?? this.step,
      phone: phone ?? this.phone,
      busy: busy ?? this.busy,
      phoneError: phoneError ?? this.phoneError,
      otpError: otpError ?? this.otpError,
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
      state = state.copyWith(phone: phone, phoneError: true);
      return;
    }
    state = state.copyWith(phone: phone, busy: true, phoneError: false);
    final result = await ref.read(authApiProvider).requestOtp(phone);
    state = state.copyWith(
      busy: false,
      phoneError: result != OtpRequestResult.sent,
      step: result == OtpRequestResult.sent ? AuthStep.otp : AuthStep.phone,
    );
  }

  /// Re-sends the OTP for the current phone.
  Future<void> resendOtp() => requestOtp(state.phone);

  /// Verifies [otp]; moves to [AuthStep.done] on success.
  Future<void> verifyOtp(String otp) async {
    state = state.copyWith(busy: true, otpError: false);
    final result = await ref.read(authApiProvider).verifyOtp(state.phone, otp);
    state = state.copyWith(
      busy: false,
      otpError: result != OtpVerifyResult.ok,
      step: result == OtpVerifyResult.ok ? AuthStep.done : AuthStep.otp,
    );
  }

  /// Goes back to the phone step.
  void reset() {
    state = const AuthFlowState();
  }
}

/// Auth flow provider.
final NotifierProvider<AuthFlowNotifier, AuthFlowState> authFlowProvider =
    NotifierProvider<AuthFlowNotifier, AuthFlowState>(AuthFlowNotifier.new);

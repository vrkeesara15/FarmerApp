/// Result of an OTP request.
enum OtpRequestResult {
  /// OTP was sent to the number.
  sent,

  /// The number is not a valid Indian mobile.
  invalidNumber,

  /// Too many requests; try later.
  rateLimited,
}

/// Result of an OTP verification.
enum OtpVerifyResult {
  /// Logged in.
  ok,

  /// Wrong code.
  invalid,

  /// Code timed out; request a new one.
  expired,
}

/// Phone + OTP login API used by the onboarding screens.
///
/// The real implementation lives with the generated API client; the
/// onboarding shells only depend on this interface.
abstract interface class AuthApi {
  /// Requests an OTP for a 10-digit Indian mobile number (without +91).
  Future<OtpRequestResult> requestOtp(String phone);

  /// Verifies the 6-digit [otp] for [phone].
  Future<OtpVerifyResult> verifyOtp(String phone, String otp);
}

/// In-memory [AuthApi] for development and tests. Accepts any valid number
/// and the OTP `123456`.
class FakeAuthApi implements AuthApi {
  /// Creates the fake with an optional artificial [latency].
  const FakeAuthApi({this.latency = Duration.zero});

  /// Delay applied to every call to mimic the network.
  final Duration latency;

  /// The only OTP the fake accepts.
  static const String acceptedOtp = '123456';

  static final RegExp _indianMobile = RegExp(r'^[6-9]\d{9}$');

  @override
  Future<OtpRequestResult> requestOtp(String phone) async {
    await Future<void>.delayed(latency);
    return _indianMobile.hasMatch(phone)
        ? OtpRequestResult.sent
        : OtpRequestResult.invalidNumber;
  }

  @override
  Future<OtpVerifyResult> verifyOtp(String phone, String otp) async {
    await Future<void>.delayed(latency);
    return otp == acceptedOtp ? OtpVerifyResult.ok : OtpVerifyResult.invalid;
  }
}

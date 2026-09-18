/// Result of an OTP request.
enum OtpRequestResult {
  /// OTP was sent to the number.
  sent,

  /// The number is not a valid Indian mobile.
  invalidNumber,

  /// No account for this number (404 `user_not_found`).
  notFound,

  /// Too many codes requested (429 `otp_rate_limited`); try later.
  rateLimited,

  /// Too many wrong attempts (423 `otp_locked`); try later.
  locked,

  /// The request never reached the server.
  network,
}

/// Result of an OTP verification.
enum OtpVerifyResult {
  /// Logged in.
  ok,

  /// Wrong code (401 `otp_invalid`).
  invalid,

  /// Code timed out (401 `otp_expired`); request a new one.
  expired,

  /// No active code (404 `otp_not_found`); request a new one.
  notFound,

  /// Too many wrong attempts (423 `otp_locked`); try later.
  locked,

  /// The request never reached the server.
  network,
}

/// Outcome of [AuthApi.requestOtp] with the server's back-off hints.
class OtpRequestOutcome {
  /// Creates the outcome.
  const OtpRequestOutcome(
    this.result, {
    this.retryAfter,
    this.resendsLeft,
    this.expiresIn,
  });

  /// What happened.
  final OtpRequestResult result;

  /// How long to wait when [result] is rate limited or locked.
  final Duration? retryAfter;

  /// Resends still allowed in the current window.
  final int? resendsLeft;

  /// Validity of the code that was sent.
  final Duration? expiresIn;
}

/// Outcome of [AuthApi.verifyOtp] with the server's hints.
class OtpVerifyOutcome {
  /// Creates the outcome.
  const OtpVerifyOutcome(
    this.result, {
    this.attemptsLeft,
    this.retryAfter,
    this.session,
  });

  /// What happened.
  final OtpVerifyResult result;

  /// Wrong attempts left before lockout (on [OtpVerifyResult.invalid]).
  final int? attemptsLeft;

  /// How long the lockout lasts (on [OtpVerifyResult.locked]).
  final Duration? retryAfter;

  /// The signed-in session (on [OtpVerifyResult.ok]).
  final AuthSession? session;
}

/// The signed-in user as returned by `/v1/me` and the token endpoints.
class AuthUser {
  /// Creates the user.
  const AuthUser({
    required this.id,
    required this.tenantId,
    required this.phone,
    required this.name,
    required this.role,
    required this.language,
    required this.status,
    this.storeId,
    this.clusterId,
  });

  /// Parses the API shape.
  factory AuthUser.fromJson(Map<String, Object?> json) {
    return AuthUser(
      id: json['id']! as String,
      tenantId: json['tenant_id']! as String,
      phone: json['phone']! as String,
      name: json['name']! as String,
      role: json['role']! as String,
      language: (json['language'] as String?) ?? 'en',
      status: (json['status'] as String?) ?? 'active',
      storeId: json['store_id'] as String?,
      clusterId: json['cluster_id'] as String?,
    );
  }

  /// User id (uuid).
  final String id;

  /// Tenant id (uuid).
  final String tenantId;

  /// E.164 phone.
  final String phone;

  /// Display name.
  final String name;

  /// One of the FA-002 roles.
  final String role;

  /// Preferred language code.
  final String language;

  /// `active` or `disabled`.
  final String status;

  /// Store, when the role is store-bound.
  final String? storeId;

  /// Cluster, when the role is cluster-bound.
  final String? clusterId;

  /// Serialises to the API shape.
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'tenant_id': tenantId,
    'phone': phone,
    'name': name,
    'role': role,
    'language': language,
    'status': status,
    'store_id': storeId,
    'cluster_id': clusterId,
  };
}

/// Tokens + profile persisted after login (SEC-020).
class AuthSession {
  /// Creates the session.
  const AuthSession({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
    required this.user,
  });

  /// Parses a token response (`expires_in` seconds relative to [now]).
  factory AuthSession.fromTokenResponse(
    Map<String, Object?> json, {
    DateTime? now,
  }) {
    final base = now ?? DateTime.now().toUtc();
    final expiresIn = (json['expires_in'] as num?)?.toInt() ?? 900;
    return AuthSession(
      accessToken: json['access_token']! as String,
      refreshToken: json['refresh_token']! as String,
      expiresAt: base.add(Duration(seconds: expiresIn)),
      user: AuthUser.fromJson(json['user']! as Map<String, Object?>),
    );
  }

  /// Parses the persisted shape written by [toJson].
  factory AuthSession.fromJson(Map<String, Object?> json) {
    return AuthSession(
      accessToken: json['access_token']! as String,
      refreshToken: json['refresh_token']! as String,
      expiresAt: DateTime.parse(json['expires_at']! as String),
      user: AuthUser.fromJson(json['user']! as Map<String, Object?>),
    );
  }

  /// 15-minute JWT.
  final String accessToken;

  /// Rotating 30-day refresh token.
  final String refreshToken;

  /// When [accessToken] expires (UTC).
  final DateTime expiresAt;

  /// Signed-in user.
  final AuthUser user;

  /// Whether the access token should be refreshed.
  bool isExpired({DateTime? now}) =>
      !(now ?? DateTime.now().toUtc()).isBefore(expiresAt);

  /// Serialises for secure storage.
  Map<String, Object?> toJson() => <String, Object?>{
    'access_token': accessToken,
    'refresh_token': refreshToken,
    'expires_at': expiresAt.toUtc().toIso8601String(),
    'user': user.toJson(),
  };
}

/// Phone + OTP login API used by the onboarding screens.
///
/// [HttpAuthApi] talks to the FarmerApp API; [FakeAuthApi] is in-memory.
abstract interface class AuthApi {
  /// Requests an OTP for a 10-digit Indian mobile number (without +91).
  Future<OtpRequestOutcome> requestOtp(String phone);

  /// Verifies the 6-digit [otp] for [phone].
  Future<OtpVerifyOutcome> verifyOtp(String phone, String otp);
}

/// In-memory [AuthApi] for development and tests. Accepts any valid number
/// and the OTP `123456`; mimics the server's lockout and resend limits.
class FakeAuthApi implements AuthApi {
  /// Creates the fake with an optional artificial [latency].
  FakeAuthApi({
    this.latency = Duration.zero,
    this.maxAttempts = 5,
    this.rateLimitAfter,
    this.lockout = const Duration(minutes: 15),
    this.role = 'field_officer',
    this.storeId,
  });

  /// Role of the signed-in user (store-mode tests use `store_manager`).
  final String role;

  /// Store of the signed-in user.
  final String? storeId;

  /// Delay applied to every call to mimic the network.
  final Duration latency;

  /// Wrong codes tolerated before the phone is locked.
  final int maxAttempts;

  /// Sends allowed before [OtpRequestResult.rateLimited]; `null` = unlimited.
  final int? rateLimitAfter;

  /// Reported lockout duration.
  final Duration lockout;

  /// The only OTP the fake accepts.
  static const String acceptedOtp = '123456';

  static final RegExp _indianMobile = RegExp(r'^[6-9]\d{9}$');

  final Map<String, int> _attempts = <String, int>{};
  final Map<String, int> _sends = <String, int>{};
  final Set<String> _locked = <String>{};

  /// Clears lockouts and counters.
  void reset() {
    _attempts.clear();
    _sends.clear();
    _locked.clear();
  }

  @override
  Future<OtpRequestOutcome> requestOtp(String phone) async {
    await Future<void>.delayed(latency);
    if (!_indianMobile.hasMatch(phone)) {
      return const OtpRequestOutcome(OtpRequestResult.invalidNumber);
    }
    if (_locked.contains(phone)) {
      return OtpRequestOutcome(OtpRequestResult.locked, retryAfter: lockout);
    }
    final sends = (_sends[phone] ?? 0) + 1;
    _sends[phone] = sends;
    final limit = rateLimitAfter;
    if (limit != null && sends > limit) {
      return const OtpRequestOutcome(
        OtpRequestResult.rateLimited,
        retryAfter: Duration(minutes: 15),
      );
    }
    _attempts[phone] = 0;
    return OtpRequestOutcome(
      OtpRequestResult.sent,
      resendsLeft: limit == null ? 3 : limit - sends,
      expiresIn: const Duration(minutes: 5),
    );
  }

  @override
  Future<OtpVerifyOutcome> verifyOtp(String phone, String otp) async {
    await Future<void>.delayed(latency);
    if (_locked.contains(phone)) {
      return OtpVerifyOutcome(OtpVerifyResult.locked, retryAfter: lockout);
    }
    if (otp == acceptedOtp) {
      _attempts.remove(phone);
      return OtpVerifyOutcome(
        OtpVerifyResult.ok,
        session: AuthSession(
          accessToken: 'fake-access',
          refreshToken: 'fake-refresh',
          expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 15)),
          user: AuthUser(
            id: 'u-fake',
            tenantId: 't-fake',
            phone: '+91$phone',
            name: 'Demo user',
            role: role,
            language: 'en',
            status: 'active',
            storeId: storeId,
          ),
        ),
      );
    }
    final attempts = (_attempts[phone] ?? 0) + 1;
    _attempts[phone] = attempts;
    if (attempts >= maxAttempts) {
      _locked.add(phone);
      return OtpVerifyOutcome(OtpVerifyResult.locked, retryAfter: lockout);
    }
    return OtpVerifyOutcome(
      OtpVerifyResult.invalid,
      attemptsLeft: maxAttempts - attempts,
    );
  }
}

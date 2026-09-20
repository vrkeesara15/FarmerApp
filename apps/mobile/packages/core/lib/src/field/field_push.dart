import '../push/push_controller.dart';
import 'field_api.dart';

/// The officer app's side of the shared FA-007 token registry: the token
/// goes to `POST /v1/devices/me/push-token` through [FieldApi].
///
/// A server the phone cannot reach is [PushRegistration.offline], never an
/// error: the officer keeps their session and the A13 inbox keeps filling
/// over sync.
class FieldPushRegistry implements PushTokenRegistry {
  /// Creates the registry over [api].
  const FieldPushRegistry(this.api);

  /// The M7 field endpoints.
  final FieldApi api;

  @override
  Future<PushRegistration> registerPushToken(
    String token, {
    String platform = 'android',
    String? deviceId,
    String? appVersion,
  }) async {
    try {
      await api.registerPushToken(
        token,
        platform: PushPlatform.values.firstWhere(
          (p) => p.name == platform,
          orElse: () => PushPlatform.android,
        ),
        appVersion: appVersion,
      );
    } on FieldUnavailableException {
      return PushRegistration.offline;
    }
    return PushRegistration.done;
  }

  @override
  Future<PushRegistration> clearPushToken(String? token) async {
    if (token == null || token.isEmpty) return PushRegistration.done;
    try {
      await api.removePushToken(token);
    } on FieldUnavailableException {
      // The server disables the token itself once FCM rejects it.
      return PushRegistration.offline;
    }
    return PushRegistration.done;
  }
}

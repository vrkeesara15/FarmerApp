import 'dart:async';

import 'push_service.dart';

/// What came of registering (or withdrawing) a device token.
enum PushRegistration {
  /// The server has the token (or has forgotten it).
  done,

  /// The phone could not reach the server; the next start tries again.
  offline,

  /// Nothing was registered: push is unavailable on this build, or the
  /// user declined the notification permission, or the server refused.
  refused,
}

/// Where a device token is registered and withdrawn — the app's side of
/// `POST /v1/devices/me/push-token` (+ `/remove`).
///
/// Each app implements it over its own API client so that this module
/// depends on neither the officer's nor the farmer's data layer.
abstract interface class PushTokenRegistry {
  /// Registers [token] after login and on every FCM rotation.
  Future<PushRegistration> registerPushToken(
    String token, {
    String platform,
    String? deviceId,
    String? appVersion,
  });

  /// Withdraws the token (logout, SEC-025 wipe). [token] is the one the
  /// controller knows; an implementation that remembers its own may use
  /// that instead.
  Future<PushRegistration> clearPushToken(String? token);
}

/// Registers nothing: the default until an app wires its own registry.
class NoPushTokenRegistry implements PushTokenRegistry {
  /// Creates the registry.
  const NoPushTokenRegistry();

  @override
  Future<PushRegistration> registerPushToken(
    String token, {
    String platform = 'android',
    String? deviceId,
    String? appVersion,
  }) async => PushRegistration.refused;

  @override
  Future<PushRegistration> clearPushToken(String? token) async =>
      PushRegistration.done;
}

/// FA-007 glue, shared by both apps: registers this device's push token
/// after login, keeps it registered when FCM rotates it, hands arriving
/// data messages to the app (which files them in its inbox), follows a
/// tapped push to its screen, and withdraws the token on logout or a
/// remote wipe.
///
/// Nothing here knows about FCM: the transport is the [PushService] seam
/// and the endpoint is the [PushTokenRegistry] seam.
class PushController {
  /// Creates the controller.
  PushController({
    required this.service,
    required this.registry,
    this.platform = 'android',
    this.deviceId,
    this.appVersion,
    this.onMessage,
    this.onRoute,
  });

  /// The device's transport.
  final PushService service;

  /// Where the token is registered.
  final PushTokenRegistry registry;

  /// `android` | `ios` | `web`.
  final String platform;

  /// This device's id (defaults to the access token's device server-side).
  final String? deviceId;

  /// App version reported with the token.
  final String? appVersion;

  /// Called for every message that arrives while the app runs, and for the
  /// one the app was opened from. The app files it in its inbox and
  /// decides whether to navigate.
  final Future<void> Function(PushMessage message)? onMessage;

  /// Called with the deep link when a push is tapped (and for the push
  /// that cold-started the app).
  final void Function(String route)? onRoute;

  /// True once [signedIn] registered a token in this session.
  bool get registered => _registered;
  bool _registered = false;

  /// The token registered by the last [signedIn].
  String? get registeredToken => _token;
  String? _token;

  final List<StreamSubscription<Object>> _subs = <StreamSubscription<Object>>[];
  bool _initialHandled = false;
  PushMessage? _initial;

  /// After login (FA-007): starts listening, asks for permission and
  /// registers the token. A registration that cannot reach the server is
  /// not an error — the user keeps their session and the inbox still
  /// fills over sync.
  Future<PushRegistration> signedIn() async {
    await listen();
    if (!await service.isAvailable()) return PushRegistration.refused;
    final permission = await service.requestPermission();
    if (permission != PushPermission.granted) return PushRegistration.refused;
    final token = await service.token();
    if (token == null || token.isEmpty) return PushRegistration.refused;
    final result = await registry.registerPushToken(
      token,
      platform: platform,
      deviceId: deviceId,
      appVersion: appVersion,
    );
    if (result == PushRegistration.done) {
      _registered = true;
      _token = token;
    }
    return result;
  }

  /// Starts handling arriving messages, taps and token rotations, and
  /// follows the push the app was opened from. The app calls this on
  /// start, so a push that lands before (or without) a registration still
  /// reaches the inbox and the deep link.
  Future<void> listen() async {
    if (_subs.isEmpty) {
      _subs
        ..add(
          service.tokenRefreshes.listen((token) {
            unawaited(
              registry
                  .registerPushToken(
                    token,
                    platform: platform,
                    deviceId: deviceId,
                    appVersion: appVersion,
                  )
                  .then<void>((_) {})
                  .catchError((Object _) {}),
            );
          }),
        )
        ..add(
          service.messages.listen((message) {
            unawaited(_guard(() => handle(message)));
          }),
        )
        ..add(
          service.opened.listen((message) {
            unawaited(_guard(() async => onRoute?.call(message.route)));
          }),
        );
    }
    await openingMessage();
  }

  /// Hands [message] to the app (which files it in its inbox).
  Future<void> handle(PushMessage message) async {
    await onMessage?.call(message);
  }

  /// The message the app was cold-started from: filed once, then followed
  /// to its screen. Safe to call more than once.
  Future<PushMessage?> openingMessage() async {
    if (_initialHandled) return _initial;
    _initialHandled = true;
    final message = await service.initialMessage();
    _initial = message;
    if (message == null) return null;
    await handle(message);
    onRoute?.call(message.route);
    return message;
  }

  /// On logout or a remote wipe: withdraws the token from the server and
  /// forgets it on the device. Best effort — the server disables a token
  /// itself once FCM reports it unregistered.
  Future<PushRegistration> signedOut() async {
    _registered = false;
    final token = _token ?? await service.token();
    _token = null;
    final result = await registry.clearPushToken(token);
    await service.deleteToken();
    return result;
  }

  /// Stops listening.
  Future<void> dispose() async {
    for (final sub in _subs) {
      await sub.cancel();
    }
    _subs.clear();
  }

  Future<void> _guard(Future<void> Function() body) async {
    try {
      await body();
    } on Object {
      // A push that cannot be handled must never crash the app.
    }
  }
}

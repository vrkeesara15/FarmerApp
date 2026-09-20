import 'dart:async';

import '../kisan/kisan_models.dart' show KisanWrite;
import 'advisory_models.dart';
import 'advisory_repository.dart';
import 'push_service.dart';

/// FA-007 glue: registers this device's push token after login, keeps it
/// registered when FCM rotates it, files arriving data messages in the
/// inbox and hands the deep link to the app, and withdraws the token on
/// logout or a remote wipe.
///
/// Nothing here knows about FCM: the transport is the [PushService] seam.
class PushController {
  /// Creates the controller.
  PushController({
    required this.service,
    required this.repository,
    this.platform = 'android',
    this.deviceId,
    this.appVersion,
    this.onMessage,
  });

  /// The device's transport.
  final PushService service;

  /// Where notifications are stored and the token registered.
  final AdvisoryRepository repository;

  /// `android` | `ios` | `web`.
  final String platform;

  /// This device's id (defaults to the access token's device server-side).
  final String? deviceId;

  /// App version reported with the token.
  final String? appVersion;

  /// Called for every message that arrives while the app runs, after it
  /// was filed in the inbox. The app decides whether to navigate.
  final void Function(AppNotification notification)? onMessage;

  StreamSubscription<String>? _tokenSub;
  StreamSubscription<PushMessage>? _messageSub;

  /// True once [signedIn] registered a token in this session.
  bool get registered => _registered;
  bool _registered = false;

  /// After login (FA-007): asks for permission, registers the token and
  /// starts listening for rotations and messages. Returns the write
  /// outcome of the registration (`offline` when the phone has no
  /// network: the next start or reconnect registers again).
  Future<KisanWrite> signedIn() async {
    await listen();
    final permission = await service.requestPermission();
    if (permission != PushPermission.granted) return KisanWrite.refused;
    final token = await service.token();
    if (token == null) return KisanWrite.refused;
    final result = await repository.registerPushToken(
      token,
      platform: platform,
      deviceId: deviceId,
      appVersion: appVersion,
    );
    _registered = result == KisanWrite.done;
    return result;
  }

  /// Starts handling arriving messages and token rotations. The app
  /// calls this on start so a push that lands before (or without) a
  /// registration still reaches the inbox and the deep link.
  Future<void> listen() async {
    _tokenSub ??= service.tokenRefreshes.listen((token) {
      unawaited(
        repository
            .registerPushToken(
              token,
              platform: platform,
              deviceId: deviceId,
              appVersion: appVersion,
            )
            .then<void>((_) {})
            .catchError((Object _) {}),
      );
    });
    _messageSub ??= service.messages.listen((message) {
      unawaited(
        Future<void>(() async {
          try {
            await handle(message);
          } on Object {
            // A push that cannot be filed must never crash the app.
          }
        }),
      );
    });
  }

  /// Files [message] in the inbox and tells the app about it.
  Future<AppNotification> handle(PushMessage message) async {
    final row = await repository.receivePush(message);
    onMessage?.call(row);
    return row;
  }

  /// The message the app was cold-started from, filed in the inbox.
  Future<AppNotification?> openingMessage() async {
    final message = await service.initialMessage();
    if (message == null) return null;
    return repository.receivePush(message);
  }

  /// On logout or a remote wipe: withdraws the token from the server and
  /// forgets it on the device.
  Future<KisanWrite> signedOut() async {
    _registered = false;
    final result = await repository.clearPushToken();
    await service.deleteToken();
    return result;
  }

  /// Stops listening.
  Future<void> dispose() async {
    await _tokenSub?.cancel();
    await _messageSub?.cancel();
    _tokenSub = null;
    _messageSub = null;
  }
}

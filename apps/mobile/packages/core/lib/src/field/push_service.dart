import 'dart:async';

import 'package:flutter/foundation.dart' show immutable;

import 'field_api.dart';

/// One FCM **data** message (FA-007). The server never sends display text:
/// the payload carries the i18n keys and the ids, and the app renders them.
@immutable
class PushMessage {
  /// Creates the message.
  const PushMessage(this.data);

  /// Builds one from a plugin's `Map<String, dynamic>` data payload.
  factory PushMessage.fromData(Map<Object?, Object?> data) =>
      PushMessage(<String, String>{
        for (final e in data.entries)
          if (e.key != null) '${e.key}': '${e.value}',
      });

  /// Every value as a string (FCM data messages are string-only).
  final Map<String, String> data;

  /// Inbox row this push mirrors.
  String? get notificationId => data['notification_id'];

  /// Notification kind (`visit_confirm_request`, `beat_plan_ready`, ...).
  String? get kind => data['kind'];

  /// In-app deep link; `/inbox` for anything the app does not route.
  String get route {
    final r = data['route'];
    return r == null || r.isEmpty ? inboxRoute : r;
  }

  /// Where an unrouted push lands.
  static const String inboxRoute = '/inbox';

  @override
  bool operator ==(Object other) =>
      other is PushMessage &&
      other.notificationId == notificationId &&
      other.route == route;

  @override
  int get hashCode => Object.hash(notificationId, route);
}

/// Firebase Cloud Messaging as the app uses it (FA-007).
///
/// The interface exists so that the app builds and runs **without** a
/// Firebase project: when `google-services.json` is absent, or
/// `Firebase.initializeApp()` fails, the app installs
/// [NoopPushService] and everything else (the in-app inbox, the sync feed)
/// keeps working — push is an accelerator, never the only delivery path.
abstract interface class PushService {
  /// Whether this build can actually talk to FCM.
  Future<bool> isAvailable();

  /// Asks for the notification permission and returns the device token,
  /// or null when push is unavailable or the user declined.
  Future<String?> token();

  /// Data messages that arrive while the app is in the foreground.
  Stream<PushMessage> get messages;

  /// Pushes the user tapped (app in the background, or resumed).
  Stream<PushMessage> get opened;

  /// The push that cold-started the app, if any.
  Future<PushMessage?> initialMessage();

  /// Drops the device token (logout, SEC-025 wipe).
  Future<void> delete();
}

/// The build has no Firebase configuration: every call is inert.
class NoopPushService implements PushService {
  /// Creates the service.
  const NoopPushService();

  @override
  Future<bool> isAvailable() async => false;

  @override
  Future<String?> token() async => null;

  @override
  Stream<PushMessage> get messages => const Stream<PushMessage>.empty();

  @override
  Stream<PushMessage> get opened => const Stream<PushMessage>.empty();

  @override
  Future<PushMessage?> initialMessage() async => null;

  @override
  Future<void> delete() async {}
}

/// Scriptable [PushService] for tests, goldens and previews.
class FakePushService implements PushService {
  /// Creates the fake.
  FakePushService({this.available = true, this.deviceToken = 'fcm-token-1'});

  /// What [isAvailable] answers.
  bool available;

  /// What [token] answers (null mimics a declined permission).
  String? deviceToken;

  /// The push that cold-started the app.
  PushMessage? initial;

  /// Tokens deleted through [delete].
  int deletes = 0;

  final StreamController<PushMessage> _messages =
      StreamController<PushMessage>.broadcast();
  final StreamController<PushMessage> _opened =
      StreamController<PushMessage>.broadcast();

  /// Delivers a foreground data message.
  void deliver(Map<String, String> data) => _messages.add(PushMessage(data));

  /// Delivers a tap on a background notification.
  void open(Map<String, String> data) => _opened.add(PushMessage(data));

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<String?> token() async => available ? deviceToken : null;

  @override
  Stream<PushMessage> get messages => _messages.stream;

  @override
  Stream<PushMessage> get opened => _opened.stream;

  @override
  Future<PushMessage?> initialMessage() async => initial;

  @override
  Future<void> delete() async {
    deletes += 1;
    deviceToken = null;
  }

  /// Closes the controllers.
  Future<void> dispose() async {
    await _messages.close();
    await _opened.close();
  }
}

/// Registers the device token after login, keeps the inbox fresh when a
/// data message lands, opens the deep link on a tap, and clears the token
/// on logout and on a remote wipe (FA-007).
class PushRegistrar {
  /// Creates the registrar.
  PushRegistrar({
    required this.push,
    required this.api,
    this.appVersion,
    this.onMessage,
    this.onRoute,
  });

  /// The FCM adapter (or [NoopPushService]).
  final PushService push;

  /// Where the token is registered.
  final FieldApi api;

  /// App version sent with the registration.
  final String? appVersion;

  /// Called for every foreground data message (refresh the inbox).
  final Future<void> Function(PushMessage message)? onMessage;

  /// Called with the deep link when the officer taps a push.
  final void Function(String route)? onRoute;

  /// The token registered by the last [registerAfterLogin].
  String? get registeredToken => _token;
  String? _token;

  final List<StreamSubscription<PushMessage>> _subs =
      <StreamSubscription<PushMessage>>[];

  /// Registers the device token with `POST /v1/devices/me/push-token`.
  /// Returns null (and does nothing) when push is unavailable or the
  /// server could not be reached — the inbox still fills over sync.
  Future<String?> registerAfterLogin() async {
    if (!await push.isAvailable()) return null;
    final token = await push.token();
    if (token == null || token.isEmpty) return null;
    try {
      await api.registerPushToken(token, appVersion: appVersion);
    } on FieldUnavailableException {
      return null;
    }
    return _token = token;
  }

  /// Starts listening for foreground messages and taps. Also routes the
  /// push that cold-started the app.
  Future<void> listen() async {
    _subs
      ..add(
        push.messages.listen((m) {
          unawaited(onMessage?.call(m) ?? Future<void>.value());
        }),
      )
      ..add(push.opened.listen((m) => onRoute?.call(m.route)));
    final initial = await push.initialMessage();
    if (initial != null) onRoute?.call(initial.route);
  }

  /// Tells the server to forget the token and drops it on the device
  /// (logout, SEC-025 wipe). Safe to call when nothing was registered.
  Future<void> clear() async {
    final token = _token ?? await push.token();
    if (token != null && token.isNotEmpty) {
      try {
        await api.removePushToken(token);
      } on FieldUnavailableException {
        // The server disables the token itself once FCM rejects it.
      }
    }
    _token = null;
    await push.delete();
  }

  /// Stops listening.
  Future<void> dispose() async {
    for (final sub in _subs) {
      await sub.cancel();
    }
    _subs.clear();
  }
}

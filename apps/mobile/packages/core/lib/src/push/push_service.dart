/// FA-007 push seam, shared by both apps.
///
/// The transport (FCM) lives in the app, behind this interface: the core
/// never depends on Firebase, so the workspace, the tests and a build
/// without `google-services.json` stay free of it. The adapters are
/// `apps/agent/lib/push.dart` and `apps/farmer/lib/push.dart`; each app
/// keeps its own deep-link map and nothing else.
///
/// The server sends **data** messages only: every value is a string, the
/// text comes from the app's own i18n keys (`title_key` / `body_key`) and
/// `route` carries the deep link (docs/prs/M7-field-p1-api.md).
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show immutable;

/// One FCM data message (every value is a string on the wire).
@immutable
class PushMessage {
  /// Creates the message.
  const PushMessage({
    this.kind = '',
    this.notificationId,
    this.titleKey,
    this.bodyKey,
    String? route,
    this.data = const <String, String>{},
  }) : route = (route == null || route == '') ? inboxRoute : route;

  /// Parses an FCM data payload (`kind`, `route`, `notification_id`,
  /// `title_key`, `body_key` plus the row's ids).
  factory PushMessage.fromData(Map<Object?, Object?> data) {
    final flat = <String, String>{
      for (final e in data.entries)
        if (e.key != null && e.value != null) '${e.key}': '${e.value}',
    };
    return PushMessage(
      kind: flat['kind'] ?? '',
      notificationId: flat['notification_id'],
      titleKey: flat['title_key'],
      bodyKey: flat['body_key'],
      route: flat['route'],
      data: flat,
    );
  }

  /// Notification kind (`visit_confirm_request`, `beat_plan_ready`, ...).
  final String kind;

  /// The `notification` row behind the push, when there is one.
  final String? notificationId;

  /// i18n key of the title.
  final String? titleKey;

  /// i18n key of the body.
  final String? bodyKey;

  /// In-app deep link; [inboxRoute] for anything the server did not route,
  /// so a kind this app version does not know still lands somewhere.
  final String route;

  /// The whole payload.
  final Map<String, String> data;

  /// Where an unrouted push lands.
  static const String inboxRoute = '/inbox';

  /// The route exactly as the server sent it (null when it sent none).
  String? get sentRoute => data['route'];

  /// A payload value.
  String? operator [](String key) => data[key];

  @override
  bool operator ==(Object other) =>
      other is PushMessage &&
      other.kind == kind &&
      other.notificationId == notificationId &&
      other.route == route;

  @override
  int get hashCode => Object.hash(kind, notificationId, route);
}

/// Whether the user allowed notifications on this device.
enum PushPermission {
  /// Allowed.
  granted,

  /// Refused (the inbox still works; nothing is pushed).
  denied,

  /// Not asked yet.
  notDetermined,
}

/// The device's push transport (FA-007).
///
/// The interface exists so that both apps build and run **without** a
/// Firebase project: when `google-services.json` is absent, or
/// `Firebase.initializeApp()` fails, the app installs [NoPushService] and
/// everything else (the in-app inbox, the sync feed) keeps working — push
/// is an accelerator, never the only delivery path.
abstract interface class PushService {
  /// Whether this build can actually talk to FCM.
  Future<bool> isAvailable();

  /// Asks for the notification permission (Android 13+ / iOS) and answers
  /// the resulting state.
  Future<PushPermission> requestPermission();

  /// This device's token, or null when there is none (no Play services,
  /// permission refused, transport off).
  Future<String?> token();

  /// Tokens after a refresh (FCM rotates them).
  Stream<String> get tokenRefreshes;

  /// Data messages that arrive while the app is running.
  Stream<PushMessage> get messages;

  /// Pushes the user tapped (app in the background, or resumed).
  Stream<PushMessage> get opened;

  /// The push that cold-started the app, if any.
  Future<PushMessage?> initialMessage();

  /// Forgets this device's token (logout, SEC-025 wipe).
  Future<void> deleteToken();
}

/// A push transport that is not there: no token, no messages. Used when
/// the build has no Firebase configuration (`google-services.json` is a
/// human gate) so the rest of FA-007 — the inbox, the badge, the deep
/// links — still works.
class NoPushService implements PushService {
  /// Creates the service.
  const NoPushService();

  @override
  Future<bool> isAvailable() async => false;

  @override
  Future<PushPermission> requestPermission() async => PushPermission.denied;

  @override
  Future<String?> token() async => null;

  @override
  Stream<String> get tokenRefreshes => const Stream<String>.empty();

  @override
  Stream<PushMessage> get messages => const Stream<PushMessage>.empty();

  @override
  Stream<PushMessage> get opened => const Stream<PushMessage>.empty();

  @override
  Future<PushMessage?> initialMessage() async => null;

  @override
  Future<void> deleteToken() async {}
}

/// Scriptable [PushService] for tests, goldens and previews.
class FakePushService implements PushService {
  /// Creates the fake.
  FakePushService({
    this.available = true,
    this.deviceToken = 'fcm-token-1',
    this.permission = PushPermission.granted,
    this.initial,
  });

  /// What [isAvailable] answers.
  bool available;

  /// What [requestPermission] answers.
  PushPermission permission;

  /// The push that cold-started the app.
  PushMessage? initial;

  /// Permission prompts shown.
  int permissionAsks = 0;

  /// [deleteToken] calls.
  int deletes = 0;

  /// The token the service hands out (null mimics a declined permission).
  String? deviceToken;

  final StreamController<String> _tokens = StreamController<String>.broadcast();
  final StreamController<PushMessage> _messages =
      StreamController<PushMessage>.broadcast();
  final StreamController<PushMessage> _opened =
      StreamController<PushMessage>.broadcast();

  /// Pushes a new token to listeners (FCM rotation).
  void rotate(String token) {
    deviceToken = token;
    _tokens.add(token);
  }

  /// Delivers [message] as if it arrived from FCM.
  void deliver(PushMessage message) => _messages.add(message);

  /// Delivers a foreground data message.
  void deliverData(Map<String, String> data) =>
      _messages.add(PushMessage.fromData(data));

  /// Delivers a tap on a background notification.
  void open(PushMessage message) => _opened.add(message);

  /// Delivers a tap on a background notification from its data payload.
  void openData(Map<String, String> data) =>
      _opened.add(PushMessage.fromData(data));

  /// Sets the message the app is opened from (cold start).
  void openedFrom(PushMessage? message) => initial = message;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<PushPermission> requestPermission() async {
    permissionAsks += 1;
    return available ? permission : PushPermission.denied;
  }

  @override
  Future<String?> token() async =>
      available && permission == PushPermission.granted ? deviceToken : null;

  @override
  Stream<String> get tokenRefreshes => _tokens.stream;

  @override
  Stream<PushMessage> get messages => _messages.stream;

  @override
  Stream<PushMessage> get opened => _opened.stream;

  @override
  Future<PushMessage?> initialMessage() async => initial;

  @override
  Future<void> deleteToken() async {
    deletes += 1;
    deviceToken = null;
  }

  /// Closes the controllers.
  Future<void> dispose() async {
    await _tokens.close();
    await _messages.close();
    await _opened.close();
  }
}

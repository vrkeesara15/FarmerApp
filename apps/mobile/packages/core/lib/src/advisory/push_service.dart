/// FA-007 push seam.
///
/// The transport (FCM) lives in the app, behind this interface: the core
/// never depends on Firebase, so tests and the workspace build stay free
/// of it. The farmer app's adapter is
/// `apps/farmer/lib/push.dart` (`FirebasePushService`).
///
/// NOTE for the parent loop: the officer app (M7 field half) needs the
/// same seam. If it landed one under `packages/core/lib/src/field/`, the
/// two should be reconciled into a single `PushService` — this file was
/// written in a separate worktree that could not see it
/// (docs/prs/M7-farmer-mobile.md "Duplication to reconcile").
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One FCM data message (every value is a string on the wire).
@immutable
class PushMessage {
  /// Creates the message.
  const PushMessage({
    required this.kind,
    this.notificationId,
    this.titleKey,
    this.bodyKey,
    this.route,
    this.data = const <String, String>{},
  });

  /// Parses an FCM data payload (`kind`, `route`, `notification_id`,
  /// `title_key`, `body_key` plus the row's ids).
  factory PushMessage.fromData(Map<String, Object?> data) {
    final flat = <String, String>{
      for (final e in data.entries)
        if (e.value != null) e.key: '${e.value}',
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

  /// Notification kind (see `NotificationKinds`).
  final String kind;

  /// The `notification` row behind the push, when there is one.
  final String? notificationId;

  /// i18n key of the title.
  final String? titleKey;

  /// i18n key of the body.
  final String? bodyKey;

  /// Route the server suggests (FA-007 deep link).
  final String? route;

  /// The whole payload.
  final Map<String, String> data;

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

/// Whether the farmer allowed notifications on this device.
enum PushPermission {
  /// Allowed.
  granted,

  /// Refused (the inbox still works; nothing is pushed).
  denied,

  /// Not asked yet.
  notDetermined,
}

/// The device's push transport.
abstract interface class PushService {
  /// Asks the farmer for permission (Android 13+ / iOS) and answers the
  /// resulting state.
  Future<PushPermission> requestPermission();

  /// This device's token, or null when there is none (no Play services,
  /// permission refused, transport off).
  Future<String?> token();

  /// Tokens after a refresh (FCM rotates them).
  Stream<String> get tokenRefreshes;

  /// Data messages while the app is running (foreground and background
  /// taps alike).
  Stream<PushMessage> get messages;

  /// The message the app was opened from, if any (cold start).
  Future<PushMessage?> initialMessage();

  /// Forgets this device's token (logout, remote wipe).
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
  Future<PushPermission> requestPermission() async => PushPermission.denied;

  @override
  Future<String?> token() async => null;

  @override
  Stream<String> get tokenRefreshes => const Stream<String>.empty();

  @override
  Stream<PushMessage> get messages => const Stream<PushMessage>.empty();

  @override
  Future<PushMessage?> initialMessage() async => null;

  @override
  Future<void> deleteToken() async {}
}

/// Scriptable transport for tests and previews.
class FakePushService implements PushService {
  /// Creates the fake.
  FakePushService({
    String? token = 'fcm-token-1',
    this.permission = PushPermission.granted,
    PushMessage? initial,
  }) {
    _token = token;
    _initial = initial;
  }

  String? _token;
  PushMessage? _initial;
  final _tokens = StreamController<String>.broadcast();
  final _messages = StreamController<PushMessage>.broadcast();

  /// What [requestPermission] answers.
  PushPermission permission;

  /// Permission prompts shown.
  int permissionAsks = 0;

  /// [deleteToken] calls.
  int deletes = 0;

  /// Sets the token the service hands out (null = none).
  set currentToken(String? value) => _token = value;

  /// Pushes a new token to listeners (FCM rotation).
  void rotate(String token) {
    _token = token;
    _tokens.add(token);
  }

  /// Delivers [message] as if it arrived from FCM.
  void deliver(PushMessage message) => _messages.add(message);

  /// Sets the message the app is opened from (cold start).
  void openedFrom(PushMessage? message) => _initial = message;

  @override
  Future<PushPermission> requestPermission() async {
    permissionAsks += 1;
    return permission;
  }

  @override
  Future<String?> token() async =>
      permission == PushPermission.granted ? _token : null;

  @override
  Stream<String> get tokenRefreshes => _tokens.stream;

  @override
  Stream<PushMessage> get messages => _messages.stream;

  @override
  Future<PushMessage?> initialMessage() async => _initial;

  @override
  Future<void> deleteToken() async {
    deletes += 1;
    _token = null;
  }

  /// Closes the streams.
  Future<void> dispose() async {
    await _tokens.close();
    await _messages.close();
  }
}

/// The device's push transport; the apps override it.
final Provider<PushService> pushServiceProvider = Provider<PushService>(
  (ref) => const NoPushService(),
);

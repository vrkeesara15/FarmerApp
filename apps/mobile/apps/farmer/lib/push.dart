import 'dart:async';

import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show debugPrint;

/// FA-007 transport for the farmer app: FCM behind the core's
/// [PushService] seam. Nothing above this file knows about Firebase.
///
/// The server sends **data** messages only (docs/prs/M7-field-p1-api.md):
/// every value is a string, the text comes from the app's own i18n keys
/// (`title_key` / `body_key`) and `route` carries the deep link.
class FirebasePushService implements PushService {
  /// Creates the service over an initialised Firebase app.
  FirebasePushService(this._messaging) {
    _subs
      ..add(FirebaseMessaging.onMessage.listen(_forward))
      ..add(FirebaseMessaging.onMessageOpenedApp.listen(_forwardOpened));
  }

  /// Initialises Firebase and returns the service, or [NoPushService]
  /// when this build has no Firebase configuration
  /// (`android/app/google-services.json` is a human gate) or the device
  /// has no Play services. Push is optional: the inbox, the badge and the
  /// deep links work without it.
  static Future<PushService> create() async {
    try {
      await Firebase.initializeApp();
      return FirebasePushService(FirebaseMessaging.instance);
    } on Object catch (e) {
      debugPrint('push: FCM unavailable ($e); the inbox still works');
      return const NoPushService();
    }
  }

  final FirebaseMessaging _messaging;
  final List<StreamSubscription<RemoteMessage>> _subs =
      <StreamSubscription<RemoteMessage>>[];
  final StreamController<PushMessage> _messages =
      StreamController<PushMessage>.broadcast();
  final StreamController<PushMessage> _opened =
      StreamController<PushMessage>.broadcast();

  void _forward(RemoteMessage message) =>
      _messages.add(PushMessage.fromData(message.data));

  void _forwardOpened(RemoteMessage message) {
    final push = PushMessage.fromData(message.data);
    // The farmer app files and follows a tap through [messages]; [opened]
    // is there for the shared seam and stays in sync.
    _messages.add(push);
    _opened.add(push);
  }

  @override
  Future<bool> isAvailable() async => Firebase.apps.isNotEmpty;

  @override
  Stream<PushMessage> get opened => _opened.stream;

  @override
  Future<PushPermission> requestPermission() async {
    final settings = await _messaging.requestPermission();
    return switch (settings.authorizationStatus) {
      AuthorizationStatus.authorized ||
      AuthorizationStatus.provisional => PushPermission.granted,
      AuthorizationStatus.denied => PushPermission.denied,
      _ => PushPermission.notDetermined,
    };
  }

  @override
  Future<String?> token() => _messaging.getToken();

  @override
  Stream<String> get tokenRefreshes => _messaging.onTokenRefresh;

  @override
  Stream<PushMessage> get messages => _messages.stream;

  @override
  Future<PushMessage?> initialMessage() async {
    final message = await _messaging.getInitialMessage();
    return message == null ? null : PushMessage.fromData(message.data);
  }

  @override
  Future<void> deleteToken() => _messaging.deleteToken();

  /// Stops listening (app teardown, remote wipe).
  Future<void> dispose() async {
    for (final sub in _subs) {
      await sub.cancel();
    }
    _subs.clear();
    await _messages.close();
    await _opened.close();
  }
}

import 'dart:async';

import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

/// Firebase Cloud Messaging adapter for the officer app (FA-007).
///
/// **Builds without Firebase.** `firebase_core` compiles on Android with no
/// `google-services.json`; what fails is `Firebase.initializeApp()` at
/// runtime. [FirebasePushService.create] catches that and returns
/// [NoopPushService] instead, so a developer build, CI and the reference
/// device all run with push simply switched off — the in-app inbox (A13)
/// and the sync feed still deliver every notification.
///
/// To turn push on: add `android/app/google-services.json` from the
/// Firebase project, apply the `com.google.gms.google-services` Gradle
/// plugin, and set `PUSH_PROVIDER=fcm` on the API (docs/prs/
/// M7-field-p1-api.md, "Human gates").
class FirebasePushService implements PushService {
  FirebasePushService._(this._messaging);

  /// Initialises Firebase and returns the adapter, or [NoopPushService]
  /// when this build has no Firebase configuration.
  static Future<PushService> create() async {
    try {
      if (Firebase.apps.isEmpty) await Firebase.initializeApp();
      return FirebasePushService._(FirebaseMessaging.instance);
    } on Object {
      // No google-services.json, or the plugin is missing on this platform.
      return const NoopPushService();
    }
  }

  final FirebaseMessaging _messaging;

  @override
  Future<bool> isAvailable() async => Firebase.apps.isNotEmpty;

  @override
  Future<String?> token() async {
    final settings = await _messaging.requestPermission();
    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      return null;
    }
    try {
      return await _messaging.getToken();
    } on Object {
      return null;
    }
  }

  @override
  Stream<PushMessage> get messages =>
      FirebaseMessaging.onMessage.map((m) => PushMessage.fromData(m.data));

  @override
  Stream<PushMessage> get opened => FirebaseMessaging.onMessageOpenedApp.map(
    (m) => PushMessage.fromData(m.data),
  );

  @override
  Future<PushMessage?> initialMessage() async {
    final message = await _messaging.getInitialMessage();
    return message == null ? null : PushMessage.fromData(message.data);
  }

  @override
  Future<void> delete() async {
    try {
      await _messaging.deleteToken();
    } on Object {
      // Nothing to delete (push was never on).
    }
  }
}

/// Background / terminated data messages. FCM data-only messages need a
/// background handler registered before `runApp`; the row is already in the
/// server's inbox, so this only has to not crash — the app reads the inbox
/// from sync on its next start.
@pragma('vm:entry-point')
Future<void> mitraBackgroundMessageHandler(RemoteMessage message) async {
  // Deliberately empty: A13 reads the `notification` sync entity.
}

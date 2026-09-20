import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'push_controller.dart';
import 'push_service.dart';

/// The device's push transport (FA-007). Each app overrides it with its
/// own FCM adapter and leaves [NoPushService] in place when Firebase is
/// not configured.
final Provider<PushService> pushServiceProvider = Provider<PushService>(
  (ref) => const NoPushService(),
);

/// Where the device token is registered. Overridden per app:
/// `fieldPushOverrides` (officer) or `advisoryPushOverrides` (farmer).
final Provider<PushTokenRegistry> pushTokenRegistryProvider =
    Provider<PushTokenRegistry>((ref) => const NoPushTokenRegistry());

/// What the app does with an arriving data message (file it in its inbox,
/// refresh, navigate). Overridden per app.
final Provider<Future<void> Function(PushMessage)?> pushMessageHandlerProvider =
    Provider<Future<void> Function(PushMessage)?>((ref) => null);

/// What the app does with a tapped push's deep link. Overridden per app
/// (the officer app hands it to its router; the farmer app navigates from
/// the message handler instead).
final Provider<void Function(String)?> pushRouteHandlerProvider =
    Provider<void Function(String)?>((ref) => null);

/// `android` | `ios` | `web`, reported with the token.
final Provider<String> pushPlatformProvider = Provider<String>(
  (ref) => 'android',
);

/// The device id reported with the push token (the app overrides it).
final Provider<String?> pushDeviceIdProvider = Provider<String?>((ref) => null);

/// The app version reported with the push token (the app overrides it).
final Provider<String?> pushAppVersionProvider = Provider<String?>(
  (ref) => null,
);

/// The one FA-007 controller both apps use: token registration, message
/// handling, deep links, logout.
final Provider<PushController> pushControllerProvider =
    Provider<PushController>((ref) {
      final controller = PushController(
        service: ref.watch(pushServiceProvider),
        registry: ref.watch(pushTokenRegistryProvider),
        platform: ref.watch(pushPlatformProvider),
        deviceId: ref.watch(pushDeviceIdProvider),
        appVersion: ref.watch(pushAppVersionProvider),
        onMessage: ref.watch(pushMessageHandlerProvider),
        onRoute: ref.watch(pushRouteHandlerProvider),
      );
      ref.onDispose(() => unawaited(controller.dispose()));
      return controller;
    });

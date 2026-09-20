import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show StreamProviderFamily;

import '../db/open_database.dart';
import '../kisan/kisan_models.dart' show Cached;
import '../kisan/kisan_providers.dart' show kisanFlushProvider;
import '../sync/sync_providers.dart';
import 'advisory_api.dart';
import 'advisory_models.dart';
import 'advisory_repository.dart';
import 'push_controller.dart';
import 'push_service.dart';

/// The advisory REST calls; the app overrides it with [HttpAdvisoryApi].
final Provider<AdvisoryApi> advisoryApiProvider = Provider<AdvisoryApi>(
  (ref) => FakeAdvisoryApi(),
);

/// Crop calendar, weather, alerts and the notification inbox.
final Provider<AdvisoryRepository> advisoryRepositoryProvider =
    Provider<AdvisoryRepository>((ref) {
      final flush = ref.watch(kisanFlushProvider);
      return AdvisoryRepository(
        db: ref.watch(appDatabaseProvider),
        api: ref.watch(advisoryApiProvider),
        outbox: ref.watch(outboxProvider),
        clock: ref.watch(clockProvider),
        ids: ref.watch(idGeneratorProvider),
        onQueued: () => unawaited(flush().catchError((Object _) {})),
      );
    });

/// FM-007 crop calendar (cached), live.
final StreamProvider<Cached<CropCalendar>?> cropCalendarProvider =
    StreamProvider<Cached<CropCalendar>?>(
      (ref) => ref.watch(advisoryRepositoryProvider).watchCalendar(),
    );

/// F42 "what changed" note of one crop plot, live.
final StreamProviderFamily<CalendarChange?, String> calendarChangeProvider =
    StreamProvider.family<CalendarChange?, String>(
      (ref, cropPlotId) =>
          ref.watch(advisoryRepositoryProvider).watchCalendarChange(cropPlotId),
    );

/// FM-008 forecast of one farm (cached), live.
final StreamProviderFamily<Cached<FarmWeather>?, String> farmWeatherProvider =
    StreamProvider.family<Cached<FarmWeather>?, String>(
      (ref, farmId) =>
          ref.watch(advisoryRepositoryProvider).watchWeather(farmId),
    );

/// FM-009 district alerts (cached, dismissed ones removed), live.
final StreamProvider<Cached<List<OutbreakAlert>>?> outbreakAlertsProvider =
    StreamProvider<Cached<List<OutbreakAlert>>?>(
      (ref) => ref.watch(advisoryRepositoryProvider).watchAlerts(),
    );

/// FA-007 notification inbox, newest first, live.
final StreamProvider<List<AppNotification>> inboxProvider =
    StreamProvider<List<AppNotification>>(
      (ref) => ref.watch(advisoryRepositoryProvider).watchInbox(),
    );

/// FA-007 unread badge count, live.
final StreamProvider<int> inboxUnreadProvider = StreamProvider<int>(
  (ref) => ref.watch(advisoryRepositoryProvider).watchUnreadCount(),
);

/// The device id reported with the push token (the app overrides it).
final Provider<String?> pushDeviceIdProvider = Provider<String?>((ref) => null);

/// The app version reported with the push token (the app overrides it).
final Provider<String?> pushAppVersionProvider = Provider<String?>(
  (ref) => null,
);

/// Opened when a push arrives or is tapped: the app listens and navigates
/// to the notification's deep link.
final Provider<StreamController<AppNotification>> pushOpenControllerProvider =
    Provider<StreamController<AppNotification>>((ref) {
      final controller = StreamController<AppNotification>.broadcast();
      ref.onDispose(controller.close);
      return controller;
    });

/// FA-007 controller: token registration, message handling, logout.
final Provider<PushController> pushControllerProvider =
    Provider<PushController>((ref) {
      final opens = ref.watch(pushOpenControllerProvider);
      final controller = PushController(
        service: ref.watch(pushServiceProvider),
        repository: ref.watch(advisoryRepositoryProvider),
        deviceId: ref.watch(pushDeviceIdProvider),
        appVersion: ref.watch(pushAppVersionProvider),
        onMessage: (notification) {
          if (!opens.isClosed) opens.add(notification);
        },
      );
      ref.onDispose(() => unawaited(controller.dispose()));
      return controller;
    });

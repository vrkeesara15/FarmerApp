import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show StreamProviderFamily, Override;

import '../db/open_database.dart';
import '../kisan/kisan_models.dart' show Cached;
import '../kisan/kisan_providers.dart' show kisanFlushProvider;
import '../push/push_providers.dart';
import '../sync/sync_providers.dart';
import 'advisory_api.dart';
import 'advisory_models.dart';
import 'advisory_repository.dart';

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
final StreamProvider<List<AppNotification>> advisoryInboxProvider =
    StreamProvider<List<AppNotification>>(
      (ref) => ref.watch(advisoryRepositoryProvider).watchInbox(),
    );

/// FA-007 unread badge count, live.
final StreamProvider<int> inboxUnreadProvider = StreamProvider<int>(
  (ref) => ref.watch(advisoryRepositoryProvider).watchUnreadCount(),
);

/// Opened when a push arrives or is tapped: the app listens and navigates
/// to the notification's deep link.
final Provider<StreamController<AppNotification>> pushOpenControllerProvider =
    Provider<StreamController<AppNotification>>((ref) {
      final controller = StreamController<AppNotification>.broadcast();
      ref.onDispose(controller.close);
      return controller;
    });

/// Wires the farmer app onto the shared FA-007 push seam (`src/push/`):
/// the token is registered through [AdvisoryRepository] (which is the
/// [PushTokenRegistry]) and an arriving data message is filed in the inbox
/// and offered to the app on [pushOpenControllerProvider], which navigates
/// to its deep link. `apps/farmer/lib/main.dart` and the test harness
/// spread these into their container.
final List<Override> advisoryPushOverrides = <Override>[
  pushTokenRegistryProvider.overrideWith(
    (ref) => ref.watch(advisoryRepositoryProvider),
  ),
  pushMessageHandlerProvider.overrideWith((ref) {
    final opens = ref.watch(pushOpenControllerProvider);
    return (message) async {
      final row = await ref
          .read(advisoryRepositoryProvider)
          .receivePush(message);
      if (!opens.isClosed) opens.add(row);
    };
  }),
];

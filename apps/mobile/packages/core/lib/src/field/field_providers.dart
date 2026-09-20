import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart'
    show StreamProviderFamily, FutureProviderFamily;

import '../db/open_database.dart';
import '../duty/duty_providers.dart' show appVersionProvider, istDayBounds;
import '../sync/sync_providers.dart';
import '../utils/format.dart';
import 'field_api.dart';
import 'field_models.dart';
import 'field_repository.dart';
import 'push_service.dart';
import 'speech_service.dart';

/// `YYYY-MM-DD` of the IST day containing [nowUtc].
String istDateKey(DateTime nowUtc) {
  final ist = nowUtc.toUtc().add(istOffset);
  final m = ist.month.toString().padLeft(2, '0');
  final d = ist.day.toString().padLeft(2, '0');
  return '${ist.year}-$m-$d';
}

/// `YYYY-MM` of the IST month containing [nowUtc].
String istMonthKey(DateTime nowUtc) => istDateKey(nowUtc).substring(0, 7);

/// First and last IST day of the month containing [nowUtc], as
/// `(YYYY-MM-01, YYYY-MM-DD)` — the A60 period.
(String, String) istMonthBounds(DateTime nowUtc) {
  final key = istDateKey(nowUtc);
  return ('${key.substring(0, 7)}-01', key);
}

/// The M7 field endpoints; the agent app overrides it with [HttpFieldApi].
final Provider<FieldApi> fieldApiProvider = Provider<FieldApi>(
  (ref) => FakeFieldApi(),
);

/// FCM adapter; the agent app overrides it with its Firebase service, and
/// leaves [NoopPushService] in place when Firebase is not configured.
final Provider<PushService> pushServiceProvider = Provider<PushService>(
  (ref) => const NoopPushService(),
);

/// Android speech-to-text (FA-005); the agent app overrides it with the
/// `speech_to_text` adapter. The default refuses politely.
final Provider<SpeechService> speechServiceProvider = Provider<SpeechService>(
  (ref) => const NoSpeechService(),
);

/// Reads and writes behind A11, A12, A13, A35, A36, A60, A61 and A62.
final Provider<FieldRepository> fieldRepositoryProvider =
    Provider<FieldRepository>(
      (ref) => FieldRepository(
        db: ref.watch(appDatabaseProvider),
        api: ref.watch(fieldApiProvider),
        outbox: ref.watch(outboxProvider),
        clock: ref.watch(clockProvider),
        ids: ref.watch(idGeneratorProvider),
      ),
    );

/// Registers the push token after login and clears it on logout / wipe.
final Provider<PushRegistrar> pushRegistrarProvider = Provider<PushRegistrar>((
  ref,
) {
  final registrar = PushRegistrar(
    push: ref.watch(pushServiceProvider),
    api: ref.watch(fieldApiProvider),
    appVersion: ref.watch(appVersionProvider),
    onMessage: (_) => ref.read(fieldRepositoryProvider).refreshInbox(),
  );
  ref.onDispose(registrar.dispose);
  return registrar;
});

// --- A13 inbox --------------------------------------------------------------

/// The inbox, live.
final StreamProvider<Inbox> inboxProvider = StreamProvider<Inbox>(
  (ref) => ref.watch(fieldRepositoryProvider).watchInbox(),
);

/// Unread count for the bottom-nav badge.
final Provider<int> unreadCountProvider = Provider<int>(
  (ref) => ref.watch(inboxProvider).value?.unread ?? 0,
);

// --- A11 beat plan ----------------------------------------------------------

/// Today's IST date, recomputed from [clockProvider].
final Provider<String> todayIstProvider = Provider<String>(
  (ref) => istDateKey(ref.watch(clockProvider)()),
);

/// The beat plan for a date, live.
final StreamProviderFamily<BeatPlan?, String> beatPlanProvider =
    StreamProvider.family<BeatPlan?, String>(
      (ref, date) => ref.watch(fieldRepositoryProvider).watchBeat(date),
    );

// --- A12 my day -------------------------------------------------------------

/// The server day timeline for a date (cached), live.
final StreamProviderFamily<CachedView<DayTimeline>, String>
dayTimelineProvider = StreamProvider.family<CachedView<DayTimeline>, String>(
  (ref, date) => ref.watch(fieldRepositoryProvider).watchDay(date),
);

/// IST day bounds of "now" as UTC instants (A12, A60 trend).
final Provider<(DateTime, DateTime)> todayBoundsProvider =
    Provider<(DateTime, DateTime)>(
      (ref) => istDayBounds(ref.watch(clockProvider)()),
    );

// --- A60 performance --------------------------------------------------------

/// This month's performance (cached), live.
final StreamProvider<CachedView<Performance>> performanceProvider =
    StreamProvider<CachedView<Performance>>((ref) {
      final (from, to) = istMonthBounds(ref.watch(clockProvider)());
      return ref
          .watch(fieldRepositoryProvider)
          .watchPerformance(from: from, to: to);
    });

// --- A61 travel allowance ---------------------------------------------------

/// The travel statement of a month (cached), live.
final StreamProviderFamily<CachedView<TravelStatement>, String>
travelStatementProvider =
    StreamProvider.family<CachedView<TravelStatement>, String>(
      (ref, month) => ref.watch(fieldRepositoryProvider).watchTravel(month),
    );

// --- A62 my flags -----------------------------------------------------------

/// The officer's own flags (cached), live.
final StreamProvider<CachedView<List<MyFlag>>> myFlagsProvider =
    StreamProvider<CachedView<List<MyFlag>>>(
      (ref) => ref.watch(fieldRepositoryProvider).watchFlags(),
    );

// --- A35 meetings -----------------------------------------------------------

/// Meetings held by this officer, live.
final StreamProvider<List<Meeting>> meetingsProvider =
    StreamProvider<List<Meeting>>(
      (ref) => ref.watch(fieldRepositoryProvider).watchMeetings(),
    );

/// One meeting, live.
final StreamProviderFamily<Meeting?, String> meetingProvider =
    StreamProvider.family<Meeting?, String>(
      (ref, id) => ref.watch(fieldRepositoryProvider).watchMeeting(id),
    );

// --- A36 demo plots ---------------------------------------------------------

/// Demo plots of this officer, live.
final StreamProvider<List<DemoPlot>> demoPlotsProvider =
    StreamProvider<List<DemoPlot>>(
      (ref) => ref.watch(fieldRepositoryProvider).watchDemoPlots(),
    );

/// One demo plot, live.
final StreamProviderFamily<DemoPlot?, String> demoPlotProvider =
    StreamProvider.family<DemoPlot?, String>(
      (ref, id) => ref.watch(fieldRepositoryProvider).watchDemoPlot(id),
    );

/// Pulls every M7 officer view the screens read from cache. Called on app
/// start and whenever the network returns.
final FutureProviderFamily<void, String> fieldRefreshProvider =
    FutureProvider.family<void, String>((ref, date) async {
      final repo = ref.watch(fieldRepositoryProvider);
      await repo.refreshInbox();
      await repo.refreshBeat(date);
      await repo.refreshDay(date);
    });

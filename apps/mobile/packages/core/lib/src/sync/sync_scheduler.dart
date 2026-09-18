import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:workmanager/workmanager.dart';

import 'sync_engine.dart';

/// Reports whether the device has a network path (NF-002 OfflineBanner,
/// immediate sync on reconnect).
abstract interface class ConnectivityMonitor {
  /// Emits on every change; true = online.
  Stream<bool> get onlineChanges;

  /// Current state.
  Future<bool> isOnline();
}

/// Scriptable monitor for tests and previews.
class FakeConnectivityMonitor implements ConnectivityMonitor {
  /// Creates the monitor, online by default.
  FakeConnectivityMonitor({this._online = true});

  final StreamController<bool> _controller = StreamController<bool>.broadcast();
  bool _online;

  /// Current state; setting it emits when it changes.
  bool get online => _online;

  set online(bool value) {
    if (value == _online) return;
    _online = value;
    _controller.add(value);
  }

  @override
  Stream<bool> get onlineChanges => _controller.stream;

  @override
  Future<bool> isOnline() async => _online;

  /// Closes the stream.
  Future<void> dispose() => _controller.close();
}

/// [ConnectivityMonitor] over `connectivity_plus`.
class PlusConnectivityMonitor implements ConnectivityMonitor {
  /// Creates the monitor.
  PlusConnectivityMonitor({Connectivity? connectivity})
    : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;

  static bool _isOnline(List<ConnectivityResult> results) =>
      results.any((r) => r != ConnectivityResult.none);

  @override
  Stream<bool> get onlineChanges =>
      _connectivity.onConnectivityChanged.map(_isOnline).distinct();

  @override
  Future<bool> isOnline() async =>
      _isOnline(await _connectivity.checkConnectivity());
}

/// Registers OS-level background sync work.
abstract interface class BackgroundWorkScheduler {
  /// Periodic sync (15 min, network required); idempotent.
  Future<void> registerPeriodicSync();

  /// One-off sync as soon as the network allows (replaces a pending one).
  Future<void> requestOneOffSync();
}

/// Records registrations for tests.
class FakeBackgroundWorkScheduler implements BackgroundWorkScheduler {
  /// Periodic registrations so far.
  int periodicRegistrations = 0;

  /// One-off requests so far.
  int oneOffRequests = 0;

  @override
  Future<void> registerPeriodicSync() async => periodicRegistrations += 1;

  @override
  Future<void> requestOneOffSync() async => oneOffRequests += 1;
}

/// Task name the periodic WorkManager job carries.
const String syncPeriodicTaskName = 'in.farmerapp.sync.periodic';

/// Task name the one-off WorkManager job carries.
const String syncOneOffTaskName = 'in.farmerapp.sync.now';

/// [BackgroundWorkScheduler] over `workmanager`. The app's
/// `callbackDispatcher` must call [SyncScheduler.runBackgroundTask].
class WorkmanagerSyncScheduler implements BackgroundWorkScheduler {
  /// Creates the scheduler.
  WorkmanagerSyncScheduler({
    Workmanager? workmanager,
    this.frequency = const Duration(minutes: 15),
  }) : _workmanager = workmanager ?? Workmanager();

  final Workmanager _workmanager;

  /// Periodic interval (Android minimum is 15 minutes).
  final Duration frequency;

  @override
  Future<void> registerPeriodicSync() => _workmanager.registerPeriodicTask(
    syncPeriodicTaskName,
    syncPeriodicTaskName,
    frequency: frequency,
    constraints: Constraints(networkType: NetworkType.connected),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
    backoffPolicy: BackoffPolicy.exponential,
    backoffPolicyDelay: const Duration(seconds: 30),
  );

  @override
  Future<void> requestOneOffSync() => _workmanager.registerOneOffTask(
    syncOneOffTaskName,
    syncOneOffTaskName,
    constraints: Constraints(networkType: NetworkType.connected),
    existingWorkPolicy: ExistingWorkPolicy.replace,
    backoffPolicy: BackoffPolicy.exponential,
    backoffPolicyDelay: const Duration(seconds: 30),
  );
}

/// Wires the engine to connectivity and background work: periodic sync
/// every 15 minutes when the network is up, and an immediate sync (plus a
/// one-off background job) the moment connectivity comes back.
class SyncScheduler {
  /// Creates the scheduler.
  SyncScheduler({
    required this.engine,
    required this.connectivity,
    required this.background,
  });

  /// The engine to run.
  final SyncEngine engine;

  /// Network state.
  final ConnectivityMonitor connectivity;

  /// OS background work.
  final BackgroundWorkScheduler background;

  StreamSubscription<bool>? _subscription;
  bool _online = false;
  int _triggered = 0;

  /// Syncs this scheduler started.
  int get syncsTriggered => _triggered;

  /// Last known connectivity.
  bool get isOnline => _online;

  /// Registers background work, starts listening and syncs once if online.
  Future<void> start() async {
    await background.registerPeriodicSync();
    _online = await connectivity.isOnline();
    _subscription = connectivity.onlineChanges.listen(_onChange);
    if (_online) _trigger(force: false);
  }

  void _onChange(bool online) {
    final regained = online && !_online;
    _online = online;
    if (regained) {
      _trigger(force: true);
      unawaited(background.requestOneOffSync());
    }
  }

  void _trigger({required bool force}) {
    _triggered += 1;
    unawaited(engine.syncNow(force: force));
  }

  /// Stops listening.
  Future<void> dispose() async => _subscription?.cancel();

  /// Runs one background task; call from the app's
  /// `Workmanager().executeTask` callback with a builder that opens the
  /// database and constructs the engine in the background isolate.
  static Future<bool> runBackgroundTask(
    String taskName,
    Future<SyncEngine> Function() buildEngine,
  ) async {
    if (taskName != syncPeriodicTaskName && taskName != syncOneOffTaskName) {
      return true;
    }
    final engine = await buildEngine();
    try {
      final report = await engine.syncNow(force: false);
      return report.error == null;
    } finally {
      await engine.dispose();
    }
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint, immutable;
import 'package:path_provider/path_provider.dart';

import '../auth/token_store.dart';
import '../catalog/rest_json_client.dart';
import '../db/app_database.dart';
import '../db/encrypted_database.dart';
import '../duty/duty_platform.dart';
import '../duty/location_sampler.dart';
import '../state/settings.dart';
import 'api_http_client.dart';

/// SEC-025 remote wipe: when the server orders it (a 401
/// `device_wipe_required`, or `wipe_required` from
/// `GET /v1/devices/me/status` on start) the app stops the duty service,
/// deletes the encrypted database and its key, the session tokens, cached
/// photos and uploads, and every `kv` setting except the language, then
/// shows A08 "Signed out by your administrator".

/// `kv` key of the A08 notice written into the fresh database after a wipe
/// (JSON `{at, reason}`); A08 shows while it exists.
const String wipeNoticeKey = 'security.wipe_notice';

/// `kv` keys that survive a wipe (the language, so A08 and the next
/// sign-in are in the user's language).
const List<String> wipeKeepKeys = <String>[KvSettingsStore.localeKey];

/// One named, independent part of the wipe.
@immutable
class WipeStep {
  /// Creates the step.
  const WipeStep(this.name, this.run);

  /// Log / report name.
  final String name;

  /// Does the work.
  final Future<void> Function() run;
}

/// What the wipe did.
@immutable
class WipeReport {
  /// Creates the report.
  const WipeReport({required this.completed, required this.failures});

  /// Steps that finished.
  final List<String> completed;

  /// Steps that threw, with the error.
  final Map<String, Object> failures;

  /// Every step finished.
  bool get ok => failures.isEmpty;
}

/// Runs every [steps] entry in order; a failing step is logged and the
/// rest still run (a wipe must remove as much as it can).
class RemoteWipe {
  /// Creates the wipe.
  RemoteWipe(this.steps, {void Function(String message)? log})
    : _log = log ?? debugPrint;

  /// The steps, in order.
  final List<WipeStep> steps;

  final void Function(String message) _log;

  /// Runs the steps.
  Future<WipeReport> run() async {
    final completed = <String>[];
    final failures = <String, Object>{};
    for (final step in steps) {
      try {
        await step.run();
        completed.add(step.name);
      } on Object catch (e) {
        failures[step.name] = e;
        _log('SEC-025: wipe step ${step.name} failed: $e');
      }
    }
    _log(
      'SEC-025: wipe done (${completed.length} steps, ${failures.length} '
      'failed)',
    );
    return WipeReport(completed: completed, failures: failures);
  }
}

/// Runs the wipe once when [signal] fires (SEC-025): [teardown] (show a
/// neutral screen, dispose the provider container so nothing touches the
/// database), the [steps] for the reason, then [restart] (start the app
/// again; the fresh database carries the A08 notice).
class RemoteWipeCoordinator {
  /// Creates the coordinator; call [arm] once.
  RemoteWipeCoordinator({
    required this.signal,
    required this.steps,
    required this.teardown,
    required this.restart,
    void Function(String message)? log,
  }) : _log = log ?? debugPrint;

  /// The wipe order.
  final WipeSignal signal;

  /// The wipe steps for a reason.
  final List<WipeStep> Function(String reason) steps;

  /// Stops the UI and background work of the current run.
  final Future<void> Function() teardown;

  /// Starts a new app run.
  final Future<void> Function() restart;

  final void Function(String message) _log;
  final Completer<WipeReport> _done = Completer<WipeReport>();

  /// Completes with the report once the wipe ran and the app restarted.
  Future<WipeReport> get done => _done.future;

  /// Starts listening.
  void arm() {
    unawaited(signal.onWipe.then(_run));
  }

  Future<void> _run(String reason) async {
    _log('SEC-025: remote wipe ordered ($reason)');
    try {
      await teardown();
    } on Object catch (e) {
      _log('SEC-025: teardown failed: $e');
    }
    final report = await RemoteWipe(steps(reason), log: _log).run();
    await restart();
    _done.complete(report);
  }
}

/// Stops the duty foreground service and the location sampler.
WipeStep stopDutyStep({
  ForegroundDutyService? service,
  LocationSampler? sampler,
}) => WipeStep('duty', () async {
  if (sampler != null && sampler.isRunning) await sampler.stop();
  if (service != null) await service.stop();
});

/// Closes [db], deletes its files and key ([opener]), then opens a fresh
/// database to put back [keep] `kv` values and the [wipeNoticeKey] record.
WipeStep databaseWipeStep({
  required AppDatabase db,
  required DestroyableDatabaseOpener opener,
  required String reason,
  DateTime Function()? clock,
  List<String> keep = wipeKeepKeys,
}) => WipeStep('database', () async {
  final kept = <String, String>{};
  for (final key in keep) {
    try {
      final value = await db.getValue(key);
      if (value != null) kept[key] = value;
    } on Object {
      // An unreadable database has nothing to keep.
    }
  }
  try {
    await db.close();
  } on Object {
    // Already closed.
  }
  await opener.destroy();
  final fresh = AppDatabase(opener.open());
  try {
    for (final e in kept.entries) {
      await fresh.setValue(e.key, e.value);
    }
    await fresh.setValue(
      wipeNoticeKey,
      jsonEncode(<String, Object?>{
        'at': (clock ?? () => DateTime.now().toUtc())().toIso8601String(),
        'reason': reason,
      }),
    );
  } finally {
    await fresh.close();
  }
});

/// Forgets the session (the device id stays: the server keeps recognising
/// a phone reported lost).
WipeStep tokensWipeStep(TokenStore tokens) => WipeStep('tokens', tokens.clear);

/// Deletes the directories [resolve] returns (photos, uploads, caches).
WipeStep filesWipeStep(Future<List<Directory>> Function() resolve) =>
    WipeStep('files', () async {
      for (final dir in await resolve()) {
        if (await dir.exists()) await dir.delete(recursive: true);
      }
    });

/// The wipe the apps run, in order: stop duty (no more location), forget
/// the session (no more authenticated calls), the database and its key,
/// then cached files (photos, pending uploads, image picker caches).
List<WipeStep> standardWipeSteps({
  required AppDatabase db,
  required DestroyableDatabaseOpener opener,
  required TokenStore tokens,
  required String reason,
  ForegroundDutyService? dutyService,
  LocationSampler? sampler,
  Future<List<Directory>> Function()? directories,
  DateTime Function()? clock,
}) => <WipeStep>[
  if (dutyService != null || sampler != null)
    stopDutyStep(service: dutyService, sampler: sampler),
  tokensWipeStep(tokens),
  databaseWipeStep(db: db, opener: opener, reason: reason, clock: clock),
  if (directories != null) filesWipeStep(directories),
];

/// On-device file caches the wipe deletes: `<documents>/photos` (visit and
/// farm photos, also the chunked-upload sources) and the temporary
/// directory (camera / image picker output).
Future<List<Directory>> appCacheDirectories() async => <Directory>[
  Directory('${(await getApplicationDocumentsDirectory()).path}/photos'),
  await getTemporaryDirectory(),
];

/// Removes the A08 notice (the user tapped "Sign in again").
Future<void> clearWipeNotice(AppDatabase db) => db.removeValue(wipeNoticeKey);

/// Whether a wipe happened and A08 must be shown.
Future<bool> hasWipeNotice(AppDatabase db) async =>
    await db.getValue(wipeNoticeKey) != null;

/// `GET /v1/devices/me/status` answer.
@immutable
class DeviceStatus {
  /// Creates the status.
  const DeviceStatus({
    required this.status,
    required this.wipeRequired,
    this.userStatus = 'active',
  });

  /// Parses the wire shape.
  factory DeviceStatus.fromJson(Map<String, Object?> json) => DeviceStatus(
    status: (json['status'] as String?) ?? 'unknown',
    wipeRequired: json['wipe_required'] == true,
    userStatus: (json['user_status'] as String?) ?? 'active',
  );

  /// `pending | active | revoked | lost | unknown`.
  final String status;

  /// Wipe now.
  final bool wipeRequired;

  /// `active | disabled`.
  final String userStatus;
}

/// Reads this device's status.
abstract interface class DeviceStatusApi {
  /// The status, or `null` when the request did not complete (offline,
  /// signed out, server error).
  Future<DeviceStatus?> fetch();
}

/// Scriptable status for tests.
class FakeDeviceStatusApi implements DeviceStatusApi {
  /// Creates the fake.
  FakeDeviceStatusApi({this.status});

  /// What [fetch] answers.
  DeviceStatus? status;

  /// Calls so far.
  int calls = 0;

  @override
  Future<DeviceStatus?> fetch() async {
    calls += 1;
    return status;
  }
}

/// [DeviceStatusApi] over [RestJsonClient] with `X-Device-Id`.
class HttpDeviceStatusApi implements DeviceStatusApi {
  /// Creates the client.
  HttpDeviceStatusApi(this._rest, this._tokens);

  final RestJsonClient _rest;
  final TokenStore _tokens;

  @override
  Future<DeviceStatus?> fetch() async {
    final response = await _rest.get(
      '/v1/devices/me/status',
      headers: <String, String>{'X-Device-Id': await _tokens.deviceId()},
    );
    return response.ok ? DeviceStatus.fromJson(response.body) : null;
  }
}

/// The start-up check (SEC-025): when signed in and online, asks the
/// server and triggers [signal] on `wipe_required`. A 401
/// `device_wipe_required` triggers it through [SecureApiClient]; any other
/// failure (offline, timeout) does nothing. Returns whether the server
/// answered.
Future<bool> checkDeviceStatusOnStart({
  required TokenStore tokens,
  required DeviceStatusApi api,
  required WipeSignal signal,
  Future<bool> Function()? isOnline,
}) async {
  if (await tokens.read() == null) return false;
  if (isOnline != null && !await isOnline()) return false;
  final status = await api.fetch();
  if (status == null) return false;
  if (status.wipeRequired) signal.trigger('device_status:${status.status}');
  return true;
}

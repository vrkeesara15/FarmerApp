/// NF-014 / SPEC 8.4 / OPS-002: crash and non-fatal reporting behind a seam.
///
/// The transport is Firebase Crashlytics, which lives in the apps
/// (`apps/*/lib/observability.dart`) exactly like the FA-007 push transport:
/// the core never imports Firebase, so the workspace, the tests and a build
/// with no `google-services.json` all stay free of it. A build without
/// Firebase gets [NoCrashReporter] and everything else keeps working -- crash
/// reporting is diagnostics, never a dependency of the farmer's work.
///
/// What it is for (docs/runbooks/bad-mobile-release-rollback.md): crash-free
/// sessions per app version is the OPS-002 signal that halts a staged
/// rollout. That number is only trustworthy if the app also reports the
/// failures it *handles* -- a sync that gives up, a photo that will not
/// upload -- which is what [recordError] with `fatal: false` is for.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Reports crashes and handled errors.
///
/// Implementations must never throw: a failure to report an error must not
/// become a second error.
abstract interface class CrashReporter {
  /// Whether reports actually leave the device.
  bool get isEnabled;

  /// Records an error. [fatal] marks a crash; handled failures are non-fatal.
  Future<void> recordError(
    Object error,
    StackTrace? stack, {
    String? reason,
    bool fatal = false,
  });

  /// A breadcrumb shown with the next report.
  Future<void> log(String message);

  /// A key/value shown on every later report (app version, tenant, the
  /// current trace id -- never a name, a phone or a token: SEC / NF-011).
  Future<void> setCustomKey(String key, Object value);

  /// The signed-in user for grouping. Pass the opaque user id, never a phone.
  Future<void> setUserId(String? id);
}

/// Does nothing. Used when the build has no Firebase configuration, when the
/// device has no Play services, and in every test that does not assert on
/// reporting.
class NoCrashReporter implements CrashReporter {
  /// Creates the reporter.
  const NoCrashReporter();

  @override
  bool get isEnabled => false;

  @override
  Future<void> recordError(
    Object error,
    StackTrace? stack, {
    String? reason,
    bool fatal = false,
  }) async {}

  @override
  Future<void> log(String message) async {}

  @override
  Future<void> setCustomKey(String key, Object value) async {}

  @override
  Future<void> setUserId(String? id) async {}
}

/// One recorded error.
@immutable
class RecordedError {
  /// Creates the record.
  const RecordedError(
    this.error,
    this.stack, {
    this.reason,
    this.fatal = false,
  });

  /// The error.
  final Object error;

  /// Its stack, when there was one.
  final StackTrace? stack;

  /// Why it was recorded.
  final String? reason;

  /// Whether it crashed the app.
  final bool fatal;

  @override
  String toString() => '${fatal ? 'fatal' : 'non-fatal'} $error ($reason)';
}

/// Records in memory (tests, previews).
class FakeCrashReporter implements CrashReporter {
  /// Errors, in order.
  final List<RecordedError> errors = <RecordedError>[];

  /// Breadcrumbs, in order.
  final List<String> breadcrumbs = <String>[];

  /// Custom keys, last write wins.
  final Map<String, Object> keys = <String, Object>{};

  /// The last user id set.
  String? userId;

  @override
  bool get isEnabled => true;

  @override
  Future<void> recordError(
    Object error,
    StackTrace? stack, {
    String? reason,
    bool fatal = false,
  }) async =>
      errors.add(RecordedError(error, stack, reason: reason, fatal: fatal));

  @override
  Future<void> log(String message) async => breadcrumbs.add(message);

  @override
  Future<void> setCustomKey(String key, Object value) async =>
      keys[key] = value;

  @override
  Future<void> setUserId(String? id) async => userId = id;
}

/// The crash reporter; the apps override it with their Firebase adapter.
final Provider<CrashReporter> crashReporterProvider = Provider<CrashReporter>(
  (ref) => const NoCrashReporter(),
);

/// Custom-key names, so the app, the runbook and Crashlytics agree.
abstract final class CrashKeys {
  /// App version (`crash-free sessions per app version`, OPS-002).
  static const String appVersion = 'app_version';

  /// The tenant, for a regression that only one tenant sees.
  static const String tenantId = 'tenant_id';

  /// The last trace id sent to the API (NF-014): joins a Crashlytics report
  /// to the API's structured logs and Cloud Trace.
  static const String traceId = 'trace_id';

  /// The route the user was on.
  static const String route = 'route';

  /// Whether the device was offline when it happened (NF-002).
  static const String online = 'online';
}

/// Installs [reporter] as the sink for Flutter's own error channels.
///
/// Three channels, all of which are silent crashes without this:
/// * `FlutterError.onError` -- errors inside the widget tree. In debug the
///   original handler still prints them, because a red screen you can read
///   beats a report you cannot.
/// * `PlatformDispatcher.instance.onError` -- uncaught asynchronous errors.
/// * the zone around [body], for anything raised before the bindings exist.
///
/// Every error reaches the reporter; [body] still runs to completion.
Future<void> runWithCrashReporting(
  CrashReporter reporter,
  Future<void> Function() body,
) {
  final previousOnError = FlutterError.onError;
  FlutterError.onError = (details) {
    unawaited(
      reporter.recordError(
        details.exception,
        details.stack,
        reason: details.context?.toDescription(),
        fatal: true,
      ),
    );
    if (kDebugMode) previousOnError?.call(details);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    unawaited(reporter.recordError(error, stack, fatal: true));
    return true;
  };
  final done = Completer<void>();
  runZonedGuarded<void>(
    () async {
      try {
        await body();
      } finally {
        if (!done.isCompleted) done.complete();
      }
    },
    (error, stack) {
      unawaited(reporter.recordError(error, stack, fatal: true));
      if (!done.isCompleted) done.complete();
    },
  );
  return done.future;
}

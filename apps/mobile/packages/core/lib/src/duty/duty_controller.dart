import 'dart:async';

import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/app_database.dart';
import '../geo/geo.dart';
import '../state/auth_flow.dart';
import '../sync/sync_models.dart';
import '../sync/sync_providers.dart';
import '../sync/sync_store.dart';
import '../utils/format.dart';
import 'duty_models.dart';
import 'duty_providers.dart';
import 'duty_repository.dart';
import 'location_sampler.dart';

/// Why the toggle could not go on.
enum DutyStartResult {
  /// The session was created and the service started.
  started,

  /// A05 not accepted for the current policy version (FA-011).
  policyNotAccepted,

  /// No GPS fix could be obtained (service off, permission missing).
  locationUnavailable,

  /// A session is already active on this device.
  alreadyActive,
}

/// One-line notices A10 shows after something ended the shift.
enum DutyNotice {
  /// The tenant auto-end time passed (VV-007).
  autoEnded,

  /// The server ended the session (idle / day end / manager).
  endedByServer,

  /// The server rejected the start: another device is already on duty.
  alreadyActiveElsewhere,

  /// The server rejected the start: the policy must be accepted again.
  policyNotAccepted,

  /// No fix; duty stays off.
  locationUnavailable,
}

/// What A10 shows.
@immutable
class DutyState {
  /// Creates the state.
  const DutyState({
    this.active,
    this.elapsed = Duration.zero,
    this.pointsPending = 0,
    this.integrity = const IntegritySnapshot(),
    this.notice,
    this.busy = false,
    this.restored = false,
  });

  /// The open session, or null while off duty.
  final DutySession? active;

  /// Time since [active] started.
  final Duration elapsed;

  /// Points waiting for upload.
  final int pointsPending;

  /// Latest FA-028 signals (banner when [IntegritySnapshot.hasIssues]).
  final IntegritySnapshot integrity;

  /// A notice to show once.
  final DutyNotice? notice;

  /// Starting or ending right now.
  final bool busy;

  /// [DutyController.restore] has run.
  final bool restored;

  /// On duty.
  bool get onDuty => active != null;

  /// Copy with overrides.
  DutyState copyWith({
    DutySession? active,
    bool clearActive = false,
    Duration? elapsed,
    int? pointsPending,
    IntegritySnapshot? integrity,
    DutyNotice? notice,
    bool clearNotice = false,
    bool? busy,
    bool? restored,
  }) => DutyState(
    active: clearActive ? null : active ?? this.active,
    elapsed: elapsed ?? this.elapsed,
    pointsPending: pointsPending ?? this.pointsPending,
    integrity: integrity ?? this.integrity,
    notice: clearNotice ? null : notice ?? this.notice,
    busy: busy ?? this.busy,
    restored: restored ?? this.restored,
  );
}

/// Drives the DutyToggle (FA-010, VV-001, VV-007, FA-028).
///
/// On: `duty_session` create op with the current fix and the integrity
/// signals, then the foreground service, then the sampler. Off: sampler
/// and service stopped first, buffer flushed, `duty_session` update op
/// with `end_at`. **Nothing samples while no session is active** — the
/// sampler is started only inside [_adopt], after the row exists, and the
/// fix listener ignores fixes once the session is gone.
class DutyController extends Notifier<DutyState> {
  /// VV-007 prompt lead time.
  static const Duration promptLead = Duration(minutes: 10);

  StreamSubscription<LocationFix>? _fixSub;
  StreamSubscription<DutySession?>? _sessionSub;
  StreamSubscription<List<OutboxRow>>? _opsSub;
  StreamSubscription<Object?>? _conditionsSub;
  StreamSubscription<void>? _tickSub;
  Future<void> _fixChain = Future<void>.value();
  SamplingCadence? _cadence;
  DateTime? _autoEndAt;
  DateTime? _lastFlushAt;
  bool _ending = false;
  bool _flushing = false;
  bool _disposed = false;

  @override
  DutyState build() {
    ref.onDispose(() {
      _disposed = true;
      unawaited(_cancelSubscriptions());
    });
    return const DutyState();
  }

  DutyRepository get _repo => ref.read(dutyRepositoryProvider);
  DateTime get _now => ref.read(clockProvider)();
  DutyPolicy get _policy => ref.read(locationPolicyProvider).duty;

  void _set(DutyState next) {
    if (_disposed) return;
    state = next;
  }

  /// The state, or an empty one once the provider is gone (stream
  /// callbacks can fire after dispose).
  DutyState get _s => _disposed ? const DutyState() : state;

  /// When the current session auto-ends (UTC), if on duty.
  DateTime? get autoEndAt => _autoEndAt;

  /// Resumes an open session after an app restart (service + sampler
  /// again); marks the state restored either way.
  Future<void> restore() async {
    await ref.read(locationPolicyProvider.notifier).load();
    await restoreClockDrift(ref);
    final open = await _repo.activeSession();
    if (open == null) {
      _set(_s.copyWith(restored: true));
      return;
    }
    await _adopt(open, resume: true);
    _set(_s.copyWith(restored: true));
  }

  /// Switches duty on.
  Future<DutyStartResult> goOnDuty() async {
    if (_s.active != null) return DutyStartResult.alreadyActive;
    final policy = ref.read(locationPolicyProvider.notifier);
    await policy.load();
    if (!ref.read(locationPolicyProvider).accepted) {
      return DutyStartResult.policyNotAccepted;
    }
    _set(_s.copyWith(busy: true, clearNotice: true));
    final sampler = ref.read(locationSamplerProvider);
    final fix = await sampler.current();
    if (fix == null) {
      _set(_s.copyWith(busy: false, notice: DutyNotice.locationUnavailable));
      return DutyStartResult.locationUnavailable;
    }
    final now = _now;
    final integrity = await ref
        .read(deviceIntegrityProvider)
        .snapshot(fixIsMock: fix.isMock, now: now);
    final id = ref.read(idGeneratorProvider)();
    final deviceId = await ref.read(tokenStoreProvider).deviceId();
    await ref.read(outboxProvider).enqueueCreate(
      SyncEntities.dutySession,
      id,
      <String, Object?>{
        'device_id': deviceId,
        'app_version': ref.read(appVersionProvider),
        'policy_version': ref.read(locationPolicyProvider).current.version,
        'start_at': now.toIso8601String(),
        'start_point': fix.toPointJson(),
        'integrity': integrity.toJson(),
      },
    );
    final row = (await _repo.session(id))!;
    await _adopt(row, integrity: integrity);
    _set(_s.copyWith(busy: false));
    return DutyStartResult.started;
  }

  /// Switches duty off (`end_reason: manual`).
  Future<void> goOffDuty() => _end(DutyEndReason.manual);

  /// Clears the one-shot notice.
  void dismissNotice() => _set(_s.copyWith(clearNotice: true));

  Future<void> _adopt(
    DutySession row, {
    bool resume = false,
    IntegritySnapshot? integrity,
  }) async {
    _ending = false;
    final policy = _policy;
    final copy = ref.read(dutyCopyProvider);
    final now = _now;
    final pending = await _repo.pendingCount(row.id);
    _set(
      _s.copyWith(
        active: row,
        elapsed: now.difference(row.startAt.toUtc()),
        pointsPending: pending,
        integrity: integrity,
        clearNotice: true,
      ),
    );
    final service = ref.read(foregroundDutyServiceProvider);
    await service.start(
      title: copy.notificationTitle,
      text: copy.notificationText(_s.elapsed),
    );
    final cadence = SamplingCadence(policy);
    final last = await _repo.lastPoint(row.id);
    if (last != null) {
      cadence.seed(
        LocationFix(
          point: GeoPoint(last.lat, last.lon),
          accuracyM: last.accuracyM,
          time: last.ts.toUtc(),
        ),
      );
    }
    _cadence = cadence;
    final sampler = ref.read(locationSamplerProvider);
    await _fixSub?.cancel();
    _fixSub = sampler.fixes.listen(_onFix);
    await sampler.start(policy);
    _autoEndAt = policy.nextAutoEnd(row.startAt.toUtc());
    final promptAt = _autoEndAt!.subtract(promptLead);
    final alerts = ref.read(dutyAlertsProvider);
    if (promptAt.isAfter(now)) {
      await alerts.schedulePrompt(
        at: promptAt,
        title: copy.promptTitle,
        body: copy.promptBody(_autoEndAt!),
      );
    }
    _lastFlushAt = resume ? null : now;
    await _sessionSub?.cancel();
    _sessionSub = _repo.watchSession(row.id).listen(_onSessionRow);
    await _opsSub?.cancel();
    _opsSub = _repo.watchOps(row.id).listen(_onOps);
    await _conditionsSub?.cancel();
    _conditionsSub = ref.read(deviceConditionsProvider).changes.listen((c) {
      if (c.uploadFriendly && policy.uploadOnWifiOrCharging) {
        unawaited(flush());
      }
    });
    await _tickSub?.cancel();
    _tickSub = ref.read(dutyTickerProvider).listen((_) => unawaited(tick()));
    if (resume) await tick();
  }

  void _onFix(LocationFix fix) {
    _fixChain = _fixChain.then((_) => _handleFix(fix));
  }

  Future<void> _handleFix(LocationFix fix) async {
    final active = _s.active;
    final cadence = _cadence;
    if (active == null || cadence == null || _ending) return;
    final previous = cadence.last;
    if (!cadence.accept(fix)) return;
    final integrity = await ref
        .read(deviceIntegrityProvider)
        .snapshot(fixIsMock: fix.isMock, now: _now);
    final conditions = await ref.read(deviceConditionsProvider).read();
    if (_s.active?.id != active.id || _ending) return;
    await _repo.insertPoint(
      sessionId: active.id,
      fix: fix,
      integrity: integrity,
      batteryPct: conditions.batteryPct,
    );
    if (previous != null) {
      await _repo.addDistance(
        active.id,
        distanceMetres(previous.point, fix.point),
      );
    }
    final pending = await _repo.pendingCount(active.id);
    _set(_s.copyWith(pointsPending: pending, integrity: integrity));
    if (pending >= maxPointsPerBatch) await flush();
  }

  /// Periodic work: elapsed time, notification text, auto-end, the
  /// 15-minute flush. Driven by [dutyTickerProvider]; tests call it.
  Future<void> tick() async {
    final active = _s.active;
    if (active == null || _ending) return;
    final now = _now;
    final elapsed = now.difference(active.startAt.toUtc());
    _set(_s.copyWith(elapsed: elapsed));
    final copy = ref.read(dutyCopyProvider);
    await ref
        .read(foregroundDutyServiceProvider)
        .update(text: copy.notificationText(elapsed));
    final autoEnd = _autoEndAt;
    if (autoEnd != null && !now.isBefore(autoEnd)) {
      await _end(DutyEndReason.autoTime, notice: DutyNotice.autoEnded);
      return;
    }
    final last = _lastFlushAt;
    if (last == null || now.difference(last) >= _policy.uploadInterval) {
      await flush();
    }
  }

  /// Queues the buffered points as `location_batch` ops (≤ 500 points
  /// each) and stamps them.
  Future<void> flush() async {
    final active = _s.active;
    if (active == null || _flushing) return;
    _flushing = true;
    try {
      final now = _now;
      final deviceId = await ref.read(tokenStoreProvider).deviceId();
      final outbox = ref.read(outboxProvider);
      while (true) {
        final points = await _repo.pendingPoints(active.id);
        if (points.isEmpty) break;
        final batchId = ref.read(idGeneratorProvider)();
        await outbox.enqueueCreate(
          SyncEntities.locationBatch,
          batchId,
          <String, Object?>{
            'duty_session_id': active.id,
            'device_id': deviceId,
            'sent_at': now.toIso8601String(),
            'points': <Object?>[
              for (final p in points) DutyRepository.pointJson(p),
            ],
          },
        );
        await _repo.markBatched(points.map((p) => p.id).toList(), batchId);
        if (points.length < maxPointsPerBatch) break;
      }
      _lastFlushAt = now;
      await _repo.purgeBatchedBefore(now.subtract(const Duration(days: 2)));
      await _repo.purgeBatchDocsBefore(now.subtract(const Duration(days: 7)));
      _set(_s.copyWith(pointsPending: await _repo.pendingCount(active.id)));
    } finally {
      _flushing = false;
    }
  }

  /// Cancels every subscription. Not awaited: a broadcast subscription's
  /// `cancel()` resolves on a root-zone microtask, which never runs inside
  /// a widget test's fake async zone; the callbacks check `_ending` /
  /// `_disposed` themselves.
  Future<void> _cancelSubscriptions() async {
    unawaited(_fixSub?.cancel());
    unawaited(_sessionSub?.cancel());
    unawaited(_opsSub?.cancel());
    unawaited(_conditionsSub?.cancel());
    unawaited(_tickSub?.cancel());
    _fixSub = null;
    _sessionSub = null;
    _opsSub = null;
    _conditionsSub = null;
    _tickSub = null;
    _cadence = null;
    _autoEndAt = null;
  }

  Future<void> _stopPlatform() async {
    await ref.read(locationSamplerProvider).stop();
    await ref.read(foregroundDutyServiceProvider).stop();
    await ref.read(dutyAlertsProvider).cancelPrompt();
  }

  Future<void> _end(DutyEndReason reason, {DutyNotice? notice}) async {
    final active = _s.active;
    if (active == null || _ending) return;
    _ending = true;
    _set(_s.copyWith(busy: true));
    await _cancelSubscriptions();
    await _fixChain;
    await _stopPlatform();
    final sampler = ref.read(locationSamplerProvider);
    final fix = await sampler.current();
    final now = _now;
    await flush();
    await ref.read(outboxProvider).enqueueUpdate(
      SyncEntities.dutySession,
      active.id,
      <String, Object?>{
        'end_at': now.toIso8601String(),
        'end_point': fix?.toPointJson(),
        'end_reason': reason.wire,
      },
    );
    if (notice != null) {
      final copy = ref.read(dutyCopyProvider);
      await ref
          .read(dutyAlertsProvider)
          .notice(title: copy.endedTitle, body: copy.autoEndedBody(now));
    }
    _set(
      _s.copyWith(
        clearActive: true,
        elapsed: Duration.zero,
        pointsPending: 0,
        busy: false,
        notice: notice,
      ),
    );
  }

  /// The server owns `end_at` once it auto-ended the session (VV-007): a
  /// `conflict` or a pulled change writes the row with `end_at`; stop the
  /// service and tell the officer.
  Future<void> _onSessionRow(DutySession? row) async {
    final active = _s.active;
    if (row == null || active == null || _ending) return;
    if (row.endAt == null) {
      if (row.version != active.version) {
        _set(_s.copyWith(active: row));
      }
      return;
    }
    _ending = true;
    await _cancelSubscriptions();
    await _fixChain;
    await _stopPlatform();
    await flush();
    final copy = ref.read(dutyCopyProvider);
    await ref
        .read(dutyAlertsProvider)
        .notice(title: copy.endedTitle, body: copy.serverEndedBody);
    _set(
      _s.copyWith(
        clearActive: true,
        elapsed: Duration.zero,
        pointsPending: 0,
        busy: false,
        notice: DutyNotice.endedByServer,
      ),
    );
  }

  /// The create op was rejected (`duty_already_active`,
  /// `policy_not_accepted`): nothing exists server-side, so the local
  /// session is dropped rather than ended with an op.
  Future<void> _onOps(List<OutboxRow> rows) async {
    final active = _s.active;
    if (active == null || _ending) return;
    final rejected = rows
        .where(
          (r) =>
              r.action == SyncAction.create.name &&
              r.state == OutboxState.rejected.name,
        )
        .firstOrNull;
    if (rejected == null) return;
    final code = SyncStore.errorOf(rejected)?.code;
    _ending = true;
    await _cancelSubscriptions();
    await _fixChain;
    await _stopPlatform();
    await ref.read(syncEngineProvider).discard(rejected.opId);
    final policyRejected = code == 'policy_not_accepted';
    if (policyRejected) {
      await ref.read(locationPolicyProvider.notifier).markNotAccepted();
    }
    _set(
      _s.copyWith(
        clearActive: true,
        elapsed: Duration.zero,
        pointsPending: 0,
        busy: false,
        notice: policyRejected
            ? DutyNotice.policyNotAccepted
            : DutyNotice.alreadyActiveElsewhere,
      ),
    );
  }
}

/// Formats the elapsed time for the notification (shared with the UI).
String dutyElapsedText(Duration elapsed) => formatElapsed(elapsed);

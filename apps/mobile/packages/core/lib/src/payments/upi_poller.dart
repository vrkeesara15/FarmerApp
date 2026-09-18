import 'dart:async';

import 'package:flutter/foundation.dart' show immutable;

import 'payments_api.dart';

/// Where an A53 UPI collection stands.
enum UpiPollPhase {
  /// QR on screen, not paid yet.
  waiting,

  /// The server marked the payment paid (webhook).
  paid,

  /// The provider reported a failure.
  failed,

  /// The QR expired before the farmer paid.
  expired,
}

/// One poll result.
@immutable
class UpiPollState {
  /// Creates the state.
  const UpiPollState(this.phase, {this.polls = 0, this.failureReason});

  /// Phase.
  final UpiPollPhase phase;

  /// Polls made so far.
  final int polls;

  /// Provider reason on [UpiPollPhase.failed].
  final String? failureReason;

  /// Nothing more will happen.
  bool get isFinal => phase != UpiPollPhase.waiting;
}

/// Polls `GET /v1/payments/{id}` for A53 (FA-021): every 3 s for the first
/// [fastPolls] polls, then backing off by 1.5x up to 10 s, and stops at
/// the QR's expiry, on `paid` or on `failed`. Clock and sleep are injected
/// so tests drive it with a fake clock.
class UpiPoller {
  /// Creates the poller.
  UpiPoller({
    required this.fetch,
    required this.clock,
    required this.sleep,
    this.expiresAt,
    this.first = const Duration(seconds: 3),
    this.max = const Duration(seconds: 10),
    this.fastPolls = 10,
  });

  /// One status call.
  final Future<PaymentCallOutcome> Function() fetch;

  /// Now (UTC).
  final DateTime Function() clock;

  /// Waits (real `Future.delayed` in the app, a clock advance in tests).
  final Future<void> Function(Duration) sleep;

  /// QR expiry; polling stops there.
  final DateTime? expiresAt;

  /// Interval of the first polls.
  final Duration first;

  /// Interval cap.
  final Duration max;

  /// Polls at [first] before backing off.
  final int fastPolls;

  /// Wait before poll number [n] + 1 (n counted from 1).
  Duration intervalAfter(int n) {
    if (n < fastPolls) return first;
    var ms = first.inMilliseconds.toDouble();
    for (var i = fastPolls; i <= n; i++) {
      ms *= 1.5;
    }
    final capped = ms.round().clamp(first.inMilliseconds, max.inMilliseconds);
    return Duration(milliseconds: capped);
  }

  bool _expired() {
    final e = expiresAt;
    return e != null && !clock().isBefore(e);
  }

  /// Polls until a final state; the stream ends after it.
  Stream<UpiPollState> run() async* {
    var polls = 0;
    while (true) {
      if (_expired()) {
        yield UpiPollState(UpiPollPhase.expired, polls: polls);
        return;
      }
      final out = await fetch();
      polls += 1;
      if (out.result == PaymentCallResult.ok) {
        final state = out.body['state'] as String?;
        if (state == 'paid') {
          yield UpiPollState(UpiPollPhase.paid, polls: polls);
          return;
        }
        if (state == 'failed') {
          yield UpiPollState(
            UpiPollPhase.failed,
            polls: polls,
            failureReason: out.body['failure_reason'] as String?,
          );
          return;
        }
      }
      yield UpiPollState(UpiPollPhase.waiting, polls: polls);
      var wait = intervalAfter(polls);
      final e = expiresAt;
      if (e != null) {
        final left = e.difference(clock());
        if (left < wait) wait = left.isNegative ? Duration.zero : left;
      }
      await sleep(wait);
    }
  }
}

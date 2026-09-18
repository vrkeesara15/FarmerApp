import 'dart:math';

import 'package:flutter/foundation.dart' show immutable;

/// Exponential backoff with jitter for transport failures (NF-003).
///
/// Ceilings: 1 s, 2 s, 4 s, ... doubling per consecutive failure and capped
/// at [cap] (5 min). The actual delay is drawn uniformly from
/// `[ceiling * (1 - jitter), ceiling]` so many phones regaining signal at
/// once do not hit the API in lock-step.
@immutable
class Backoff {
  /// Creates the schedule.
  const Backoff({
    this.base = const Duration(seconds: 1),
    this.cap = const Duration(minutes: 5),
    this.jitter = 0.5,
  }) : assert(jitter >= 0 && jitter <= 1, 'jitter is a fraction');

  /// Delay ceiling after the first failure.
  final Duration base;

  /// Largest ceiling.
  final Duration cap;

  /// Fraction of the ceiling the jitter may shave off.
  final double jitter;

  /// Ceiling for consecutive failure number [attempt] (1-based), no jitter.
  Duration ceiling(int attempt) {
    if (attempt <= 1) return base < cap ? base : cap;
    final exponent = (attempt - 1).clamp(0, 62);
    final ms = base.inMilliseconds * (1 << exponent);
    return ms >= cap.inMilliseconds || ms <= 0
        ? cap
        : Duration(milliseconds: ms);
  }

  /// Jittered delay for consecutive failure number [attempt] (1-based).
  Duration delay(int attempt, {Random? random}) {
    final max = ceiling(attempt).inMilliseconds;
    final min = (max * (1 - jitter)).round();
    final rng = random ?? Random();
    return Duration(milliseconds: min + rng.nextInt(max - min + 1));
  }
}

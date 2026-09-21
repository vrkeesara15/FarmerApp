/// NF-014: W3C trace context, so one farmer action can be followed from the
/// phone through the API into the workers.
///
/// The API already speaks this protocol end to end (`farmerapp/telemetry.py`):
/// it accepts a `traceparent` header, continues the trace through SQLAlchemy,
/// injects it into Pub/Sub message attributes and picks it up again in the
/// worker. Every structured log line carries the same `trace_id`. The one
/// missing link was the phone, which started no trace of its own, so a farmer
/// tapping "Send" and an API span were two unrelated facts.
///
/// The apps do not run an OpenTelemetry SDK. A mobile SDK would add a
/// background exporter, a queue and several hundred kilobytes to a 25 MB APK
/// budget (FM-014) for spans nobody looks at: the useful span tree is on the
/// server. What the phone must do is *start* the trace and hand the id over,
/// which is what this file does. `SecureApiClient` puts the header on every
/// request; the crash reporter records the same id, so a Crashlytics report
/// and the API's logs meet.
library;

import 'dart:math';

/// The W3C header name.
const String traceparentHeader = 'traceparent';

/// A W3C `traceparent`: version 00, a 128-bit trace id, a 64-bit span id and
/// the sampled flag.
///
/// The phone is the root of the trace, so [spanId] is the id of the client
/// span the API's server span becomes a child of.
class TraceContext {
  /// Creates a context from ids that are already hex.
  const TraceContext({
    required this.traceId,
    required this.spanId,
    this.sampled = true,
  });

  /// A fresh root context.
  ///
  /// [random] is injectable so tests can assert exact ids; production uses
  /// [Random.secure] (a trace id is not a secret, but a predictable one lets
  /// an observer correlate a phone's requests).
  factory TraceContext.random({Random? random, bool sampled = true}) {
    final rnd = random ?? Random.secure();
    return TraceContext(
      traceId: _hex(rnd, 16),
      spanId: _hex(rnd, 8),
      sampled: sampled,
    );
  }

  /// Parses a `traceparent` value, or returns null when it is malformed or a
  /// version this app does not understand.
  ///
  /// An all-zero trace or span id is invalid per the spec and is rejected:
  /// forwarding it would make every request look like the same trace.
  static TraceContext? parse(String? header) {
    if (header == null) return null;
    final parts = header.trim().split('-');
    if (parts.length != 4) return null;
    final [version, traceId, spanId, flags] = parts;
    if (version != '00') return null;
    if (!_isHex(traceId, 32) || !_isHex(spanId, 16) || !_isHex(flags, 2)) {
      return null;
    }
    if (traceId == '0' * 32 || spanId == '0' * 16) return null;
    return TraceContext(
      traceId: traceId,
      spanId: spanId,
      sampled: int.parse(flags, radix: 16) & 0x01 == 1,
    );
  }

  /// 32 lower-case hex characters.
  final String traceId;

  /// 16 lower-case hex characters.
  final String spanId;

  /// Whether the server is asked to record this trace.
  final bool sampled;

  /// The header value: `00-<trace id>-<span id>-<flags>`.
  String get header => '00-$traceId-$spanId-${sampled ? '01' : '00'}';

  /// A new span in the same trace (a retry, or a second call in one action).
  TraceContext child({Random? random}) => TraceContext(
    traceId: traceId,
    spanId: _hex(random ?? Random.secure(), 8),
    sampled: sampled,
  );

  @override
  String toString() => header;

  @override
  bool operator ==(Object other) =>
      other is TraceContext &&
      other.traceId == traceId &&
      other.spanId == spanId &&
      other.sampled == sampled;

  @override
  int get hashCode => Object.hash(traceId, spanId, sampled);

  static String _hex(Random random, int bytes) {
    final buffer = StringBuffer();
    for (var i = 0; i < bytes; i++) {
      buffer.write(random.nextInt(256).toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }

  static bool _isHex(String value, int length) =>
      value.length == length &&
      RegExp(r'^[0-9a-f]+$').hasMatch(value.toLowerCase());
}

/// Decides which requests carry a sampled trace (NF-014 head sampling).
///
/// Sampling happens on the phone because that is where the trace starts: an
/// unsampled request still carries a `traceparent` (so the API's log line has
/// the same `trace_id` and the two can be joined), it just asks the server not
/// to record spans for it. The API's own `OTEL_SAMPLE_RATIO` is the second
/// gate.
class TraceSampler {
  /// [ratio] 1.0 records everything, 0.0 nothing.
  TraceSampler({double ratio = 1, Random? random})
    : assert(ratio >= 0 && ratio <= 1, 'ratio must be between 0 and 1'),
      _ratio = ratio,
      _random = random ?? Random.secure();

  final double _ratio;
  final Random _random;

  /// The sampling ratio in force.
  double get ratio => _ratio;

  /// A fresh root context, sampled according to [ratio].
  TraceContext next() => TraceContext.random(
    random: _random,
    sampled: _ratio >= 1 || (_ratio > 0 && _random.nextDouble() < _ratio),
  );
}

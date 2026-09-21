import 'dart:math';

import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

/// NF-014: the phone starts the trace and hands the id to the API, so one
/// farmer action can be followed app -> API -> worker.
void main() {
  group('TraceContext', () {
    test('a random context is a valid W3C traceparent', () {
      final trace = TraceContext.random(random: Random(7));
      expect(trace.traceId, hasLength(32));
      expect(trace.spanId, hasLength(16));
      expect(
        trace.header,
        matches(RegExp(r'^00-[0-9a-f]{32}-[0-9a-f]{16}-01$')),
      );
      // Round trip: whatever we send, we can read back.
      expect(TraceContext.parse(trace.header), trace);
    });

    test('an unsampled context still carries a usable id', () {
      final trace = TraceContext.random(random: Random(1), sampled: false);
      expect(trace.header, endsWith('-00'));
      final parsed = TraceContext.parse(trace.header)!;
      expect(parsed.sampled, isFalse);
      // The id is what joins the API's log line to the app's report, so it
      // matters even when the server records no spans.
      expect(parsed.traceId, trace.traceId);
    });

    test('malformed, unknown-version and all-zero headers are rejected', () {
      for (final bad in <String?>[
        null,
        '',
        'not-a-header',
        '00-tooshort-0000000000000001-01',
        // A version this app does not understand: the spec allows new fields
        // after the flags, but we refuse rather than guess.
        '01-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01',
        // All-zero ids are invalid: forwarding one would merge every request
        // in the fleet into a single trace.
        '00-${'0' * 32}-b7ad6b7169203331-01',
        '00-0af7651916cd43dd8448eb211c80319c-${'0' * 16}-01',
        '00-0AF7651916CD43DD8448EB211C80319C-b7ad6b7169203331-zz',
      ]) {
        expect(TraceContext.parse(bad), isNull, reason: 'rejects "$bad"');
      }
    });

    test('a well-formed header from the W3C spec parses', () {
      final trace = TraceContext.parse(
        '00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01',
      )!;
      expect(trace.traceId, '0af7651916cd43dd8448eb211c80319c');
      expect(trace.spanId, 'b7ad6b7169203331');
      expect(trace.sampled, isTrue);
    });

    test('a child keeps the trace and the sampling decision', () {
      final root = TraceContext.random(random: Random(3), sampled: false);
      final child = root.child(random: Random(4));
      expect(child.traceId, root.traceId);
      expect(child.spanId, isNot(root.spanId));
      expect(child.sampled, isFalse);
    });
  });

  group('TraceSampler', () {
    test('ratio 1 samples everything and ratio 0 nothing', () {
      final all = TraceSampler(random: Random(1));
      final none = TraceSampler(ratio: 0, random: Random(1));
      for (var i = 0; i < 20; i++) {
        expect(all.next().sampled, isTrue);
        expect(none.next().sampled, isFalse);
      }
    });

    test('every context is a new trace, sampled or not', () {
      final sampler = TraceSampler(ratio: 0, random: Random(9));
      final ids = <String>{for (var i = 0; i < 50; i++) sampler.next().traceId};
      expect(ids, hasLength(50), reason: 'a reused trace id joins two actions');
    });

    test('a fractional ratio samples roughly that share', () {
      final sampler = TraceSampler(ratio: 0.5, random: Random(11));
      final sampled = List.generate(
        400,
        (_) => sampler.next().sampled,
      ).where((s) => s).length;
      expect(sampled, greaterThan(150));
      expect(sampled, lessThan(250));
    });

    test(
      'an impossible ratio is a programming error, not a silent default',
      () {
        expect(() => TraceSampler(ratio: 1.5), throwsA(isA<AssertionError>()));
        expect(() => TraceSampler(ratio: -0.1), throwsA(isA<AssertionError>()));
      },
    );
  });

  group('SecureApiClient (NF-014)', () {
    test('every request carries a traceparent and the trace is reported', () {
      final seen = <TraceContext>[];
      final inner = _RecordingClient();
      final client = SecureApiClient(
        inner: inner,
        sampler: TraceSampler(random: Random(5)),
        onTrace: seen.add,
      );
      addTearDown(client.close);

      return client
          .get(Uri.parse('https://api.example.invalid/v1/visits'))
          .then((_) async {
            await client.post(Uri.parse('https://api.example.invalid/v1/sync'));
            expect(inner.requests, hasLength(2));
            for (final request in inner.requests) {
              final header = request.headers[traceparentHeader];
              expect(header, isNotNull);
              expect(TraceContext.parse(header), isNotNull);
            }
            // Two actions, two traces.
            expect(
              inner.requests[0].headers[traceparentHeader],
              isNot(inner.requests[1].headers[traceparentHeader]),
            );
            expect(seen, hasLength(2));
            expect(client.lastTrace!.header, seen.last.header);
          });
    });

    test('a caller that already set a traceparent keeps it', () async {
      final inner = _RecordingClient();
      final client = SecureApiClient(inner: inner);
      addTearDown(client.close);
      const existing =
          '00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01';

      await client.get(
        Uri.parse('https://api.example.invalid/v1/me'),
        headers: const <String, String>{traceparentHeader: existing},
      );

      expect(inner.requests.single.headers[traceparentHeader], existing);
      expect(client.lastTrace!.traceId, '0af7651916cd43dd8448eb211c80319c');
    });

    test(
      'a junk traceparent from a caller is replaced, not forwarded',
      () async {
        final inner = _RecordingClient();
        final client = SecureApiClient(inner: inner);
        addTearDown(client.close);

        await client.get(
          Uri.parse('https://api.example.invalid/v1/me'),
          headers: const <String, String>{traceparentHeader: 'garbage'},
        );

        final sent = inner.requests.single.headers[traceparentHeader]!;
        expect(sent, isNot('garbage'));
        expect(TraceContext.parse(sent), isNotNull);
      },
    );
  });
}

class _RecordingClient extends http.BaseClient {
  final List<http.BaseRequest> requests = <http.BaseRequest>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    return http.StreamedResponse(
      http.ByteStream.fromBytes(const <int>[]),
      200,
      request: request,
    );
  }
}

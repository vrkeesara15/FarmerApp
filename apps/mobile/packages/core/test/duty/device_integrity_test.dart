import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final t0 = DateTime.utc(2026, 9, 21, 3, 30);

  group('ClockDriftTracker', () {
    test('drift = device − server from the Date header, persisted', () {
      final persisted = <int>[];
      final tracker = ClockDriftTracker(onChanged: persisted.add);
      expect(tracker.driftSeconds, isNull);
      tracker.record(t0, t0.add(const Duration(seconds: 42)));
      expect(tracker.driftSeconds, 42);
      tracker.record(t0, t0.subtract(const Duration(seconds: 7)));
      expect(tracker.driftSeconds, -7);
      expect(persisted, <int>[42, -7]);
      expect(tracker.clockJumped, isFalse);
    });

    test('restore fills a missing drift only', () {
      final tracker = ClockDriftTracker()..restore(30);
      expect(tracker.driftSeconds, 30);
      tracker.record(t0, t0);
      tracker.restore(99);
      expect(tracker.driftSeconds, 0);
    });

    test('a wall-clock jump against the monotonic clock is a tamper signal '
        'and shifts the drift by the jump', () {
      var mono = Duration.zero;
      final tracker = ClockDriftTracker(monotonic: () => mono);
      tracker.record(t0, t0.add(const Duration(seconds: 5)));
      // 10 real minutes pass; the wall clock says 10 minutes too: no jump.
      mono = const Duration(minutes: 10);
      expect(
        tracker.checkpoint(t0.add(const Duration(minutes: 10, seconds: 5))),
        0,
      );
      expect(tracker.clockJumped, isFalse);
      // 1 real minute later the wall clock was set back by one hour.
      mono = const Duration(minutes: 11);
      final jump = tracker.checkpoint(
        t0.add(
          const Duration(minutes: 11, seconds: 5) - const Duration(hours: 1),
        ),
      );
      expect(jump, -3600);
      expect(tracker.clockJumped, isTrue);
      expect(tracker.driftSeconds, 5 - 3600);
      // Small disagreements (< 60 s) are noise, not tamper.
      mono = const Duration(minutes: 12);
      expect(
        tracker.checkpoint(
          t0.add(
            const Duration(minutes: 12, seconds: 35) - const Duration(hours: 1),
          ),
        ),
        0,
      );
      // The next server response resets the flag with the true drift.
      tracker.record(t0, t0.add(const Duration(seconds: 3)));
      expect(tracker.clockJumped, isFalse);
      expect(tracker.driftSeconds, 3);
    });

    test('a forward jump is detected too', () {
      var mono = Duration.zero;
      final tracker = ClockDriftTracker(monotonic: () => mono)..checkpoint(t0);
      mono = const Duration(seconds: 30);
      expect(tracker.checkpoint(t0.add(const Duration(days: 1))), 86400 - 30);
      expect(tracker.clockJumped, isTrue);
    });
  });

  group('DeviceIntegrity', () {
    test(
      'combines probes, per-fix mock flag and drift; never throws',
      () async {
        final probe = FakeDeviceIntegrityProbe(rooted: true);
        final clock = ClockDriftTracker()
          ..record(t0, t0.add(const Duration(seconds: 400)));
        final integrity = DeviceIntegrity(probe: probe, clock: clock);
        final s = await integrity.snapshot(
          now: t0.add(const Duration(seconds: 400)),
        );
        expect(s.isRooted, isTrue);
        expect(s.isMock, isFalse);
        expect(s.clockDriftS, 400);
        expect(s.hasIssues, isTrue);
        expect((await integrity.snapshot(fixIsMock: true)).isMock, isTrue);
      },
    );

    test(
      '"allow mock locations" counts as mock even for a clean fix',
      () async {
        final integrity = DeviceIntegrity(
          probe: FakeDeviceIntegrityProbe(mockAllowed: true),
          clock: ClockDriftTracker(),
        );
        final s = await integrity.snapshot();
        expect(s.isMock, isTrue);
        expect(s.isRooted, isFalse);
        expect(s.clockDriftS, isNull);
        expect(s.toJson()['clock_drift_s'], isNull);
      },
    );

    test('probe results are cached, then refreshed', () async {
      final probe = FakeDeviceIntegrityProbe();
      final integrity = DeviceIntegrity(
        probe: probe,
        clock: ClockDriftTracker(),
        probeCacheFor: Duration.zero,
      );
      expect((await integrity.snapshot()).isRooted, isFalse);
      probe.rooted = true;
      expect((await integrity.snapshot()).isRooted, isTrue);
    });
  });

  test('reportServerDate parses an HTTP Date header', () {
    DateTime? server;
    reportServerDate('Mon, 21 Sep 2026 03:30:00 GMT', (s, d) => server = s);
    expect(server, t0);
    reportServerDate('garbage', (s, d) => fail('not called'));
    reportServerDate(null, (s, d) => fail('not called'));
  });
}

import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'duty_harness.dart';

void main() {
  const policy = DutyPolicy();

  test('the first fix is always kept', () {
    final c = SamplingCadence(policy);
    expect(c.accept(fixAt(dutyT0)), isTrue);
    expect(c.last?.time, dutyT0);
  });

  test('moving (speed > 0.5 m/s): one fix every 2 minutes', () {
    final c = SamplingCadence(policy)..accept(fixAt(dutyT0, speedMps: 3));
    expect(
      c.accept(fixAt(dutyT0.add(const Duration(seconds: 90)), speedMps: 3)),
      isFalse,
    );
    expect(
      c.accept(fixAt(dutyT0.add(const Duration(minutes: 2)), speedMps: 3)),
      isTrue,
    );
    expect(
      c.accept(fixAt(dutyT0.add(const Duration(minutes: 3)), speedMps: 3)),
      isFalse,
    );
    expect(
      c.accept(fixAt(dutyT0.add(const Duration(minutes: 4)), speedMps: 3)),
      isTrue,
    );
  });

  test('moved > 50 m without a speed also counts as moving', () {
    final c = SamplingCadence(policy)..accept(fixAt(dutyT0));
    final t2 = dutyT0.add(const Duration(minutes: 2));
    expect(c.isMoving(fixAt(t2, east: 60)), isTrue);
    expect(c.isMoving(fixAt(t2, east: 20)), isFalse);
    expect(c.accept(fixAt(t2, east: 60)), isTrue);
  });

  test('stationary: one fix every 10 minutes even if fixes arrive every '
      '2 minutes', () {
    final c = SamplingCadence(policy)..accept(fixAt(dutyT0));
    var kept = 0;
    for (var m = 2; m <= 20; m += 2) {
      if (c.accept(fixAt(dutyT0.add(Duration(minutes: m)), east: 5))) {
        kept += 1;
      }
    }
    // Kept at +10 and +20 only.
    expect(kept, 2);
    expect(c.last?.time, dutyT0.add(const Duration(minutes: 20)));
  });

  test('a stationary officer who starts walking is sampled at the moving '
      'rate again', () {
    final c = SamplingCadence(policy)..accept(fixAt(dutyT0));
    expect(
      c.accept(fixAt(dutyT0.add(const Duration(minutes: 4)), east: 5)),
      isFalse,
    );
    // 4 minutes later, 80 m away: moving, and 4 min >= 2 min → kept.
    expect(
      c.accept(fixAt(dutyT0.add(const Duration(minutes: 4)), east: 80)),
      isTrue,
    );
  });

  test('a fix older than the last kept one is dropped (clock went back)', () {
    final c = SamplingCadence(policy)..accept(fixAt(dutyT0));
    expect(
      c.accept(fixAt(dutyT0.subtract(const Duration(minutes: 5)), east: 500)),
      isFalse,
    );
  });

  test('seed restores the reference after a restart', () {
    final c = SamplingCadence(policy)..seed(fixAt(dutyT0));
    expect(
      c.accept(fixAt(dutyT0.add(const Duration(minutes: 1)), east: 5)),
      isFalse,
    );
  });

  test('tenant intervals are honoured', () {
    final fast = DutyPolicy.fromJson(const <String, Object?>{
      'moving_interval_s': 30,
      'stationary_interval_s': 60,
    });
    final c = SamplingCadence(fast)..accept(fixAt(dutyT0));
    expect(
      c.accept(fixAt(dutyT0.add(const Duration(seconds: 30)), speedMps: 2)),
      isTrue,
    );
    expect(c.accept(fixAt(dutyT0.add(const Duration(seconds: 61)))), isFalse);
    expect(c.accept(fixAt(dutyT0.add(const Duration(seconds: 90)))), isTrue);
  });
}

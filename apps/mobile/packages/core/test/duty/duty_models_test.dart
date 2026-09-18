import 'dart:io';

import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the bundled policy text is the shared design copy, hash = sha256 of '
      'the stripped English text', () {
    final file = File('../../../../design/copy/location_policy_en.md');
    expect(file.existsSync(), isTrue, reason: 'design/copy is the shared copy');
    expect(bundledLocationPolicyEnglish.trim(), file.readAsStringSync().trim());
    final doc = LocationPolicyDoc.bundled();
    expect(doc.version, '2026-09-v1');
    expect(doc.textHash, policyTextHash(bundledLocationPolicyEnglish));
    expect(doc.textHash, hasLength(64));
    // Leading / trailing whitespace never changes the hash (API strips too).
    expect(
      policyTextHash('\n  $bundledLocationPolicyEnglish \n'),
      doc.textHash,
    );
    expect(doc.textFor('te'), doc.textFor('en'));
  });

  test('LocationPolicyDoc round-trips the wire shape', () {
    final doc = LocationPolicyDoc.fromJson(const <String, Object?>{
      'version': '2026-10-v2',
      'text_hash': 'abc',
      'text': <String, Object?>{'en': 'Hello', 'te': 'హలో', 'x': 1},
    });
    expect(doc.version, '2026-10-v2');
    expect(doc.text, <String, String>{'en': 'Hello', 'te': 'హలో'});
    expect(LocationPolicyDoc.fromJson(doc.toJson()), doc);
  });

  group('DutyPolicy', () {
    test('defaults match the tenant settings (120 / 600 / 900, 20:00 IST)', () {
      const p = DutyPolicy();
      expect(p.movingInterval, const Duration(minutes: 2));
      expect(p.stationaryInterval, const Duration(minutes: 10));
      expect(p.uploadInterval, const Duration(minutes: 15));
      expect(p.uploadOnWifiOrCharging, isTrue);
      expect(p.autoEndLocalTime, '20:00');
      expect(DutyPolicy.fromJson(const <String, Object?>{}), p);
      expect(DutyPolicy.fromJson(p.toJson()), p);
    });

    test('parses the contract shape', () {
      final p = DutyPolicy.fromJson(const <String, Object?>{
        'moving_interval_s': 60,
        'stationary_interval_s': 300,
        'upload_interval_s': 600,
        'upload_on_wifi_or_charging': false,
        'auto_end_local_time': '19:30',
      });
      expect(p.movingInterval, const Duration(minutes: 1));
      expect(p.stationaryInterval, const Duration(minutes: 5));
      expect(p.uploadInterval, const Duration(minutes: 10));
      expect(p.uploadOnWifiOrCharging, isFalse);
      expect(p.autoEndLocalTime, '19:30');
    });

    test('nextAutoEnd is 20:00 IST today, or tomorrow after 20:00', () {
      const p = DutyPolicy();
      final morning = DateTime.utc(2026, 9, 21, 3, 30); // 09:00 IST
      expect(p.nextAutoEnd(morning), DateTime.utc(2026, 9, 21, 14, 30));
      final late = DateTime.utc(2026, 9, 21, 15); // 20:30 IST
      expect(p.nextAutoEnd(late), DateTime.utc(2026, 9, 22, 14, 30));
      final exact = DateTime.utc(2026, 9, 21, 14, 30);
      expect(p.nextAutoEnd(exact), DateTime.utc(2026, 9, 22, 14, 30));
    });
  });

  test('DutyEndReason wire values', () {
    expect(DutyEndReason.autoTime.wire, 'auto_time');
    expect(DutyEndReason.parse('auto_idle'), DutyEndReason.autoIdle);
    expect(DutyEndReason.parse('nope'), isNull);
  });

  test('IntegritySnapshot contract shape and issue threshold', () {
    const clean = IntegritySnapshot(clockDriftS: 12);
    expect(clean.hasIssues, isFalse);
    expect(clean.toJson(), <String, Object?>{
      'is_mock': false,
      'is_rooted': false,
      'clock_drift_s': 12,
    });
    expect(const IntegritySnapshot(isMock: true).hasIssues, isTrue);
    expect(const IntegritySnapshot(isRooted: true).hasIssues, isTrue);
    expect(const IntegritySnapshot(clockDriftS: 301).hasIssues, isTrue);
    expect(const IntegritySnapshot(clockDriftS: -301).hasIssues, isTrue);
    expect(const IntegritySnapshot(clockJumped: true).hasIssues, isTrue);
    expect(
      IntegritySnapshot.fromJson(const <String, Object?>{
        'is_mock': true,
        'clock_drift_s': 5,
      }),
      const IntegritySnapshot(isMock: true, clockDriftS: 5),
    );
  });
}

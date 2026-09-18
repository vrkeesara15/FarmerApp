import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter_test/flutter_test.dart';

/// VV-004 on the device: `evaluateVisitProof` mirrors the server's
/// `farmerapp/visits/scoring.py` (30 / 30 / 20 / 10 / 10, override 15,
/// verified >= 70, partial 40-69, integrity zeroing) so A31 / A33 show the
/// score the server will store.
void main() {
  final checkin = DateTime.utc(2026, 9, 21, 4);
  final checkout = checkin.add(const Duration(minutes: 20));
  const point = GeoPoint(17.4, 78.4);
  final goodPhoto = PhotoEvidence(
    takenInApp: true,
    exifTime: checkin.add(const Duration(minutes: 5)),
    exifLat: 17.4001,
    exifLon: 78.4001,
  );

  VisitProof score({
    String geofence = 'inside',
    bool overrideApproved = false,
    bool confirmed = true,
    List<PhotoEvidence>? photos,
    DateTime? checkoutAt,
    bool open = false,
    DateTime? now,
    IntegritySnapshot integrity = const IntegritySnapshot(clockDriftS: 2),
    int minDurationS = 300,
  }) => evaluateVisitProof(
    geofenceResult: geofence,
    overrideApproved: overrideApproved,
    confirmed: confirmed,
    photos: photos ?? <PhotoEvidence>[goodPhoto],
    checkinAt: checkin,
    checkoutAt: open ? null : checkoutAt ?? checkout,
    now: now,
    checkinPoint: point,
    minDurationS: minDurationS,
    integrity: integrity,
  );

  test('everything present scores 100 verified', () {
    final s = score();
    expect(s.score, 100);
    expect(s.status, VisitStatus.verified);
    expect(s.components, <String, int>{
      'geofence': 30,
      'confirmation': 30,
      'photo': 20,
      'duration': 10,
      'integrity': 10,
    });
  });

  test('no farmer confirmation scores 70, still verified (boundary)', () {
    final s = score(confirmed: false);
    expect(s.score, 70);
    expect(s.status, VisitStatus.verified);
    expect(s.confirmed, isFalse);
  });

  test('approved override earns 15 of the geofence 30: 65 partial', () {
    final s = score(
      geofence: 'override',
      overrideApproved: true,
      photos: const <PhotoEvidence>[],
    );
    expect(s.score, 65);
    expect(s.status, VisitStatus.partial);
    expect(s.components['geofence'], 15);
  });

  test('pending override scores 0 for the geofence', () {
    expect(score(geofence: 'override').components['geofence'], 0);
  });

  test('outside, no photo, mock location, confirmed and long enough: 40 '
      'partial (boundary)', () {
    final s = score(
      geofence: 'outside',
      photos: const <PhotoEvidence>[],
      integrity: const IntegritySnapshot(isMock: true),
    );
    expect(s.score, 40);
    expect(s.status, VisitStatus.partial);
  });

  test('only geofence: 30 unverified', () {
    final s = score(
      confirmed: false,
      photos: const <PhotoEvidence>[],
      checkoutAt: checkin.add(const Duration(minutes: 1)),
      integrity: const IntegritySnapshot(isMock: true),
    );
    expect(s.score, 30);
    expect(s.status, VisitStatus.unverified);
  });

  test('status thresholds: 69 is partial, 39 is unverified', () {
    expect(VisitStatus.fromScore(69), VisitStatus.partial);
    expect(VisitStatus.fromScore(70), VisitStatus.verified);
    expect(VisitStatus.fromScore(39), VisitStatus.unverified);
    expect(VisitStatus.fromScore(40), VisitStatus.partial);
  });

  group('integrity zeroing', () {
    test('mock location', () {
      final s = score(integrity: const IntegritySnapshot(isMock: true));
      expect(s.components['integrity'], 0);
      expect(s.score, 90);
    });

    test('rooted device', () {
      expect(
        score(integrity: const IntegritySnapshot(isRooted: true)).score,
        90,
      );
    });

    test('drift over 300 s fails, exactly 300 s is fine', () {
      expect(
        score(integrity: const IntegritySnapshot(clockDriftS: 301)).score,
        90,
      );
      expect(
        score(integrity: const IntegritySnapshot(clockDriftS: -301)).score,
        90,
      );
      expect(
        score(integrity: const IntegritySnapshot(clockDriftS: 300)).score,
        100,
      );
    });
  });

  group('photo evidence', () {
    test('gallery photo never counts', () {
      final s = score(
        photos: <PhotoEvidence>[
          PhotoEvidence(
            takenInApp: false,
            exifTime: goodPhoto.exifTime,
            exifLat: goodPhoto.exifLat,
            exifLon: goodPhoto.exifLon,
          ),
        ],
      );
      expect(s.components['photo'], 0);
    });

    test('EXIF time outside the widened window does not count', () {
      final late = PhotoEvidence(
        takenInApp: true,
        exifTime: checkout.add(const Duration(minutes: 11)),
        exifLat: 17.4,
        exifLon: 78.4,
      );
      expect(score(photos: <PhotoEvidence>[late]).components['photo'], 0);
      final justInside = PhotoEvidence(
        takenInApp: true,
        exifTime: checkout.add(const Duration(minutes: 10)),
        exifLat: 17.4,
        exifLon: 78.4,
      );
      expect(
        score(photos: <PhotoEvidence>[justInside]).components['photo'],
        20,
      );
    });

    test('EXIF GPS farther than 150 m does not count', () {
      final far = PhotoEvidence(
        takenInApp: true,
        exifTime: goodPhoto.exifTime,
        exifLat: 17.4,
        exifLon: 78.402, // ~210 m east
      );
      expect(score(photos: <PhotoEvidence>[far]).components['photo'], 0);
    });

    test('missing EXIF does not count', () {
      const none = PhotoEvidence(takenInApp: true);
      expect(score(photos: const <PhotoEvidence>[none]).components['photo'], 0);
    });
  });

  group('open visit (A31 live view)', () {
    test('duration ticks against now before check-out', () {
      final early = score(
        open: true,
        now: checkin.add(const Duration(minutes: 2)),
      );
      expect(early.durationOk, isFalse);
      expect(early.elapsed, const Duration(minutes: 2));
      final later = score(
        open: true,
        now: checkin.add(const Duration(minutes: 5)),
      );
      expect(later.durationOk, isTrue);
      expect(later.score, 100);
    });

    test('a photo taken 15 minutes in counts with now as the window end', () {
      final s = score(
        open: true,
        now: checkin.add(const Duration(minutes: 16)),
        photos: <PhotoEvidence>[
          PhotoEvidence(
            takenInApp: true,
            exifTime: checkin.add(const Duration(minutes: 15)),
            exifLat: 17.4,
            exifLon: 78.4,
          ),
        ],
      );
      expect(s.photoOk, isTrue);
    });

    test('checklist items follow the components', () {
      final s = score(confirmed: false, photos: const <PhotoEvidence>[]);
      expect(s.geofenceOk, isTrue);
      expect(s.confirmed, isFalse);
      expect(s.photoOk, isFalse);
      expect(s.durationOk, isTrue);
      expect(s.integrityOk, isTrue);
      expect(s.missing, <String>['confirmation', 'photo']);
    });
  });
}

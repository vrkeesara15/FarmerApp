// NF-004: photos resized on device to 1280 px long edge, JPEG q80
// (~150-250 KB), EXIF time + GPS written, hard cap 300 KB with a q70/q60
// fallback ladder. Also serves FA-012 / FA-015 (EXIF stored) and FM-004.
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'synthetic_images.dart';

const int kb = 1024;

void main() {
  final takenAt = DateTime.utc(2026, 9, 18, 5, 0, 7);
  const kondapur = PhotoLocation(latitude: 17.4523, longitude: 78.3921);

  late Uint8List landscape4000;

  setUpAll(() {
    landscape4000 = jpeg(textured(4000, 3000, blades: 4000, noiseSigma: 12));
  });

  group('resize', () {
    test('4000x3000 becomes 1280x960 at q80 within the size budget', () async {
      final out = await PhotoProcessor.process(
        landscape4000,
        captureTime: takenAt,
        location: kondapur,
      );
      expect((out.width, out.height), (1280, 960));
      expect(out.quality, 80);
      expect(out.withinBudget, isTrue);
      expect(out.sizeBytes, out.bytes.length);
      expect(out.sizeBytes, lessThanOrEqualTo(250 * kb));
      expect(out.sizeBytes, greaterThan(100 * kb), reason: 'not degenerate');
      expect(out.sha256, sha256.convert(out.bytes).toString());
      // The output is a real JPEG of the reported size.
      final decoded = img.decodeJpg(out.bytes)!;
      expect((decoded.width, decoded.height), (1280, 960));
    });

    test('portrait 3000x4000 becomes 960x1280', () {
      final out = processPhotoSync(
        PhotoProcessRequest(bytes: jpeg(textured(3000, 4000, blades: 3000))),
      );
      expect((out.width, out.height), (960, 1280));
    });

    test('a small image is not upscaled', () {
      final out = processPhotoSync(
        PhotoProcessRequest(bytes: jpeg(textured(800, 600))),
      );
      expect((out.width, out.height), (800, 600));
      expect(out.quality, 80);
      expect(img.decodeJpg(out.bytes), isNotNull);
    });

    test('non-integer ratio rounds the short edge', () {
      final out = processPhotoSync(
        PhotoProcessRequest(bytes: jpeg(textured(3000, 2000, blades: 1000))),
      );
      expect((out.width, out.height), (1280, 853));
    });

    test('config can change the long edge', () {
      final out = processPhotoSync(
        PhotoProcessRequest(
          bytes: jpeg(textured(1600, 1200, blades: 800)),
          config: const PhotoProcessorConfig(maxLongEdge: 640),
        ),
      );
      expect((out.width, out.height), (640, 480));
    });

    test('PNG input is accepted', () {
      final out = processPhotoSync(
        PhotoProcessRequest(bytes: png(textured(640, 480, blades: 100))),
      );
      expect((out.width, out.height), (640, 480));
      expect(img.decodeJpg(out.bytes), isNotNull);
    });

    test('undecodable bytes throw PhotoDecodeException', () {
      expect(
        () => processPhotoSync(
          PhotoProcessRequest(bytes: Uint8List.fromList(<int>[1, 2, 3])),
        ),
        throwsA(isA<PhotoDecodeException>()),
      );
    });
  });

  group('orientation', () {
    test('EXIF orientation 6 is baked into the pixels', () {
      final out = processPhotoSync(
        PhotoProcessRequest(
          bytes: jpegWithOrientation(textured(1200, 900, blades: 300), 6),
        ),
      );
      expect((out.width, out.height), (900, 1200));
      final decoded = img.decodeJpg(out.bytes)!;
      final orientation = decoded.exif.imageIfd.orientation;
      expect(orientation == null || orientation == 1, isTrue);
    });
  });

  group('size budget', () {
    test('a photographic-noise 1280x960 image is 150-250 KB at q80', () {
      final out = processPhotoSync(
        PhotoProcessRequest(bytes: jpeg(textured(1280, 960))),
      );
      expect(out.quality, 80);
      expect(out.sizeBytes, inInclusiveRange(150 * kb, 250 * kb));
    });

    test('over 300 KB at q80 and q70 steps down to q60 and fits', () {
      // Measured: ~342 KB at q80, ~328 KB at q70, ~220 KB at q60.
      final out = processPhotoSync(
        PhotoProcessRequest(
          bytes: jpeg(textured(1280, 960, blades: 1500, noiseSigma: 18)),
        ),
      );
      expect(out.quality, 60);
      expect(out.withinBudget, isTrue);
      expect(out.sizeBytes, lessThanOrEqualTo(300 * kb));
      expect(out.sizeBytes, greaterThan(150 * kb));
    });

    test('still over the cap at q60 keeps q60 and reports it', () {
      final out = processPhotoSync(
        PhotoProcessRequest(bytes: jpeg(textured(1280, 960, noiseSigma: 60))),
      );
      expect(out.quality, 60);
      expect(out.withinBudget, isFalse);
      expect(out.sizeBytes, greaterThan(300 * kb));
    });

    test('ladder stops at the first quality that fits (config)', () {
      final bytes = jpeg(textured(1280, 960));
      final at80 = processPhotoSync(PhotoProcessRequest(bytes: bytes));
      final out = processPhotoSync(
        PhotoProcessRequest(
          bytes: bytes,
          config: PhotoProcessorConfig(hardCapBytes: at80.sizeBytes - 1),
        ),
      );
      expect(out.quality, 70);
      expect(out.sizeBytes, lessThan(at80.sizeBytes));
    });
  });

  group('EXIF', () {
    test('DateTimeOriginal and GPS round-trip through the output JPEG', () {
      final out = processPhotoSync(
        PhotoProcessRequest(
          bytes: jpeg(textured(800, 600)),
          captureTime: DateTime(2026, 9, 18, 10, 30, 7), // local time in
          location: kondapur,
        ),
      );
      expect(out.exif.takenAt, DateTime(2026, 9, 18, 10, 30, 7).toUtc());
      expect(out.exif.latitude, closeTo(17.4523, 1e-5));
      expect(out.exif.longitude, closeTo(78.3921, 1e-5));

      final read = PhotoProcessor.readExif(out.bytes);
      expect(read.takenAt, out.exif.takenAt);
      expect(read.latitude, closeTo(17.4523, 1e-5));
      expect(read.longitude, closeTo(78.3921, 1e-5));

      final raw = img.decodeJpg(out.bytes)!.exif;
      expect(
        raw.exifIfd['DateTimeOriginal'].toString(),
        DateTime(2026, 9, 18, 10, 30, 7)
            .toUtc()
            .toIso8601String()
            .substring(0, 19)
            .replaceAll('-', ':')
            .replaceAll('T', ' '),
      );
      expect(raw.exifIfd['OffsetTimeOriginal'].toString(), '+00:00');
      expect(raw.gpsIfd[0x1].toString(), 'N');
      expect(raw.gpsIfd[0x3].toString(), 'E');
    });

    test('southern / western hemisphere refs', () {
      final out = processPhotoSync(
        PhotoProcessRequest(
          bytes: jpeg(textured(400, 300, blades: 50)),
          captureTime: takenAt,
          location: const PhotoLocation(latitude: -33.8688, longitude: -70.6),
        ),
      );
      final raw = img.decodeJpg(out.bytes)!.exif;
      expect(raw.gpsIfd[0x1].toString(), 'S');
      expect(raw.gpsIfd[0x3].toString(), 'W');
      final read = PhotoProcessor.readExif(out.bytes);
      expect(read.latitude, closeTo(-33.8688, 1e-5));
      expect(read.longitude, closeTo(-70.6, 1e-5));
    });

    test('input EXIF is kept when no capture time or location is given', () {
      final first = processPhotoSync(
        PhotoProcessRequest(
          bytes: jpeg(textured(400, 300, blades: 50)),
          captureTime: takenAt,
          location: kondapur,
        ),
      );
      final second = processPhotoSync(PhotoProcessRequest(bytes: first.bytes));
      expect(second.exif.takenAt, takenAt);
      expect(second.exif.latitude, closeTo(17.4523, 1e-5));
      expect(second.exif.longitude, closeTo(78.3921, 1e-5));
    });

    test('explicit values override input EXIF', () {
      final first = processPhotoSync(
        PhotoProcessRequest(
          bytes: jpeg(textured(400, 300, blades: 50)),
          captureTime: takenAt,
          location: kondapur,
        ),
      );
      final later = takenAt.add(const Duration(minutes: 5));
      final second = processPhotoSync(
        PhotoProcessRequest(
          bytes: first.bytes,
          captureTime: later,
          location: const PhotoLocation(latitude: 12.97, longitude: 77.59),
        ),
      );
      expect(second.exif.takenAt, later);
      expect(second.exif.latitude, closeTo(12.97, 1e-5));
    });

    test('no metadata means empty exif and no GPS block', () {
      final out = processPhotoSync(
        PhotoProcessRequest(bytes: png(textured(300, 200, blades: 20))),
      );
      expect(out.exif.takenAt, isNull);
      expect(out.exif.latitude, isNull);
      expect(out.exif.longitude, isNull);
      expect(PhotoProcessor.readExif(out.bytes).isEmpty, isTrue);
    });
  });

  group('serialisation', () {
    test('ProcessedPhoto.toJson carries the upload payload fields', () {
      final out = processPhotoSync(
        PhotoProcessRequest(
          bytes: jpeg(textured(400, 300, blades: 50)),
          captureTime: takenAt,
          location: kondapur,
        ),
      );
      final json = jsonDecode(jsonEncode(out.toJson())) as Map<String, Object?>;
      expect(json['width'], 400);
      expect(json['height'], 300);
      expect(json['size_bytes'], out.sizeBytes);
      expect(json['sha256'], out.sha256);
      expect(json['quality'], 80);
      expect(json['within_budget'], true);
      final exif = json['exif']! as Map<String, Object?>;
      expect(exif['taken_at'], takenAt.toIso8601String());
      expect(exif['lat'], closeTo(17.4523, 1e-5));
      expect(exif['lon'], closeTo(78.3921, 1e-5));
      expect(json.containsKey('bytes'), isFalse, reason: 'bytes go to disk');
    });
  });
}

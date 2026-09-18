import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show compute, immutable;
import 'package:image/image.dart' as img;

/// A GPS fix attached to a photo. Only collected while on duty (FA-010).
@immutable
class PhotoLocation {
  /// Creates the fix.
  const PhotoLocation({
    required this.latitude,
    required this.longitude,
    this.accuracyMetres,
  });

  /// Degrees, negative south.
  final double latitude;

  /// Degrees, negative west.
  final double longitude;

  /// Horizontal accuracy if the platform reports it.
  final double? accuracyMetres;

  /// JSON for the outbox / upload payload.
  Map<String, Object?> toJson() => <String, Object?>{
    'lat': latitude,
    'lon': longitude,
    if (accuracyMetres != null) 'accuracy_m': accuracyMetres,
  };

  @override
  bool operator ==(Object other) =>
      other is PhotoLocation &&
      other.latitude == latitude &&
      other.longitude == longitude &&
      other.accuracyMetres == accuracyMetres;

  @override
  int get hashCode => Object.hash(latitude, longitude, accuracyMetres);
}

/// The metadata FarmerApp keeps for a photo (FA-015: EXIF time + GPS; the
/// server adds its own receive time). Mirrors the `exif_time` / `exif_point`
/// columns of the upload payload.
@immutable
class PhotoExif {
  /// Creates the metadata.
  const PhotoExif({this.takenAt, this.latitude, this.longitude});

  /// Parses the `exif` object of a [ProcessedPhoto.toJson] payload.
  factory PhotoExif.fromJson(Map<String, Object?> json) {
    final takenAt = json['taken_at'] as String?;
    return PhotoExif(
      takenAt: takenAt == null ? null : DateTime.parse(takenAt).toUtc(),
      latitude: (json['lat'] as num?)?.toDouble(),
      longitude: (json['lon'] as num?)?.toDouble(),
    );
  }

  /// No metadata.
  const PhotoExif.none() : this();

  /// Capture time in UTC (EXIF `DateTimeOriginal` + `OffsetTimeOriginal`).
  final DateTime? takenAt;

  /// EXIF GPS latitude, negative south.
  final double? latitude;

  /// EXIF GPS longitude, negative west.
  final double? longitude;

  /// True when nothing is known.
  bool get isEmpty => takenAt == null && latitude == null && longitude == null;

  /// JSON for the outbox / upload payload.
  Map<String, Object?> toJson() => <String, Object?>{
    'taken_at': takenAt?.toIso8601String(),
    'lat': latitude,
    'lon': longitude,
  };

  @override
  bool operator ==(Object other) =>
      other is PhotoExif &&
      other.takenAt == takenAt &&
      other.latitude == latitude &&
      other.longitude == longitude;

  @override
  int get hashCode => Object.hash(takenAt, latitude, longitude);
}

/// Image budget (SPEC NF-004): 1280 px long edge, JPEG q80 (~150-250 KB),
/// hard cap 300 KB with a q70 then q60 fallback.
@immutable
class PhotoProcessorConfig {
  /// Creates a config.
  const PhotoProcessorConfig({
    this.maxLongEdge = 1280,
    this.quality = 80,
    this.hardCapBytes = 300 * 1024,
    this.fallbackQualities = const <int>[70, 60],
  });

  /// The NF-004 defaults.
  static const PhotoProcessorConfig defaults = PhotoProcessorConfig();

  /// Longest edge after resizing. Smaller images are never upscaled.
  final int maxLongEdge;

  /// JPEG quality of the first encode.
  final int quality;

  /// If the output is larger than this, the quality steps down through
  /// [fallbackQualities] and stops at the first that fits.
  final int hardCapBytes;

  /// Qualities tried in order when the cap is exceeded.
  final List<int> fallbackQualities;
}

/// Input to [processPhotoSync]. Plain data so it can cross an isolate.
@immutable
class PhotoProcessRequest {
  /// Creates the request.
  const PhotoProcessRequest({
    required this.bytes,
    this.captureTime,
    this.location,
    this.config = PhotoProcessorConfig.defaults,
  });

  /// Encoded image bytes from the in-app camera (JPEG or PNG).
  final Uint8List bytes;

  /// Capture time; falls back to the input EXIF, else none.
  final DateTime? captureTime;

  /// Capture location; falls back to the input EXIF GPS, else none.
  final PhotoLocation? location;

  /// Budget settings.
  final PhotoProcessorConfig config;
}

/// The device-side result: what gets written to disk and queued for upload.
@immutable
class ProcessedPhoto {
  /// Creates the result.
  const ProcessedPhoto({
    required this.bytes,
    required this.width,
    required this.height,
    required this.sha256,
    required this.quality,
    required this.withinBudget,
    required this.exif,
  });

  /// JPEG bytes (EXIF time + GPS embedded when known).
  final Uint8List bytes;

  /// Pixel width after orientation correction and resizing.
  final int width;

  /// Pixel height after orientation correction and resizing.
  final int height;

  /// Hex SHA-256 of [bytes]; the upload and audit identity of the photo.
  final String sha256;

  /// Final JPEG quality (80, or 70 / 60 after the fallback ladder).
  final int quality;

  /// False when even the lowest fallback quality is above the hard cap.
  final bool withinBudget;

  /// Metadata embedded in [bytes] and sent alongside it.
  final PhotoExif exif;

  /// Size of [bytes].
  int get sizeBytes => bytes.length;

  /// Upload payload fields (no bytes: those go to the file store).
  Map<String, Object?> toJson() => <String, Object?>{
    'width': width,
    'height': height,
    'size_bytes': sizeBytes,
    'sha256': sha256,
    'quality': quality,
    'within_budget': withinBudget,
    'exif': exif.toJson(),
  };
}

/// Thrown when the input bytes are not a decodable image.
class PhotoDecodeException implements Exception {
  /// Creates the exception.
  const PhotoDecodeException([this.message = 'Could not decode image']);

  /// Human-readable reason (not shown to users).
  final String message;

  @override
  String toString() => 'PhotoDecodeException: $message';
}

/// Shared on-device photo pipeline for FA-012 / FA-015 / FM-004 (NF-004).
///
/// Decode, correct EXIF orientation, resize to the long-edge budget, encode
/// JPEG at q80 (4:2:0), write EXIF `DateTimeOriginal` + GPS, and hash. Runs
/// on a background isolate through [compute].
abstract final class PhotoProcessor {
  /// Processes [bytes] off the UI thread.
  static Future<ProcessedPhoto> process(
    Uint8List bytes, {
    DateTime? captureTime,
    PhotoLocation? location,
    PhotoProcessorConfig config = PhotoProcessorConfig.defaults,
  }) {
    return compute(
      processPhotoSync,
      PhotoProcessRequest(
        bytes: bytes,
        captureTime: captureTime,
        location: location,
        config: config,
      ),
      debugLabel: 'PhotoProcessor.process',
    );
  }

  /// Reads the FarmerApp metadata back out of a JPEG (full decode; cheap at
  /// 1280 px, avoid on raw camera output).
  static PhotoExif readExif(Uint8List bytes) {
    final decoded = decodeImageOrThrow(bytes, jpegOnly: true);
    return _readExif(decoded.exif);
  }
}

/// Decodes [bytes] or throws [PhotoDecodeException]. The `image` decoders
/// can throw range errors while probing malformed input; those are folded in.
img.Image decodeImageOrThrow(Uint8List bytes, {bool jpegOnly = false}) {
  img.Image? decoded;
  try {
    decoded = jpegOnly ? img.decodeJpg(bytes) : img.decodeImage(bytes);
  } on Exception catch (e) {
    throw PhotoDecodeException('$e');
  } on Error catch (e) {
    throw PhotoDecodeException('$e');
  }
  if (decoded == null) throw const PhotoDecodeException();
  return decoded;
}

/// The synchronous pipeline behind [PhotoProcessor.process]. Public so tests
/// and isolates can call it; app code should use [PhotoProcessor.process].
ProcessedPhoto processPhotoSync(PhotoProcessRequest request) {
  final config = request.config;
  final decoded = decodeImageOrThrow(request.bytes);
  final inputExif = _readExif(decoded.exif);

  var image = decoded;
  final orientation = image.exif.imageIfd.orientation;
  if (orientation != null && orientation != 1) {
    image = img.bakeOrientation(image);
  }
  final longEdge = math.max(image.width, image.height);
  if (longEdge > config.maxLongEdge) {
    final scale = config.maxLongEdge / longEdge;
    image = img.copyResize(
      image,
      width: (image.width * scale).round(),
      height: (image.height * scale).round(),
      interpolation: img.Interpolation.average,
    );
  }
  if (image.hasPalette ||
      image.format != img.Format.uint8 ||
      image.numChannels != 3) {
    image = image.convert(format: img.Format.uint8, numChannels: 3);
  }

  final exif = PhotoExif(
    takenAt: request.captureTime?.toUtc() ?? inputExif.takenAt,
    latitude: request.location?.latitude ?? inputExif.latitude,
    longitude: request.location?.longitude ?? inputExif.longitude,
  );
  // A fresh EXIF block: orientation is baked in, thumbnails are dropped.
  image.exif = _buildExif(exif);

  Uint8List encode(int quality) =>
      img.encodeJpg(image, quality: quality, chroma: img.JpegChroma.yuv420);

  var quality = config.quality;
  var bytes = encode(quality);
  var withinBudget = bytes.length <= config.hardCapBytes;
  for (final fallback in config.fallbackQualities) {
    if (withinBudget) break;
    quality = fallback;
    bytes = encode(quality);
    withinBudget = bytes.length <= config.hardCapBytes;
  }

  return ProcessedPhoto(
    bytes: bytes,
    width: image.width,
    height: image.height,
    sha256: sha256.convert(bytes).toString(),
    quality: quality,
    withinBudget: withinBudget,
    exif: exif,
  );
}

// EXIF tag ids (image package only names the IFD0/EXIF tags).
const int _tagDateTime = 0x0132;
const int _tagDateTimeOriginal = 0x9003;
const int _tagDateTimeDigitized = 0x9004;
const int _tagOffsetTime = 0x9010;
const int _tagOffsetTimeOriginal = 0x9011;
const int _gpsVersionId = 0x0;
const int _gpsLatitudeRef = 0x1;
const int _gpsLatitude = 0x2;
const int _gpsLongitudeRef = 0x3;
const int _gpsLongitude = 0x4;

final RegExp _exifDateTime = RegExp(
  r'^(\d{4}):(\d{2}):(\d{2}) (\d{2}):(\d{2}):(\d{2})$',
);
final RegExp _exifOffset = RegExp(r'^([+-])(\d{2}):(\d{2})$');

img.ExifData _buildExif(PhotoExif exif) {
  final data = img.ExifData();
  final takenAt = exif.takenAt;
  if (takenAt != null) {
    final stamp = _formatExifDateTime(takenAt.toUtc());
    data.imageIfd[_tagDateTime] = img.IfdValueAscii(stamp);
    data.exifIfd[_tagDateTimeOriginal] = img.IfdValueAscii(stamp);
    data.exifIfd[_tagDateTimeDigitized] = img.IfdValueAscii(stamp);
    data.exifIfd[_tagOffsetTime] = img.IfdValueAscii('+00:00');
    data.exifIfd[_tagOffsetTimeOriginal] = img.IfdValueAscii('+00:00');
  }
  final lat = exif.latitude;
  final lon = exif.longitude;
  if (lat != null && lon != null) {
    final gps = data.gpsIfd;
    gps[_gpsVersionId] = img.IfdByteValue.list(
      Uint8List.fromList(const <int>[2, 3, 0, 0]),
    );
    gps[_gpsLatitudeRef] = img.IfdValueAscii(lat < 0 ? 'S' : 'N');
    gps[_gpsLatitude] = _degreesMinutesSeconds(lat.abs());
    gps[_gpsLongitudeRef] = img.IfdValueAscii(lon < 0 ? 'W' : 'E');
    gps[_gpsLongitude] = _degreesMinutesSeconds(lon.abs());
  }
  return data;
}

PhotoExif _readExif(img.ExifData data) {
  if (data.isEmpty) return const PhotoExif.none();
  DateTime? takenAt;
  final stamp =
      data.exifIfd[_tagDateTimeOriginal]?.toString() ??
      data.imageIfd[_tagDateTime]?.toString();
  if (stamp != null) {
    takenAt = _parseExifDateTime(
      stamp,
      data.exifIfd[_tagOffsetTimeOriginal]?.toString(),
    );
  }
  final gps = data.gpsIfd;
  final lat = _fromDegreesMinutesSeconds(
    gps[_gpsLatitude],
    negative: gps[_gpsLatitudeRef]?.toString().trim() == 'S',
  );
  final lon = _fromDegreesMinutesSeconds(
    gps[_gpsLongitude],
    negative: gps[_gpsLongitudeRef]?.toString().trim() == 'W',
  );
  return PhotoExif(takenAt: takenAt, latitude: lat, longitude: lon);
}

String _two(int v) => v.toString().padLeft(2, '0');

String _formatExifDateTime(DateTime utc) =>
    '${utc.year.toString().padLeft(4, '0')}:${_two(utc.month)}:'
    '${_two(utc.day)} ${_two(utc.hour)}:${_two(utc.minute)}:'
    '${_two(utc.second)}';

/// Parses `YYYY:MM:DD HH:MM:SS` with an optional `+HH:MM` offset. Without an
/// offset (typical camera output) the stamp is taken as device local time.
DateTime? _parseExifDateTime(String stamp, String? offset) {
  final m = _exifDateTime.firstMatch(stamp.trim());
  if (m == null) return null;
  final parts = List<int>.generate(6, (i) => int.parse(m.group(i + 1)!));
  final o = offset == null ? null : _exifOffset.firstMatch(offset.trim());
  if (o == null) {
    return DateTime(
      parts[0],
      parts[1],
      parts[2],
      parts[3],
      parts[4],
      parts[5],
    ).toUtc();
  }
  final sign = o.group(1) == '-' ? -1 : 1;
  final shift = Duration(
    hours: int.parse(o.group(2)!),
    minutes: int.parse(o.group(3)!),
  );
  return DateTime.utc(
    parts[0],
    parts[1],
    parts[2],
    parts[3],
    parts[4],
    parts[5],
  ).subtract(shift * sign);
}

/// Degrees / minutes / seconds as three EXIF rationals; seconds to 1/10000.
img.IfdValueRational _degreesMinutesSeconds(double value) {
  final degrees = value.floor();
  final minutesFull = (value - degrees) * 60;
  final minutes = minutesFull.floor();
  final seconds = ((minutesFull - minutes) * 60 * 10000).round();
  // `Rational` is not exported by package:image; the element type is
  // inferred from `toRational()`.
  final parts = [
    img.IfdValueRational(degrees, 1).toRational(),
    img.IfdValueRational(minutes, 1).toRational(),
    img.IfdValueRational(seconds, 10000).toRational(),
  ];
  return img.IfdValueRational.list(parts);
}

double? _fromDegreesMinutesSeconds(
  img.IfdValue? value, {
  bool negative = false,
}) {
  if (value == null || value.length < 3) return null;
  var degrees = 0.0;
  for (var i = 0; i < 3; i++) {
    final r = value.toRational(i);
    if (r.denominator == 0) return null;
    degrees += r.numerator / r.denominator / math.pow(60, i);
  }
  return negative ? -degrees : degrees;
}

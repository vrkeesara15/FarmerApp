import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute, immutable;
import 'package:image/image.dart' as img;

import 'photo_processor.dart' show decodeImageOrThrow;

/// Retake tip keys returned by the quality gate (FM-004: "blurry photo
/// rejected with retake tip"). Mapped to ARB strings by `PhotoTipText`.
abstract final class PhotoTipKeys {
  /// Hold the phone steady and focus on the leaf.
  static const String blurry = 'photo.tip.blurry';

  /// Move into better light.
  static const String dark = 'photo.tip.dark';

  /// Nothing to fix.
  static const String ok = 'photo.tip.ok';

  /// Every key, for exhaustive UI mapping tests.
  static const List<String> all = <String>[blurry, dark, ok];
}

/// Thresholds for [LaplacianQualityModel].
///
/// Calibrated on the synthetic set in `test/photo/photo_quality_test.dart`
/// (320 px analysis edge, luminance 0..255):
///   * sharp textured scene: variance of Laplacian ~245-330
///   * same scene, gaussian radius 3: ~90 (accepted)
///   * same scene, gaussian radius 6: ~17-20 (rejected)
/// Real field photos will re-tune this once M6 has a labelled corpus.
@immutable
class PhotoQualityConfig {
  /// Creates a config.
  const PhotoQualityConfig({
    this.blurThreshold = 40,
    this.darkThreshold = 0.15,
    this.analysisEdge = 320,
  });

  /// The calibrated defaults.
  static const PhotoQualityConfig defaults = PhotoQualityConfig();

  /// Variance of the Laplacian below which a frame counts as blurry.
  final double blurThreshold;

  /// Mean luminance (0..1) below which a frame counts as too dark.
  final double darkThreshold;

  /// Long edge of the grayscale working copy.
  final int analysisEdge;
}

/// Outcome of the on-device gate.
@immutable
class PhotoQualityResult {
  /// Creates the result.
  const PhotoQualityResult({
    required this.isBlurry,
    required this.blurScore,
    required this.isTooDark,
    required this.brightness,
    required this.tipKey,
  });

  /// Parses [toJson] output.
  factory PhotoQualityResult.fromJson(Map<String, Object?> json) {
    return PhotoQualityResult(
      isBlurry: json['is_blurry']! as bool,
      blurScore: (json['blur_score']! as num).toDouble(),
      isTooDark: json['is_too_dark']! as bool,
      brightness: (json['brightness']! as num).toDouble(),
      tipKey: json['tip_key']! as String,
    );
  }

  /// Below the blur threshold.
  final bool isBlurry;

  /// Variance of the Laplacian (higher is sharper).
  final double blurScore;

  /// Below the dark threshold.
  final bool isTooDark;

  /// Mean luminance, 0..1.
  final double brightness;

  /// One of [PhotoTipKeys]; dark wins over blurry because a dark frame has
  /// no edges to measure.
  final String tipKey;

  /// True when the photo may be used.
  bool get isAcceptable => !isBlurry && !isTooDark;

  /// JSON for the outbox and diagnosis analytics (AN-007).
  Map<String, Object?> toJson() => <String, Object?>{
    'is_blurry': isBlurry,
    'blur_score': blurScore,
    'is_too_dark': isTooDark,
    'brightness': brightness,
    'tip_key': tipKey,
  };

  @override
  bool operator ==(Object other) =>
      other is PhotoQualityResult &&
      other.isBlurry == isBlurry &&
      other.blurScore == blurScore &&
      other.isTooDark == isTooDark &&
      other.brightness == brightness &&
      other.tipKey == tipKey;

  @override
  int get hashCode =>
      Object.hash(isBlurry, blurScore, isTooDark, brightness, tipKey);
}

/// The on-device photo gate (DX-001). The heuristic below is the default;
/// the M6 TFLite crop/leaf/quality classifier implements the same interface.
abstract interface class OnDeviceQualityModel {
  /// Evaluates encoded image bytes (normally the [ProcessedPhoto] output).
  Future<PhotoQualityResult> evaluate(Uint8List bytes);
}

@immutable
class _QualityRequest {
  const _QualityRequest(this.bytes, this.config);

  final Uint8List bytes;
  final PhotoQualityConfig config;
}

PhotoQualityResult _evaluateEntry(_QualityRequest request) =>
    PhotoQualityCheck.evaluateSync(request.bytes, config: request.config);

/// Variance-of-Laplacian blur check plus mean-luminance darkness check on a
/// downscaled grayscale copy, run off the UI thread.
class LaplacianQualityModel implements OnDeviceQualityModel {
  /// Creates the model.
  const LaplacianQualityModel({this.config = PhotoQualityConfig.defaults});

  /// Thresholds.
  final PhotoQualityConfig config;

  @override
  Future<PhotoQualityResult> evaluate(Uint8List bytes) {
    return compute(
      _evaluateEntry,
      _QualityRequest(bytes, config),
      debugLabel: 'LaplacianQualityModel.evaluate',
    );
  }
}

/// Entry point for FM-004 / DX-001 callers.
abstract final class PhotoQualityCheck {
  /// The model used when none is passed.
  static const OnDeviceQualityModel defaultModel = LaplacianQualityModel();

  /// Evaluates [bytes] with [model] (default: [LaplacianQualityModel]).
  static Future<PhotoQualityResult> evaluate(
    Uint8List bytes, {
    OnDeviceQualityModel? model,
  }) => (model ?? defaultModel).evaluate(bytes);

  /// Synchronous heuristic; public for tests and isolates.
  static PhotoQualityResult evaluateSync(
    Uint8List bytes, {
    PhotoQualityConfig config = PhotoQualityConfig.defaults,
  }) {
    final decoded = decodeImageOrThrow(bytes);
    final lum = _luminance(decoded, config.analysisEdge);
    final brightness = _mean(lum.values) / 255;
    final blurScore = _laplacianVariance(lum);
    final isTooDark = brightness < config.darkThreshold;
    final isBlurry = blurScore < config.blurThreshold;
    return PhotoQualityResult(
      isBlurry: isBlurry,
      blurScore: blurScore,
      isTooDark: isTooDark,
      brightness: brightness,
      tipKey: isTooDark
          ? PhotoTipKeys.dark
          : isBlurry
          ? PhotoTipKeys.blurry
          : PhotoTipKeys.ok,
    );
  }
}

class _Luminance {
  const _Luminance(this.width, this.height, this.values);

  final int width;
  final int height;
  final Float64List values;
}

/// Grayscale copy with the long edge at most [edge] px, luminance 0..255.
_Luminance _luminance(img.Image source, int edge) {
  final longEdge = source.width > source.height ? source.width : source.height;
  var image = source;
  if (longEdge > edge) {
    final scale = edge / longEdge;
    image = img.copyResize(
      source,
      width: (source.width * scale).round().clamp(1, longEdge),
      height: (source.height * scale).round().clamp(1, longEdge),
      interpolation: img.Interpolation.average,
    );
  }
  final w = image.width;
  final h = image.height;
  final values = Float64List(w * h);
  var i = 0;
  for (final p in image) {
    values[i++] = p.luminanceNormalized * 255;
  }
  return _Luminance(w, h, values);
}

double _mean(Float64List values) {
  if (values.isEmpty) return 0;
  var sum = 0.0;
  for (final v in values) {
    sum += v;
  }
  return sum / values.length;
}

/// Variance of the 4-neighbour Laplacian over interior pixels.
double _laplacianVariance(_Luminance lum) {
  final w = lum.width;
  final h = lum.height;
  final v = lum.values;
  if (w < 3 || h < 3) return 0;
  var sum = 0.0;
  var sumSq = 0.0;
  final n = (w - 2) * (h - 2);
  for (var y = 1; y < h - 1; y++) {
    final row = y * w;
    for (var x = 1; x < w - 1; x++) {
      final l =
          v[row - w + x] +
          v[row + w + x] +
          v[row + x - 1] +
          v[row + x + 1] -
          4 * v[row + x];
      sum += l;
      sumSq += l * l;
    }
  }
  final mean = sum / n;
  return sumSq / n - mean * mean;
}

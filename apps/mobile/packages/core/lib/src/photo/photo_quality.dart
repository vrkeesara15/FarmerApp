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

  /// No leaf in the frame (DX-001 plant check): point the camera at the
  /// leaf.
  static const String notPlant = 'photo.tip.not_plant';

  /// Nothing to fix.
  static const String ok = 'photo.tip.ok';

  /// Every key, for exhaustive UI mapping tests.
  static const List<String> all = <String>[blurry, dark, notPlant, ok];
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
///
/// The Laplacian heuristic fills the first five fields; the DX-001 model
/// ([TfliteQualityModel]) also fills the plant check, the crop guess and
/// its provenance (ml/ondevice/INTEGRATION.md §4).
@immutable
class PhotoQualityResult {
  /// Creates the result.
  const PhotoQualityResult({
    required this.isBlurry,
    required this.blurScore,
    required this.isTooDark,
    required this.brightness,
    required this.tipKey,
    this.isPlant = true,
    this.plantScore,
    this.cropCode,
    this.cropScore,
    this.cropScores = const <String, double>{},
    this.qualityScores = const <String, double>{},
    this.modelVersion = heuristicModelVersion,
    this.usedFallback = false,
    this.latencyMs,
  });

  /// Parses [toJson] output.
  factory PhotoQualityResult.fromJson(Map<String, Object?> json) {
    Map<String, double> scores(Object? raw) => raw is Map
        ? <String, double>{
            for (final e in raw.entries)
              if (e.value is num) '${e.key}': (e.value! as num).toDouble(),
          }
        : const <String, double>{};
    return PhotoQualityResult(
      isBlurry: json['is_blurry']! as bool,
      blurScore: (json['blur_score']! as num).toDouble(),
      isTooDark: json['is_too_dark']! as bool,
      brightness: (json['brightness']! as num).toDouble(),
      tipKey: json['tip_key']! as String,
      isPlant: json['is_plant'] as bool? ?? true,
      plantScore: (json['plant_score'] as num?)?.toDouble(),
      cropCode: json['crop_code'] as String?,
      cropScore: (json['crop_score'] as num?)?.toDouble(),
      cropScores: scores(json['crop_scores']),
      qualityScores: scores(json['quality_scores']),
      modelVersion: (json['model_version'] as String?) ?? heuristicModelVersion,
      usedFallback: json['used_fallback'] as bool? ?? false,
      latencyMs: (json['latency_ms'] as num?)?.toInt(),
    );
  }

  /// `on_device_model` of a result from the heuristic (INTEGRATION.md §6).
  static const String heuristicModelVersion = 'heuristic-laplacian-v1';

  /// Below the blur threshold (heuristic) or `quality_blurry` over its
  /// threshold (model).
  final bool isBlurry;

  /// Variance of the Laplacian (higher is sharper) for the heuristic;
  /// p(blurry) for the model.
  final double blurScore;

  /// Below the dark threshold.
  final bool isTooDark;

  /// Mean luminance, 0..1.
  final double brightness;

  /// One of [PhotoTipKeys]; dark wins over blurry because a dark frame has
  /// no edges to measure, and both win over the plant check.
  final String tipKey;

  /// A leaf or plant is in the frame (always true for the heuristic, which
  /// cannot tell).
  final bool isPlant;

  /// p(plant) from the model; null for the heuristic.
  final double? plantScore;

  /// On-device crop guess (a catalogue crop code or `other`) at or above
  /// the model's `crop_min`; null below it and for the heuristic. A hint
  /// only: the crop the user picks stays the source of truth.
  final String? cropCode;

  /// Probability of [cropCode] (the top crop score even when below the
  /// threshold); null for the heuristic.
  final double? cropScore;

  /// Every crop probability from the model.
  final Map<String, double> cropScores;

  /// `ok` / `blurry` / `dark` probabilities from the model.
  final Map<String, double> qualityScores;

  /// `crop_quality` model version, or [heuristicModelVersion].
  final String modelVersion;

  /// The model failed to load or run and the heuristic answered.
  final bool usedFallback;

  /// Time spent in the check (inference or heuristic).
  final int? latencyMs;

  /// True when the photo may be used.
  bool get isAcceptable => !isBlurry && !isTooDark && isPlant;

  /// The `quality` object of a `POST /v1/diagnoses` image
  /// (`PhotoQualityIn`: exactly these four fields).
  Map<String, Object?> toDiagnosisQuality() => <String, Object?>{
    'passed': isAcceptable,
    'blur_score': blurScore < 0 ? 0 : blurScore,
    'brightness': brightness.clamp(0, 1),
    'plant_present': isPlant,
  };

  /// A copy with the check's duration.
  PhotoQualityResult withLatency(int ms) => PhotoQualityResult(
    isBlurry: isBlurry,
    blurScore: blurScore,
    isTooDark: isTooDark,
    brightness: brightness,
    tipKey: tipKey,
    isPlant: isPlant,
    plantScore: plantScore,
    cropCode: cropCode,
    cropScore: cropScore,
    cropScores: cropScores,
    qualityScores: qualityScores,
    modelVersion: modelVersion,
    usedFallback: usedFallback,
    latencyMs: ms,
  );

  /// A copy marked as a fallback answer.
  PhotoQualityResult asFallback() => PhotoQualityResult(
    isBlurry: isBlurry,
    blurScore: blurScore,
    isTooDark: isTooDark,
    brightness: brightness,
    tipKey: tipKey,
    isPlant: isPlant,
    plantScore: plantScore,
    cropCode: cropCode,
    cropScore: cropScore,
    cropScores: cropScores,
    qualityScores: qualityScores,
    modelVersion: modelVersion,
    usedFallback: true,
    latencyMs: latencyMs,
  );

  /// JSON for the outbox and diagnosis analytics (AN-007).
  Map<String, Object?> toJson() => <String, Object?>{
    'is_blurry': isBlurry,
    'blur_score': blurScore,
    'is_too_dark': isTooDark,
    'brightness': brightness,
    'tip_key': tipKey,
    'is_plant': isPlant,
    'plant_score': plantScore,
    'crop_code': cropCode,
    'crop_score': cropScore,
    if (cropScores.isNotEmpty) 'crop_scores': cropScores,
    if (qualityScores.isNotEmpty) 'quality_scores': qualityScores,
    'model_version': modelVersion,
    'used_fallback': usedFallback,
    'latency_ms': latencyMs,
  };

  @override
  bool operator ==(Object other) =>
      other is PhotoQualityResult &&
      other.isBlurry == isBlurry &&
      other.blurScore == blurScore &&
      other.isTooDark == isTooDark &&
      other.brightness == brightness &&
      other.tipKey == tipKey &&
      other.isPlant == isPlant &&
      other.plantScore == plantScore &&
      other.cropCode == cropCode &&
      other.cropScore == cropScore &&
      other.modelVersion == modelVersion &&
      other.usedFallback == usedFallback;

  @override
  int get hashCode => Object.hash(
    isBlurry,
    blurScore,
    isTooDark,
    brightness,
    tipKey,
    isPlant,
    plantScore,
    cropCode,
    cropScore,
    modelVersion,
    usedFallback,
  );
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

/// Answers queued results in order, then [otherwise] (tests, previews).
class ScriptedQualityModel implements OnDeviceQualityModel {
  /// Creates the model.
  ScriptedQualityModel([Iterable<PhotoQualityResult> results = const []])
    : _queue = <PhotoQualityResult>[...results];

  final List<PhotoQualityResult> _queue;

  /// Answer once the queue is empty.
  PhotoQualityResult otherwise = good;

  /// Photos evaluated.
  int calls = 0;

  /// Queues another answer.
  void enqueue(PhotoQualityResult r) => _queue.add(r);

  /// A good leaf photo (model answer, crop guess `chilli` 0.93).
  static const PhotoQualityResult good = PhotoQualityResult(
    isBlurry: false,
    blurScore: 0.02,
    isTooDark: false,
    brightness: 0.46,
    tipKey: PhotoTipKeys.ok,
    plantScore: 0.99,
    cropCode: 'chilli',
    cropScore: 0.93,
    modelVersion: 'ondevice-v1.0',
  );

  /// A blurry photo.
  static const PhotoQualityResult blurry = PhotoQualityResult(
    isBlurry: true,
    blurScore: 0.81,
    isTooDark: false,
    brightness: 0.44,
    tipKey: PhotoTipKeys.blurry,
    plantScore: 0.9,
    modelVersion: 'ondevice-v1.0',
  );

  /// A dark photo.
  static const PhotoQualityResult dark = PhotoQualityResult(
    isBlurry: false,
    blurScore: 0.1,
    isTooDark: true,
    brightness: 0.05,
    tipKey: PhotoTipKeys.dark,
    plantScore: 0.6,
    modelVersion: 'ondevice-v1.0',
  );

  /// No leaf in the frame.
  static const PhotoQualityResult notPlant = PhotoQualityResult(
    isBlurry: false,
    blurScore: 0.03,
    isTooDark: false,
    brightness: 0.5,
    tipKey: PhotoTipKeys.notPlant,
    isPlant: false,
    plantScore: 0.04,
    modelVersion: 'ondevice-v1.0',
  );

  @override
  Future<PhotoQualityResult> evaluate(Uint8List bytes) async {
    calls += 1;
    return _queue.isEmpty ? otherwise : _queue.removeAt(0);
  }
}

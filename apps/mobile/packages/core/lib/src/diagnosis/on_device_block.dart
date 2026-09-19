import '../photo/photo_quality.dart';
import '../photo/tflite_quality_model.dart' show QualityModelMetadata;

/// The `on_device` block of `POST /v1/diagnoses` and of the sync
/// `diagnosis` create op (DX-001 scores kept as DX-005 provenance;
/// ml/ondevice/INTEGRATION.md §5 / §6, `OnDeviceIn` in the API spec).
///
/// Built only from the gate results of the accepted photos, so it carries
/// scores and model provenance and nothing else — no location, no
/// identity; the server refuses any other key. Model name, version and
/// SHA-256 come from the model asset metadata (via [PhotoQualityResult]).
abstract final class OnDeviceBlock {
  /// `on_device.fallback` when the Laplacian heuristic answered.
  static const String laplacianFallback = 'laplacian';

  /// Most crop scores the server takes (`maxProperties`).
  static const int maxCropScores = 16;

  static const int _maxName = 64;
  static const int _maxLatencyMs = 600000;
  static const List<String> _qualityKeys = <String>['ok', 'blurry', 'dark'];
  static final RegExp _sha256 = RegExp(r'^[0-9a-f]{64}$');

  /// The block for the gate results of the accepted photos (null when
  /// there are none).
  ///
  /// Photos the model scored give the model block, their scores averaged;
  /// when the model answered none of them (not available, or the heuristic
  /// alone is wired), the fallback block: `fallback: "laplacian"` plus the
  /// heuristic's blur score and brightness.
  static Map<String, Object?>? fromResults(
    Iterable<PhotoQualityResult> results,
  ) {
    final all = results.toList();
    if (all.isEmpty) return null;
    final model = all.where((r) => !r.isHeuristic).toList();
    return model.isNotEmpty ? _model(model) : _fallback(all);
  }

  static Map<String, Object?> _model(List<PhotoQualityResult> runs) {
    final first = runs.first;
    final sha = first.modelSha256;
    final plant = _mean(runs.map((r) => r.plantScore));
    final quality = <String, Object?>{
      for (final k in _qualityKeys)
        if (_mean(runs.map((r) => r.qualityScores[k])) case final v?) k: _p(v),
    };
    final crops = <String, double>{};
    final codes = <String>{
      for (final r in runs)
        for (final c in r.cropScores.keys)
          if (c.isNotEmpty && c.length <= 32) c,
    };
    for (final c in codes) {
      crops[c] = _p(_mean(runs.map((r) => r.cropScores[c] ?? 0))!);
    }
    final kept = crops.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final keep = kept.take(maxCropScores).map((e) => e.key).toSet();
    return <String, Object?>{
      'model': _name(first.modelName),
      'model_version': _cap(first.modelVersion),
      if (sha != null && _sha256.hasMatch(sha)) 'model_sha256': sha,
      if (plant != null) 'plant_score': _p(plant),
      if (quality.isNotEmpty) 'quality': quality,
      if (crops.isNotEmpty)
        'crop_scores': <String, Object?>{
          for (final e in crops.entries)
            if (keep.contains(e.key)) e.key: e.value,
        },
      'latency_ms': ?_latency(runs),
    };
  }

  static Map<String, Object?> _fallback(List<PhotoQualityResult> runs) {
    final first = runs.first;
    final blur = _mean(runs.map((r) => r.blurScore < 0 ? 0.0 : r.blurScore));
    final brightness = _mean(runs.map((r) => r.brightness));
    return <String, Object?>{
      'model': _name(runs.map((r) => r.modelName).nonNulls.firstOrNull),
      'model_version': _cap(first.modelVersion),
      'fallback': laplacianFallback,
      'heuristic': <String, Object?>{
        'blur_score': _round(blur!),
        'brightness': _p(brightness!),
      },
      'latency_ms': ?_latency(runs),
    };
  }

  static String _name(String? name) =>
      _cap(name ?? QualityModelMetadata.defaultModelName);

  static String _cap(String s) =>
      s.length <= _maxName ? s : s.substring(0, _maxName);

  static int? _latency(List<PhotoQualityResult> runs) {
    final ms = _mean(runs.map((r) => r.latencyMs?.toDouble()));
    return ms?.round().clamp(0, _maxLatencyMs);
  }

  static double? _mean(Iterable<double?> values) {
    final present = values.nonNulls.toList();
    if (present.isEmpty) return null;
    return present.fold<double>(0, (a, b) => a + b) / present.length;
  }

  /// A probability: 4 decimals, within 0..1.
  static double _p(double v) => _round(v).clamp(0.0, 1.0);

  static double _round(double v) => (v * 10000).round() / 10000;
}

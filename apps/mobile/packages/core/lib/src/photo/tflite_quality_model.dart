import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show compute, immutable, listEquals;
import 'package:flutter/services.dart' show AssetBundle, rootBundle;
import 'package:image/image.dart' as img;

import 'photo_processor.dart' show decodeImageOrThrow;
import 'photo_quality.dart';

/// DX-001 `crop_quality` model contract, read from the
/// `crop_quality_v1.metadata.json` asset shipped next to the model
/// (ml/ondevice/INTEGRATION.md: labels, layout and thresholds come from the
/// file, so a threshold change is a new asset, not a code change).
@immutable
class QualityModelMetadata {
  /// Creates the metadata.
  const QualityModelMetadata({
    required this.modelName,
    required this.modelVersion,
    required this.sha256,
    required this.sizeBytes,
    required this.inputShape,
    required this.inputDtype,
    required this.outputShape,
    required this.outputDtype,
    required this.layout,
    required this.qualityLabels,
    required this.cropLabels,
    required this.plantMin,
    required this.blurryMin,
    required this.darkMin,
    required this.cropMin,
    this.source = 'public',
  });

  /// Parses `metadata.json`.
  factory QualityModelMetadata.fromJson(Map<String, Object?> json) {
    Map<String, Object?> map(Object? v) =>
        v is Map ? Map<String, Object?>.from(v) : const <String, Object?>{};
    List<int> ints(Object? v) => <int>[
      if (v is List)
        for (final e in v) (e! as num).toInt(),
    ];
    List<String> strings(Object? v) => <String>[
      if (v is List)
        for (final e in v) '$e',
    ];
    final input = map(json['input']);
    final output = map(json['output']);
    final labels = map(json['labels']);
    final t = map(json['thresholds']);
    double th(String key, double d) => (t[key] as num?)?.toDouble() ?? d;
    return QualityModelMetadata(
      modelName: (json['model_name'] as String?) ?? 'crop_quality',
      modelVersion: json['model_version']! as String,
      sha256: json['sha256']! as String,
      sizeBytes: (json['size_bytes'] as num?)?.toInt() ?? 0,
      inputShape: ints(input['shape']),
      inputDtype: (input['dtype'] as String?) ?? 'uint8',
      outputShape: ints(output['shape']),
      outputDtype: (output['dtype'] as String?) ?? 'float32',
      layout: strings(output['layout']),
      qualityLabels: strings(labels['quality']),
      cropLabels: strings(labels['crop']),
      plantMin: th('plant_min', 0.5),
      blurryMin: th('blurry_min', 0.5),
      darkMin: th('dark_min', 0.5),
      cropMin: th('crop_min', 0.6),
      source: (json['source'] as String?) ?? 'public',
    );
  }

  /// `crop_quality`.
  final String modelName;

  /// `ondevice-v1.0`; sent as `on_device_model` (DX-005).
  final String modelVersion;

  /// Hex SHA-256 of the `.tflite` file; the loader refuses any other file.
  final String sha256;

  /// Size of the `.tflite` file.
  final int sizeBytes;

  /// `[1, 224, 224, 3]`.
  final List<int> inputShape;

  /// `uint8`.
  final String inputDtype;

  /// `[1, 11]`.
  final List<int> outputShape;

  /// `float32`.
  final String outputDtype;

  /// Output names in order (`plant`, `quality_*`, `crop_*`).
  final List<String> layout;

  /// `ok`, `blurry`, `dark`.
  final List<String> qualityLabels;

  /// Pilot crop codes plus `other`.
  final List<String> cropLabels;

  /// `plant < plantMin` → retake with `photo.tip.not_plant`.
  final double plantMin;

  /// `quality_blurry >= blurryMin` → retake with `photo.tip.blurry`.
  final double blurryMin;

  /// `quality_dark >= darkMin` → retake with `photo.tip.dark`.
  final double darkMin;

  /// Top crop probability at or above it → crop guess.
  final double cropMin;

  /// `public` until the field-validated model ships.
  final String source;

  /// Input edge in pixels (224).
  int get inputSize => inputShape.length == 4 ? inputShape[1] : 224;

  /// Number of output values (11).
  int get outputLength => layout.length;
}

/// Input tensor bytes plus the mean luminance of the same pixels.
@immutable
class QualityModelInput {
  /// Creates the input.
  const QualityModelInput(this.rgb, this.brightness);

  /// uint8 RGB, NHWC `[1, size, size, 3]`, row-major, not normalised.
  final Uint8List rgb;

  /// Mean luminance of the input, 0..1 (sent as `brightness`).
  final double brightness;
}

@immutable
class _PreprocessRequest {
  const _PreprocessRequest(this.bytes, this.size);

  final Uint8List bytes;
  final int size;
}

QualityModelInput _preprocessEntry(_PreprocessRequest r) =>
    preprocessForQualityModel(r.bytes, size: r.size);

/// INTEGRATION.md §2: the centred square of side 0.875 × the short edge,
/// resized to [size] × [size] (area average), written as uint8 RGB NHWC.
QualityModelInput preprocessForQualityModel(
  Uint8List encoded, {
  int size = 224,
  double cropFraction = 0.875,
}) {
  var image = decodeImageOrThrow(encoded);
  final orientation = image.exif.imageIfd.orientation;
  if (orientation != null && orientation != 1) {
    image = img.bakeOrientation(image);
  }
  final side = math.max(
    1,
    (math.min(image.width, image.height) * cropFraction).round(),
  );
  final x = (image.width - side) ~/ 2;
  final y = (image.height - side) ~/ 2;
  final square = img.copyCrop(image, x: x, y: y, width: side, height: side);
  final resized = img.copyResize(
    square,
    width: size,
    height: size,
    interpolation: img.Interpolation.average,
  );
  final rgb = Uint8List(size * size * 3);
  var i = 0;
  var lum = 0.0;
  for (var yy = 0; yy < size; yy++) {
    for (var xx = 0; xx < size; xx++) {
      final p = resized.getPixel(xx, yy);
      final r = p.r.toInt().clamp(0, 255);
      final g = p.g.toInt().clamp(0, 255);
      final b = p.b.toInt().clamp(0, 255);
      rgb[i++] = r;
      rgb[i++] = g;
      rgb[i++] = b;
      lum += 0.299 * r + 0.587 * g + 0.114 * b;
    }
  }
  return QualityModelInput(rgb, lum / (size * size) / 255);
}

/// INTEGRATION.md §3–§4: the output row as a [PhotoQualityResult]. Quality
/// is checked before plant presence (a dark or blurred frame cannot be
/// judged for a leaf); dark wins over blurry.
PhotoQualityResult decodeQualityOutput(
  List<double> out,
  QualityModelMetadata meta, {
  required double brightness,
}) {
  if (out.length != meta.outputLength) {
    throw QualityModelException(
      'output has ${out.length} values, expected ${meta.outputLength}',
    );
  }
  final byName = <String, double>{
    for (var i = 0; i < meta.layout.length; i++) meta.layout[i]: out[i],
  };
  final plant = byName['plant'] ?? 1;
  final quality = <String, double>{
    for (final q in meta.qualityLabels) q: byName['quality_$q'] ?? 0,
  };
  final crops = <String, double>{
    for (final c in meta.cropLabels) c: byName['crop_$c'] ?? 0,
  };
  final dark = (quality['dark'] ?? 0) >= meta.darkMin;
  final blurry = !dark && (quality['blurry'] ?? 0) >= meta.blurryMin;
  final isPlant = plant >= meta.plantMin;
  final tip = dark
      ? PhotoTipKeys.dark
      : blurry
      ? PhotoTipKeys.blurry
      : !isPlant
      ? PhotoTipKeys.notPlant
      : PhotoTipKeys.ok;
  String? top;
  var topScore = -1.0;
  for (final e in crops.entries) {
    if (e.value > topScore) {
      top = e.key;
      topScore = e.value;
    }
  }
  final accepted = !dark && !blurry && isPlant;
  return PhotoQualityResult(
    isBlurry: blurry,
    blurScore: quality['blurry'] ?? 0,
    isTooDark: dark,
    brightness: brightness,
    tipKey: tip,
    isPlant: isPlant,
    plantScore: plant,
    cropCode: accepted && topScore >= meta.cropMin ? top : null,
    cropScore: topScore < 0 ? null : topScore,
    cropScores: crops,
    qualityScores: quality,
    modelVersion: meta.modelVersion,
  );
}

/// The model file or its runtime cannot be used (bad asset, shape
/// mismatch, interpreter failure).
class QualityModelException implements Exception {
  /// Creates the exception.
  const QualityModelException(this.message);

  /// What went wrong (logged, never shown to users).
  final String message;

  @override
  String toString() => 'QualityModelException: $message';
}

/// One loaded interpreter of the `crop_quality` model. The production
/// implementation is `TfliteFlutterInterpreter` (tflite_flutter, inference
/// on a background isolate); tests pass a fake.
abstract interface class QualityInterpreter {
  /// Input tensor shape.
  List<int> get inputShape;

  /// Input tensor type name (`uint8`).
  String get inputType;

  /// Output tensor shape.
  List<int> get outputShape;

  /// Output tensor type name (`float32`).
  String get outputType;

  /// Runs one image ([QualityModelInput.rgb]) and returns the output row.
  Future<List<double>> run(Uint8List rgb);

  /// Frees the interpreter.
  Future<void> close();
}

/// Creates a [QualityInterpreter] from the model bytes.
typedef QualityInterpreterLoader = Future<QualityInterpreter> Function(
  Uint8List modelBytes,
);

/// Timing and fallback events of the gate (OPS: logged; a fallback reason
/// is reported once per session as a non-fatal).
abstract interface class QualityModelLog {
  /// One check finished.
  void timing({
    required String modelVersion,
    required int preprocessMs,
    required int inferenceMs,
    required bool fallback,
  });

  /// The model was given up for this session.
  void fallback(String reason);
}

/// [QualityModelLog] over `dart:developer` (`photo.quality` log).
class DeveloperQualityModelLog implements QualityModelLog {
  /// Creates the log.
  const DeveloperQualityModelLog();

  @override
  void timing({
    required String modelVersion,
    required int preprocessMs,
    required int inferenceMs,
    required bool fallback,
  }) => developer.log(
    jsonEncode(<String, Object?>{
      'event': 'ondevice_quality_timing',
      'model': modelVersion,
      'preprocess_ms': preprocessMs,
      'inference_ms': inferenceMs,
      'fallback': fallback,
    }),
    name: 'photo.quality',
  );

  @override
  void fallback(String reason) => developer.log(
    jsonEncode(<String, Object?>{
      'event': 'ondevice_quality_fallback',
      'reason': reason,
    }),
    name: 'photo.quality',
    level: 900,
  );
}

/// Records events (tests).
class RecordingQualityModelLog implements QualityModelLog {
  /// Timings, as maps.
  final List<Map<String, Object?>> timings = <Map<String, Object?>>[];

  /// Fallback reasons.
  final List<String> fallbacks = <String>[];

  @override
  void timing({
    required String modelVersion,
    required int preprocessMs,
    required int inferenceMs,
    required bool fallback,
  }) => timings.add(<String, Object?>{
    'model': modelVersion,
    'preprocess_ms': preprocessMs,
    'inference_ms': inferenceMs,
    'fallback': fallback,
  });

  @override
  void fallback(String reason) => fallbacks.add(reason);
}

/// DX-001: the on-device `crop_quality` TFLite model as the photo gate
/// (blurry / dark / not a plant, plus a crop guess), with the Laplacian
/// heuristic as the fallback (INTEGRATION.md §6).
///
/// The model and its metadata are app assets (never downloaded). Loading
/// checks the SHA-256 and the tensor shapes; any failure — missing asset,
/// hash mismatch, interpreter error, wrong shapes, an inference that throws
/// or takes longer than [timeout] — marks the model broken for the session
/// and every later photo goes to [fallback]. The user is never blocked.
/// Preprocessing runs in a background isolate ([compute]) and inference in
/// the interpreter's own isolate.
class TfliteQualityModel implements OnDeviceQualityModel {
  /// Creates the model; call [load] early (or let [evaluate] load it).
  TfliteQualityModel({
    required QualityInterpreterLoader loader,
    AssetBundle? bundle,
    this.modelAsset = defaultModelAsset,
    this.metadataAsset = defaultMetadataAsset,
    this.fallback = PhotoQualityCheck.defaultModel,
    this.timeout = const Duration(milliseconds: 1500),
    QualityModelLog? log,
    Future<QualityModelInput> Function(Uint8List bytes, int size)? preprocess,
  }) : _loader = loader, // ignore: prefer_initializing_formals
       _bundle = bundle, // ignore: prefer_initializing_formals
       _log = log ?? const DeveloperQualityModelLog(),
       _preprocess = preprocess ?? _preprocessInIsolate;

  /// Asset key of the model inside an app that depends on this package.
  static const String defaultModelAsset =
      'packages/farmerapp_core/assets/models/crop_quality_v1.tflite';

  /// Asset key of its metadata.
  static const String defaultMetadataAsset =
      'packages/farmerapp_core/assets/models/crop_quality_v1.metadata.json';

  /// Model asset key.
  final String modelAsset;

  /// Metadata asset key.
  final String metadataAsset;

  /// Answers when the model cannot.
  final OnDeviceQualityModel fallback;

  /// An inference slower than this gives the model up (INTEGRATION.md §6).
  final Duration timeout;

  final QualityInterpreterLoader _loader;
  final AssetBundle? _bundle;
  final QualityModelLog _log;
  final Future<QualityModelInput> Function(Uint8List bytes, int size)
  _preprocess;

  static Future<QualityModelInput> _preprocessInIsolate(
    Uint8List bytes,
    int size,
  ) => compute(
    _preprocessEntry,
    _PreprocessRequest(bytes, size),
    debugLabel: 'TfliteQualityModel.preprocess',
  );

  Future<bool>? _loading;
  QualityInterpreter? _interpreter;
  QualityModelMetadata? _meta;
  String? _brokenReason;
  Future<void> _queue = Future<void>.value();

  /// Metadata once loaded.
  QualityModelMetadata? get metadata => _meta;

  /// Why the model was given up, or null while it is usable.
  String? get fallbackReason => _brokenReason;

  /// True once the interpreter is loaded and not broken.
  bool get isReady => _interpreter != null && _brokenReason == null;

  /// Loads the model once; false when it cannot be used (then [evaluate]
  /// answers with [fallback]).
  Future<bool> load() => _loading ??= _load();

  Future<bool> _load() async {
    try {
      final bundle = _bundle ?? rootBundle;
      final meta = QualityModelMetadata.fromJson(
        Map<String, Object?>.from(
          jsonDecode(await bundle.loadString(metadataAsset, cache: false))
              as Map,
        ),
      );
      final data = await bundle.load(modelAsset);
      final bytes = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      final digest = sha256.convert(bytes).toString();
      if (digest != meta.sha256) {
        throw QualityModelException('model sha256 $digest != ${meta.sha256}');
      }
      final interpreter = await _loader(bytes);
      if (!listEquals(interpreter.inputShape, meta.inputShape) ||
          interpreter.inputType != meta.inputDtype ||
          !listEquals(interpreter.outputShape, meta.outputShape) ||
          interpreter.outputType != meta.outputDtype) {
        await interpreter.close();
        throw QualityModelException(
          'tensors ${interpreter.inputShape} ${interpreter.inputType} -> '
          '${interpreter.outputShape} ${interpreter.outputType} do not match '
          'the metadata',
        );
      }
      _meta = meta;
      _interpreter = interpreter;
      return true;
    } on Object catch (e) {
      _giveUp('load: $e');
      return false;
    }
  }

  void _giveUp(String reason) {
    if (_brokenReason != null) return;
    _brokenReason = reason;
    _log.fallback(reason);
    final interpreter = _interpreter;
    _interpreter = null;
    if (interpreter != null) unawaited(interpreter.close().catchError((_) {}));
  }

  Future<PhotoQualityResult> _fallback(Uint8List bytes) async {
    final watch = Stopwatch()..start();
    final r = await fallback.evaluate(bytes);
    final ms = watch.elapsedMilliseconds;
    _log.timing(
      modelVersion: r.modelVersion,
      preprocessMs: 0,
      inferenceMs: ms,
      fallback: true,
    );
    return r.asFallback().withLatency(ms);
  }

  @override
  Future<PhotoQualityResult> evaluate(Uint8List bytes) {
    // One inference at a time (the interpreter isolate is single-flight).
    final result = _queue.then((_) => _evaluate(bytes));
    _queue = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  Future<PhotoQualityResult> _evaluate(Uint8List bytes) async {
    if (!await load() || _brokenReason != null) return _fallback(bytes);
    final meta = _meta!;
    final interpreter = _interpreter!;
    final watch = Stopwatch()..start();
    final QualityModelInput input;
    try {
      input = await _preprocess(bytes, meta.inputSize);
    } on Object {
      // Undecodable photo: the heuristic reports it the same way.
      return _fallback(bytes);
    }
    final preprocessMs = watch.elapsedMilliseconds;
    watch
      ..reset()
      ..start();
    try {
      final out = await interpreter.run(input.rgb).timeout(timeout);
      final inferenceMs = watch.elapsedMilliseconds;
      final result = decodeQualityOutput(
        out,
        meta,
        brightness: input.brightness,
      ).withLatency(preprocessMs + inferenceMs);
      _log.timing(
        modelVersion: meta.modelVersion,
        preprocessMs: preprocessMs,
        inferenceMs: inferenceMs,
        fallback: false,
      );
      return result;
    } on TimeoutException {
      _giveUp('inference slower than ${timeout.inMilliseconds} ms');
    } on Object catch (e) {
      _giveUp('inference: $e');
    }
    return _fallback(bytes);
  }

  /// Frees the interpreter.
  Future<void> dispose() async {
    final interpreter = _interpreter;
    _interpreter = null;
    await interpreter?.close();
  }
}

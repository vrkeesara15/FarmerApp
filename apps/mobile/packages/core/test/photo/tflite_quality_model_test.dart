// DX-001 on-device model integration (ml/ondevice/INTEGRATION.md): the
// shipped asset and its metadata, preprocessing, output decoding and the
// retake rule, the fallback to the Laplacian heuristic, timing logs. The
// interpreter is faked; one test runs the real model when the TFLite
// runtime loads on this host (skipped otherwise, with the reason).
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'synthetic_images.dart';

const String _modelPath = 'assets/models/crop_quality_v1.tflite';
const String _metaPath = 'assets/models/crop_quality_v1.metadata.json';

Map<String, Object?> _metaJson() =>
    jsonDecode(File(_metaPath).readAsStringSync()) as Map<String, Object?>;

QualityModelMetadata _meta() => QualityModelMetadata.fromJson(_metaJson());

/// Output row: plant, ok, blurry, dark, paddy, cotton, chilli, maize,
/// tomato, groundnut, other.
List<double> _row({
  double plant = 0.99,
  double ok = 0.96,
  double blurry = 0.02,
  double dark = 0.02,
  Map<String, double> crops = const <String, double>{'chilli': 0.93},
}) {
  const order = <String>[
    'paddy',
    'cotton',
    'chilli',
    'maize',
    'tomato',
    'groundnut',
    'other',
  ];
  final rest =
      (1 - crops.values.fold<double>(0, (a, b) => a + b)) /
      (order.length - crops.length);
  return <double>[
    plant,
    ok,
    blurry,
    dark,
    for (final c in order) crops[c] ?? rest,
  ];
}

class _Bundle extends CachingAssetBundle {
  _Bundle(this.files);

  final Map<String, Uint8List> files;

  @override
  Future<ByteData> load(String key) async {
    final bytes = files[key];
    if (bytes == null) throw StateError('missing asset $key');
    return ByteData.sublistView(bytes);
  }
}

class _FakeInterpreter implements QualityInterpreter {
  _FakeInterpreter(this.outputs, {this.shape = const <int>[1, 224, 224, 3]});

  final List<List<double>> outputs;
  final List<int> shape;
  final List<int> inputLengths = <int>[];
  Object? throwOnRun;
  Duration? delay;
  bool closed = false;

  @override
  List<int> get inputShape => shape;

  @override
  String get inputType => 'uint8';

  @override
  List<int> get outputShape => const <int>[1, 11];

  @override
  String get outputType => 'float32';

  @override
  Future<List<double>> run(Uint8List rgb) async {
    inputLengths.add(rgb.length);
    if (delay != null) await Future<void>.delayed(delay!);
    final e = throwOnRun;
    if (e != null) throw e;
    return outputs.length > 1 ? outputs.removeAt(0) : outputs.first;
  }

  @override
  Future<void> close() async => closed = true;
}

_Bundle _realAssets({Uint8List? model}) => _Bundle(<String, Uint8List>{
  TfliteQualityModel.defaultModelAsset:
      model ?? File(_modelPath).readAsBytesSync(),
  TfliteQualityModel.defaultMetadataAsset: File(_metaPath).readAsBytesSync(),
});

Future<QualityModelInput> _syncPreprocess(Uint8List bytes, int size) async =>
    preprocessForQualityModel(bytes, size: size);

class _HeuristicSync implements OnDeviceQualityModel {
  const _HeuristicSync();

  @override
  Future<PhotoQualityResult> evaluate(Uint8List bytes) async =>
      PhotoQualityCheck.evaluateSync(bytes);
}

void main() {
  final leaf = jpeg(textured(640, 480, seed: 7));

  group('asset', () {
    test('model and metadata ship unchanged (sha256 matches metadata)', () {
      final bytes = File(_modelPath).readAsBytesSync();
      final meta = _meta();
      expect(sha256.convert(bytes).toString(), meta.sha256);
      expect(bytes.length, meta.sizeBytes);
      expect(meta.modelVersion, 'ondevice-v1.0');
      expect(bytes.length, lessThan(8 * 1024 * 1024), reason: 'DX-001 < 8 MB');
    });

    test('metadata carries the frozen v1 layout and thresholds', () {
      final meta = _meta();
      expect(meta.inputShape, <int>[1, 224, 224, 3]);
      expect(meta.inputDtype, 'uint8');
      expect(meta.outputShape, <int>[1, 11]);
      expect(meta.layout.first, 'plant');
      expect(meta.qualityLabels, <String>['ok', 'blurry', 'dark']);
      expect(meta.cropLabels, <String>[
        'paddy',
        'cotton',
        'chilli',
        'maize',
        'tomato',
        'groundnut',
        'other',
      ]);
      expect(meta.plantMin, 0.5);
      expect(meta.blurryMin, 0.5);
      expect(meta.darkMin, 0.5);
      expect(meta.cropMin, 0.6);
    });

    test('the asset is declared in the package pubspec', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      expect(pubspec, contains('- assets/models/'));
    });
  });

  group('preprocessing', () {
    test('centre square of 0.875 x short edge, 224 x 224 uint8 RGB', () {
      // 400 x 200: red border columns outside the centred 175 px square,
      // green inside it.
      final image = img.Image(width: 400, height: 200);
      img.fill(image, color: img.ColorRgb8(255, 0, 0));
      img.fillRect(
        image,
        x1: 112,
        y1: 12,
        x2: 288,
        y2: 188,
        color: img.ColorRgb8(0, 200, 0),
      );
      final input = preprocessForQualityModel(img.encodePng(image));
      expect(input.rgb.length, 224 * 224 * 3);
      // Every pixel comes from the green square: no red leaks in.
      var maxRed = 0;
      for (var i = 0; i < input.rgb.length; i += 3) {
        if (input.rgb[i] > maxRed) maxRed = input.rgb[i];
      }
      expect(maxRed, lessThan(30));
      expect(input.rgb[1], greaterThan(180)); // G of the first pixel
    });

    test('brightness is the mean luminance of the input, 0..1', () {
      final grey = flat(300, 300, r: 128, g: 128, b: 128);
      expect(
        preprocessForQualityModel(png(grey)).brightness,
        closeTo(128 / 255, 0.01),
      );
    });
  });

  group('decoding and the retake rule', () {
    final meta = _meta();

    test('a good leaf photo is accepted with the crop guess', () {
      final r = decodeQualityOutput(_row(), meta, brightness: 0.5);
      expect(r.isAcceptable, isTrue);
      expect(r.tipKey, PhotoTipKeys.ok);
      expect(r.isPlant, isTrue);
      expect(r.cropCode, 'chilli');
      expect(r.cropScore, closeTo(0.93, 1e-9));
      expect(r.modelVersion, 'ondevice-v1.0');
      expect(r.cropScores.keys, hasLength(7));
    });

    test('dark wins over blurry and over the plant check', () {
      final r = decodeQualityOutput(
        _row(ok: 0.1, blurry: 0.3, dark: 0.6, plant: 0.1),
        meta,
        brightness: 0.05,
      );
      expect(r.isTooDark, isTrue);
      expect(r.isBlurry, isFalse);
      expect(r.tipKey, PhotoTipKeys.dark);
      expect(r.isAcceptable, isFalse);
      expect(r.cropCode, isNull, reason: 'no crop guess on a rejected photo');
    });

    test('blurry is checked before the plant', () {
      final r = decodeQualityOutput(
        _row(ok: 0.2, blurry: 0.7, dark: 0.1, plant: 0.2),
        meta,
        brightness: 0.4,
      );
      expect(r.tipKey, PhotoTipKeys.blurry);
      expect(r.isAcceptable, isFalse);
    });

    test('no leaf -> not_plant tip', () {
      final r = decodeQualityOutput(_row(plant: 0.1), meta, brightness: 0.5);
      expect(r.isPlant, isFalse);
      expect(r.tipKey, PhotoTipKeys.notPlant);
      expect(r.isAcceptable, isFalse);
      expect(r.toDiagnosisQuality()['plant_present'], isFalse);
    });

    test('a crop below crop_min is not guessed', () {
      final r = decodeQualityOutput(
        _row(crops: const <String, double>{'chilli': 0.45, 'tomato': 0.4}),
        meta,
        brightness: 0.5,
      );
      expect(r.isAcceptable, isTrue);
      expect(r.cropCode, isNull);
      expect(r.cropScore, closeTo(0.45, 1e-9));
    });

    test('the diagnosis quality object has exactly the API fields', () {
      final q = decodeQualityOutput(
        _row(),
        meta,
        brightness: 0.5,
      ).toDiagnosisQuality();
      expect(
        q.keys,
        unorderedEquals(<String>[
          'passed',
          'blur_score',
          'brightness',
          'plant_present',
        ]),
      );
      expect(q['passed'], isTrue);
    });

    test('a wrong output length is refused', () {
      expect(
        () => decodeQualityOutput(<double>[0.1, 0.2], meta, brightness: 0.5),
        throwsA(isA<QualityModelException>()),
      );
    });
  });

  group('TfliteQualityModel', () {
    late RecordingQualityModelLog log;

    setUp(() => log = RecordingQualityModelLog());

    TfliteQualityModel model(
      _FakeInterpreter interpreter, {
      _Bundle? bundle,
      Duration timeout = const Duration(milliseconds: 1500),
    }) => TfliteQualityModel(
      loader: (bytes) async => interpreter,
      bundle: bundle ?? _realAssets(),
      fallback: const _HeuristicSync(),
      log: log,
      timeout: timeout,
      preprocess: _syncPreprocess,
    );

    test(
      'runs the interpreter on the 224 px tensor and logs the timing',
      () async {
        final interpreter = _FakeInterpreter(<List<double>>[_row()]);
        final m = model(interpreter);
        final r = await m.evaluate(leaf);
        expect(m.isReady, isTrue);
        expect(interpreter.inputLengths, <int>[224 * 224 * 3]);
        expect(r.cropCode, 'chilli');
        expect(r.usedFallback, isFalse);
        expect(r.latencyMs, isNotNull);
        expect(log.timings.single['model'], 'ondevice-v1.0');
        expect(log.timings.single['fallback'], isFalse);
        expect(log.fallbacks, isEmpty);
      },
    );

    test(
      'rejects blurry / dark / not-a-plant photos with the right tip',
      () async {
        final interpreter = _FakeInterpreter(<List<double>>[
          _row(ok: 0.1, blurry: 0.8, dark: 0.1),
          _row(ok: 0.1, blurry: 0.1, dark: 0.8),
          _row(plant: 0.05),
          _row(),
        ]);
        final m = model(interpreter);
        expect((await m.evaluate(leaf)).tipKey, PhotoTipKeys.blurry);
        expect((await m.evaluate(leaf)).tipKey, PhotoTipKeys.dark);
        expect((await m.evaluate(leaf)).tipKey, PhotoTipKeys.notPlant);
        expect((await m.evaluate(leaf)).isAcceptable, isTrue);
      },
    );

    test(
      'a model whose sha256 does not match falls back to the heuristic',
      () async {
        final interpreter = _FakeInterpreter(<List<double>>[_row()]);
        var loads = 0;
        final m = TfliteQualityModel(
          loader: (bytes) async {
            loads += 1;
            return interpreter;
          },
          bundle: _realAssets(model: Uint8List.fromList(<int>[1, 2, 3])),
          fallback: const _HeuristicSync(),
          log: log,
          preprocess: _syncPreprocess,
        );
        final r = await m.evaluate(leaf);
        expect(loads, 0);
        expect(r.usedFallback, isTrue);
        expect(r.modelVersion, PhotoQualityResult.heuristicModelVersion);
        expect(r.cropCode, isNull, reason: 'no crop hint on fallback');
        expect(r.isPlant, isTrue, reason: 'the heuristic cannot say no-plant');
        expect(log.fallbacks.single, contains('sha256'));
        await m.evaluate(leaf);
        expect(
          log.fallbacks,
          hasLength(1),
          reason: 'reported once per session',
        );
      },
    );

    test('a missing asset falls back', () async {
      final m = TfliteQualityModel(
        loader: (bytes) async => _FakeInterpreter(<List<double>>[_row()]),
        bundle: _Bundle(<String, Uint8List>{}),
        fallback: const _HeuristicSync(),
        log: log,
      );
      expect(await m.load(), isFalse);
      expect((await m.evaluate(leaf)).usedFallback, isTrue);
    });

    test('tensor shapes that differ from the metadata fall back', () async {
      final interpreter = _FakeInterpreter(
        <List<double>>[_row()],
        shape: const <int>[1, 160, 160, 3],
      );
      final m = model(interpreter);
      final r = await m.evaluate(leaf);
      expect(r.usedFallback, isTrue);
      expect(interpreter.closed, isTrue);
      expect(log.fallbacks.single, contains('do not match'));
    });

    test(
      'an interpreter error marks the model broken for the session',
      () async {
        final interpreter = _FakeInterpreter(<List<double>>[_row()])
          ..throwOnRun = StateError('boom');
        final m = model(interpreter);
        expect((await m.evaluate(leaf)).usedFallback, isTrue);
        interpreter.throwOnRun = null;
        expect((await m.evaluate(leaf)).usedFallback, isTrue);
        expect(interpreter.inputLengths, hasLength(1), reason: 'no retry');
        expect(m.fallbackReason, contains('boom'));
        expect(log.timings.last['fallback'], isTrue);
      },
    );

    test('an inference slower than the timeout falls back', () async {
      final interpreter = _FakeInterpreter(<List<double>>[_row()])
        ..delay = const Duration(milliseconds: 200);
      final m = model(interpreter, timeout: const Duration(milliseconds: 20));
      final r = await m.evaluate(leaf);
      expect(r.usedFallback, isTrue);
      expect(m.fallbackReason, contains('slower'));
    });

    test('the heuristic answers a blurred photo on fallback', () async {
      final m = TfliteQualityModel(
        loader: (bytes) async => throw StateError('no runtime'),
        bundle: _realAssets(),
        fallback: const _HeuristicSync(),
        log: log,
      );
      final r = await m.evaluate(jpeg(blurred(textured(640, 480, seed: 3))));
      expect(r.usedFallback, isTrue);
      expect(r.tipKey, PhotoTipKeys.blurry);
    });
  });

  test('real model on this host (skipped when the TFLite runtime does not '
      'load here)', () async {
    final QualityInterpreter interpreter;
    try {
      interpreter = await TfliteFlutterInterpreter.load(
        File(_modelPath).readAsBytesSync(),
      );
    } on Object catch (e) {
      markTestSkipped(
        'tflite_flutter resolves its desktop library next to the Flutter '
        'runner, which flutter_tester does not have ($e); the real model is '
        'exercised on device (ml/ondevice/BENCHMARK.md).',
      );
      return;
    }
    final meta = _meta();
    final input = preprocessForQualityModel(leaf);
    final out = await interpreter.run(input.rgb);
    await interpreter.close();
    expect(out, hasLength(11));
    final r = decodeQualityOutput(out, meta, brightness: input.brightness);
    expect(
      r.qualityScores.values.fold<double>(0, (a, b) => a + b),
      closeTo(1, 0.02),
    );
    expect(
      r.cropScores.values.fold<double>(0, (a, b) => a + b),
      closeTo(1, 0.02),
    );
  });
}

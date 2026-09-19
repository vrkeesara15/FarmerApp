// DX-001 / DX-005: the `on_device` block of the diagnosis create body
// (ml/ondevice/INTEGRATION.md §5 / §6, `OnDeviceIn` in apps/api/openapi.yaml):
// exact JSON for a model result and for the Laplacian fallback, several
// photos, schema bounds, and no key the server does not declare.
import 'dart:convert';
import 'dart:io';

import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/openapi_schema.dart';

QualityModelMetadata _meta() => QualityModelMetadata.fromJson(
  jsonDecode(
    File('assets/models/crop_quality_v1.metadata.json').readAsStringSync(),
  ) as Map<String, Object?>,
);

/// plant, ok, blurry, dark, paddy, cotton, chilli, maize, tomato,
/// groundnut, other — the INTEGRATION.md §5 example.
const List<double> _example = <double>[
  0.998,
  0.97,
  0.02,
  0.01,
  0.01,
  0,
  0.93,
  0.01,
  0.03,
  0,
  0.02,
];

/// Every key of [block] (nested ones too) is declared by the API schema.
void expectMatchesOnDeviceIn(Map<String, Object?> block) {
  final schema = openApiSchema('OnDeviceIn');
  expect(schema.closed, isTrue, reason: 'the server refuses extra keys');
  expect(schema.properties, containsAll(block.keys));
  expect(block.keys, containsAll(schema.required));
  final quality = block['quality'];
  if (quality is Map) {
    expect(
      openApiSchema('OnDeviceQualityScores').properties,
      containsAll(quality.keys),
    );
  }
  final heuristic = block['heuristic'];
  if (heuristic is Map) {
    expect(
      openApiSchema('OnDeviceHeuristic').properties,
      containsAll(heuristic.keys),
    );
  }
  for (final v in <Object?>[
    ?block['plant_score'],
    ...((quality as Map?)?.values ?? const <Object?>[]),
    ...((block['crop_scores'] as Map?)?.values ?? const <Object?>[]),
  ]) {
    expect(v, allOf(isA<double>(), inInclusiveRange(0, 1)));
  }
  expect(jsonDecode(jsonEncode(block)), block, reason: 'plain JSON');
}

void main() {
  final meta = _meta();

  test('model result: the exact INTEGRATION.md §5 block', () {
    final r = decodeQualityOutput(
      _example,
      meta,
      brightness: 0.46,
    ).withLatency(38);
    final block = OnDeviceBlock.fromResults(<PhotoQualityResult>[r])!;
    expect(block, <String, Object?>{
      'model': 'crop_quality',
      'model_version': 'ondevice-v1.0',
      'model_sha256': meta.sha256,
      'plant_score': 0.998,
      'quality': <String, Object?>{'ok': 0.97, 'blurry': 0.02, 'dark': 0.01},
      'crop_scores': <String, Object?>{
        'paddy': 0.01,
        'cotton': 0.0,
        'chilli': 0.93,
        'maize': 0.01,
        'tomato': 0.03,
        'groundnut': 0.0,
        'other': 0.02,
      },
      'latency_ms': 38,
    });
    expect(block['model'], meta.modelName, reason: 'from the asset metadata');
    expect(block['model_version'], meta.modelVersion);
    expectMatchesOnDeviceIn(block);
  });

  test('fallback: the exact §6 shape (fallback + heuristic)', () {
    const r = PhotoQualityResult(
      isBlurry: false,
      blurScore: 212.4,
      isTooDark: false,
      brightness: 0.46,
      tipKey: PhotoTipKeys.ok,
      latencyMs: 12,
    );
    final block = OnDeviceBlock.fromResults(<PhotoQualityResult>[
      r.asFallback(modelName: meta.modelName),
    ])!;
    expect(block, <String, Object?>{
      'model': 'crop_quality',
      'model_version': 'heuristic-laplacian-v1',
      'fallback': 'laplacian',
      'heuristic': <String, Object?>{'blur_score': 212.4, 'brightness': 0.46},
      'latency_ms': 12,
    });
    expectMatchesOnDeviceIn(block);
    expect(
      OnDeviceBlock.fromResults(<PhotoQualityResult>[r]),
      block,
      reason: 'the heuristic alone (no TFLite model wired) is the same shape',
    );
  });

  test('several photos: scores averaged over the accepted photos', () {
    final a = decodeQualityOutput(
      _example,
      meta,
      brightness: 0.4,
    ).withLatency(30);
    final b = decodeQualityOutput(
      <double>[0.9, 0.9, 0.06, 0.04, 0, 0, 0.8, 0, 0.1, 0, 0.1],
      meta,
      brightness: 0.5,
    ).withLatency(50);
    final block = OnDeviceBlock.fromResults(<PhotoQualityResult>[a, b])!;
    expect(block['plant_score'], 0.949);
    expect(block['quality'], <String, Object?>{
      'ok': 0.935,
      'blurry': 0.04,
      'dark': 0.025,
    });
    expect((block['crop_scores']! as Map)['chilli'], 0.865);
    expect((block['crop_scores']! as Map)['tomato'], 0.065);
    expect(block['latency_ms'], 40);
    expectMatchesOnDeviceIn(block);
  });

  test('the model gave up mid-session: the model photos describe it', () {
    final model = decodeQualityOutput(
      _example,
      meta,
      brightness: 0.46,
    ).withLatency(38);
    const heuristic = PhotoQualityResult(
      isBlurry: false,
      blurScore: 150,
      isTooDark: false,
      brightness: 0.5,
      tipKey: PhotoTipKeys.ok,
      usedFallback: true,
      latencyMs: 9,
    );
    final block = OnDeviceBlock.fromResults(<PhotoQualityResult>[
      model,
      heuristic,
    ])!;
    expect(block['model_version'], 'ondevice-v1.0');
    expect(block.containsKey('fallback'), isFalse);
    expect(block['latency_ms'], 38);
  });

  test('values are kept inside the schema bounds', () {
    final many = <String, double>{
      for (var i = 0; i < 20; i++) 'crop_$i': i / 100,
      '': 0.5,
      'x' * 33: 0.5,
    };
    final r = PhotoQualityResult(
      isBlurry: false,
      blurScore: -3,
      isTooDark: false,
      brightness: 1.2,
      tipKey: PhotoTipKeys.ok,
      plantScore: 1.0000001,
      cropScores: many,
      qualityScores: const <String, double>{
        'ok': 0.5,
        'blurry': 0.5,
        'dark': 0,
        'glare': 0.2,
      },
      modelVersion: 'ondevice-v9',
      modelName: 'crop_quality',
      modelSha256: 'NOT-A-HASH',
      latencyMs: 900000,
    );
    final block = OnDeviceBlock.fromResults(<PhotoQualityResult>[r])!;
    expect(block.containsKey('model_sha256'), isFalse, reason: 'bad hash');
    expect(block['plant_score'], 1.0);
    expect((block['quality']! as Map).keys, <String>['ok', 'blurry', 'dark']);
    final crops = block['crop_scores']! as Map<String, Object?>;
    expect(crops, hasLength(16), reason: 'maxProperties 16, best kept');
    expect(crops.keys, isNot(contains('crop_0')));
    expect(crops.keys.every((c) => c.isNotEmpty && c.length <= 32), isTrue);
    expect(block['latency_ms'], 600000);
    expectMatchesOnDeviceIn(block);

    final fallback = OnDeviceBlock.fromResults(<PhotoQualityResult>[
      r.asFallback(),
    ])!;
    expect(fallback['heuristic'], <String, Object?>{
      'blur_score': 0.0,
      'brightness': 1.0,
    });
    expectMatchesOnDeviceIn(fallback);
  });

  test('no photos, no block', () {
    expect(OnDeviceBlock.fromResults(const <PhotoQualityResult>[]), isNull);
  });

  test('no location or identity can reach the block', () {
    final block = OnDeviceBlock.fromResults(<PhotoQualityResult>[
      decodeQualityOutput(_example, meta, brightness: 0.46),
    ])!;
    final text = jsonEncode(block);
    for (final banned in <String>[
      'latitude',
      'longitude',
      'location',
      'phone',
      'farmer',
      'user',
      'device_id',
    ]) {
      expect(text, isNot(contains(banned)));
    }
  });
}

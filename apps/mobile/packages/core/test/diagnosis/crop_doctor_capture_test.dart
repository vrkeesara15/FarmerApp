// FM-004 capture session: the on-device gate rejects blurry / dark /
// not-a-plant shots with the matching tip, up to 3 photos, the crop guess
// only behind the `on_device_crop_guess` flag, the manual crop override
// always wins; the real heuristic pipeline rejects a blurred photo.
import 'dart:typed_data';

import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../photo/synthetic_images.dart';

Future<ProcessedPhoto> _process(Uint8List bytes, DateTime time) async =>
    processPhotoSync(PhotoProcessRequest(bytes: bytes, captureTime: time));

void main() {
  late AppDatabase db;
  late ScriptedQualityModel model;
  var ids = 0;
  final shot = jpeg(textured(640, 480, seed: 5));

  ProviderContainer container({bool flag = false, OnDeviceQualityModel? m}) {
    final c = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        photoStoreProvider.overrideWithValue(MemoryPhotoStore()),
        onDeviceCropGuessFlagProvider.overrideWithValue(flag),
        diagnosisPhotoPipelineProvider.overrideWithValue(
          DiagnosisPhotoPipeline(model: m ?? model, process: _process),
        ),
        captureClockProvider.overrideWithValue(
          () => DateTime.utc(2026, 9, 19, 4, 30),
        ),
        idGeneratorProvider.overrideWithValue(() => 'id-${++ids}'),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  setUp(() {
    db = openInMemoryDatabase();
    model = ScriptedQualityModel();
  });
  tearDown(() => db.close());

  test(
    'blurry, dark and not-a-plant shots are rejected with their tip',
    () async {
      model
        ..enqueue(ScriptedQualityModel.blurry)
        ..enqueue(ScriptedQualityModel.dark)
        ..enqueue(ScriptedQualityModel.notPlant);
      final c = container();
      final capture = c.read(cropDoctorCaptureProvider.notifier)..start();
      for (final tip in <String>[
        PhotoTipKeys.blurry,
        PhotoTipKeys.dark,
        PhotoTipKeys.notPlant,
      ]) {
        final p = await capture.addShot(shot);
        expect(p!.accepted, isFalse);
        expect(c.read(cropDoctorCaptureProvider).lastTip, tip);
        expect(capture.usePending(), isFalse, reason: '"Use photo" refused');
        capture.retake();
        expect(
          c.read(cropDoctorCaptureProvider).lastTip,
          tip,
          reason: 'the overlay keeps the tip lit for the retake',
        );
      }
      expect(c.read(cropDoctorCaptureProvider).accepted, isEmpty);
    },
  );

  test('up to three good photos', () async {
    final c = container();
    final capture = c.read(cropDoctorCaptureProvider.notifier)..start();
    for (var i = 0; i < 3; i++) {
      await capture.addShot(shot);
      expect(capture.usePending(), isTrue);
    }
    final s = c.read(cropDoctorCaptureProvider);
    expect(s.accepted, hasLength(3));
    expect(s.canAddMore, isFalse);
    await capture.addShot(shot);
    expect(capture.usePending(), isFalse);
    expect(c.read(cropDoctorCaptureProvider).accepted, hasLength(3));
  });

  test('flag off: the crop guess is neither shown nor sent', () async {
    final c = container();
    final capture = c.read(cropDoctorCaptureProvider.notifier)..start();
    await capture.addShot(shot);
    capture.usePending();
    final s = c.read(cropDoctorCaptureProvider);
    expect(s.detectedCropCode, isNull);
    expect(s.crop, isNull);
    await capture.submit();
    final op = SyncStore.toOp((await SyncStore(db).openOps()).single);
    expect(op.payload.containsKey('crop_guess'), isFalse);
    expect(op.payload['crop_id'], 'unknown');
    expect(op.payload['on_device_model'], 'ondevice-v1.0');
    expect(op.payload['on_device'], <String, Object?>{
      'model': 'crop_quality',
      'model_version': 'ondevice-v1.0',
      'plant_score': 0.99,
      'quality': <String, Object?>{'ok': 0.96, 'blurry': 0.02, 'dark': 0.02},
      'crop_scores': <String, Object?>{
        'paddy': 0.03,
        'chilli': 0.93,
        'other': 0.04,
      },
      'latency_ms': 40,
    }, reason: 'DX-005 provenance is sent whatever the guess flag says');
  });

  test('flag on: the guess pre-selects the crop and is sent', () async {
    final c = container(flag: true);
    final capture = c.read(cropDoctorCaptureProvider.notifier)..start();
    await capture.addShot(shot);
    capture.usePending();
    final s = c.read(cropDoctorCaptureProvider);
    expect(s.detectedCropCode, 'chilli');
    expect(s.crop?.code, 'chilli');
    expect(s.cropPickedByUser, isFalse);
    await capture.submit();
    final op = SyncStore.toOp((await SyncStore(db).openOps()).single);
    expect(op.payload['crop_guess'], <String, Object?>{
      'code': 'chilli',
      'confidence': 0.93,
    });
  });

  test(
    'manual crop override wins and a later guess never overwrites it',
    () async {
      final c = container(flag: true);
      final capture = c.read(cropDoctorCaptureProvider.notifier)..start();
      capture.chooseCrop(
        const CropChoice(
          code: 'cotton',
          cropId: 'crop-cotton',
          cropPlotId: 'plot-1',
        ),
      );
      await capture.addShot(shot);
      capture.usePending();
      final s = c.read(cropDoctorCaptureProvider);
      expect(s.detectedCropCode, 'chilli');
      expect(s.crop?.code, 'cotton');
      await capture.submit();
      final op = SyncStore.toOp((await SyncStore(db).openOps()).single);
      expect(op.payload['crop_plot_id'], 'plot-1');
    },
  );

  test('the real heuristic pipeline rejects a blurred photo', () async {
    final c = container(m: PhotoQualityCheck.defaultModel);
    final capture = c.read(cropDoctorCaptureProvider.notifier)..start();
    final blurredShot = jpeg(blurred(textured(1280, 960, seed: 3)));
    final p = await capture.addShot(blurredShot);
    expect(p!.quality.tipKey, PhotoTipKeys.blurry);
    expect(capture.usePending(), isFalse);
    final good = await capture.addShot(jpeg(textured(1280, 960, seed: 3)));
    expect(good!.accepted, isTrue);
    expect(good.processed.width, 1280);
  });

  test('heuristic only: the fallback on_device block is queued', () async {
    final c = container(m: PhotoQualityCheck.defaultModel);
    final capture = c.read(cropDoctorCaptureProvider.notifier)..start();
    final good = await capture.addShot(jpeg(textured(1280, 960, seed: 3)));
    expect(capture.usePending(), isTrue);
    await capture.submit();
    final op = SyncStore.toOp((await SyncStore(db).openOps()).single);
    final block = op.payload['on_device']! as Map<String, Object?>;
    expect(block.keys, <String>[
      'model',
      'model_version',
      'fallback',
      'heuristic',
      'latency_ms',
    ]);
    expect(block['model_version'], PhotoQualityResult.heuristicModelVersion);
    expect(block['fallback'], 'laplacian');
    expect(
      (block['heuristic']! as Map)['brightness'],
      closeTo(good!.quality.brightness, 0.0001),
    );
    expect(block['latency_ms'], isA<int>());
  });
}

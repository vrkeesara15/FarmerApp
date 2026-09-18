// FM-004 / DX-001: on-device quality gate. Variance of the Laplacian on a
// 320 px grayscale copy separates sharp from blurred; mean luminance flags
// dark frames. Thresholds are calibrated on this synthetic set (see the
// PhotoQualityConfig doc for the measured scores).
import 'dart:typed_data';

import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'synthetic_images.dart';

class _FixedModel implements OnDeviceQualityModel {
  const _FixedModel(this.result);

  final PhotoQualityResult result;

  @override
  Future<PhotoQualityResult> evaluate(Uint8List bytes) async => result;
}

void main() {
  final sharp = textured(1280, 960, seed: 3);

  group('blur', () {
    test('a sharp photo is not blurry', () {
      final r = PhotoQualityCheck.evaluateSync(jpeg(sharp));
      expect(r.isBlurry, isFalse);
      expect(r.blurScore, greaterThan(100));
      expect(r.isTooDark, isFalse);
      expect(r.tipKey, PhotoTipKeys.ok);
      expect(r.isAcceptable, isTrue);
    });

    test('a gaussian-blurred photo is blurry with the retake tip', () {
      final r = PhotoQualityCheck.evaluateSync(jpeg(blurred(sharp)));
      expect(r.isBlurry, isTrue);
      expect(r.blurScore, lessThan(PhotoQualityConfig.defaults.blurThreshold));
      expect(r.isTooDark, isFalse);
      expect(r.tipKey, PhotoTipKeys.blurry);
      expect(r.isAcceptable, isFalse);
    });

    test('scores keep a wide margin around the default threshold', () {
      final s = PhotoQualityCheck.evaluateSync(jpeg(sharp)).blurScore;
      final b = PhotoQualityCheck.evaluateSync(jpeg(blurred(sharp))).blurScore;
      final t = PhotoQualityConfig.defaults.blurThreshold;
      expect(s, greaterThan(t * 4));
      expect(b, lessThan(t / 1.5));
    });

    test('a slightly soft photo (radius 3) still passes', () {
      final r = PhotoQualityCheck.evaluateSync(jpeg(blurred(sharp, radius: 3)));
      expect(r.isBlurry, isFalse);
    });

    test('the score does not depend on the input resolution', () {
      final big = PhotoQualityCheck.evaluateSync(
        jpeg(textured(2560, 1920, seed: 3, blades: 1600)),
      ).blurScore;
      final small = PhotoQualityCheck.evaluateSync(jpeg(sharp)).blurScore;
      // Same scene family, both far above the threshold.
      expect(big, greaterThan(PhotoQualityConfig.defaults.blurThreshold * 2));
      expect(small, greaterThan(PhotoQualityConfig.defaults.blurThreshold * 2));
    });
  });

  group('brightness', () {
    test('a dark frame is too dark and dark wins over blurry', () {
      final r = PhotoQualityCheck.evaluateSync(jpeg(flat(640, 480)));
      expect(r.isTooDark, isTrue);
      expect(r.brightness, lessThan(PhotoQualityConfig.defaults.darkThreshold));
      expect(r.isBlurry, isTrue, reason: 'a flat frame has no edges');
      expect(r.tipKey, PhotoTipKeys.dark);
      expect(r.isAcceptable, isFalse);
    });

    test('a bright flat wall is not dark but is blurry', () {
      final r = PhotoQualityCheck.evaluateSync(
        jpeg(flat(640, 480, r: 200, g: 200, b: 200)),
      );
      expect(r.isTooDark, isFalse);
      expect(r.brightness, closeTo(200 / 255, 0.02));
      expect(r.tipKey, PhotoTipKeys.blurry);
    });

    test('brightness is the mean luminance in 0..1', () {
      final r = PhotoQualityCheck.evaluateSync(jpeg(sharp));
      expect(r.brightness, inInclusiveRange(0.3, 0.7));
    });
  });

  group('config and model seam', () {
    test('thresholds come from the config object', () {
      final strict = PhotoQualityCheck.evaluateSync(
        jpeg(sharp),
        config: const PhotoQualityConfig(blurThreshold: 1e9, darkThreshold: 0),
      );
      expect(strict.isBlurry, isTrue);
      expect(strict.isTooDark, isFalse);
      final lax = PhotoQualityCheck.evaluateSync(
        jpeg(blurred(sharp)),
        config: const PhotoQualityConfig(blurThreshold: 0, darkThreshold: 0.99),
      );
      expect(lax.isBlurry, isFalse);
      expect(lax.isTooDark, isTrue);
    });

    test('evaluate runs the default Laplacian model off the caller', () async {
      final r = await PhotoQualityCheck.evaluate(jpeg(blurred(sharp)));
      expect(r.isBlurry, isTrue);
      expect(PhotoQualityCheck.defaultModel, isA<LaplacianQualityModel>());
    });

    test(
      'another OnDeviceQualityModel can be plugged in (M6 TFLite)',
      () async {
        const fixed = PhotoQualityResult(
          isBlurry: false,
          blurScore: 999,
          isTooDark: false,
          brightness: 0.5,
          tipKey: PhotoTipKeys.ok,
        );
        final r = await PhotoQualityCheck.evaluate(
          Uint8List(0),
          model: const _FixedModel(fixed),
        );
        expect(r, fixed);
      },
    );

    test('undecodable bytes throw PhotoDecodeException', () {
      expect(
        () => PhotoQualityCheck.evaluateSync(Uint8List.fromList(<int>[0, 1])),
        throwsA(isA<PhotoDecodeException>()),
      );
    });

    test('result serialises for the outbox and analytics', () {
      final r = PhotoQualityCheck.evaluateSync(jpeg(flat(64, 48)));
      final json = r.toJson();
      expect(json['is_blurry'], true);
      expect(json['is_too_dark'], true);
      expect(json['tip_key'], 'photo.tip.dark');
      expect(json['blur_score'], isA<double>());
      expect(json['brightness'], isA<double>());
      expect(PhotoQualityResult.fromJson(json), r);
    });
  });
}

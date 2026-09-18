// Synthetic test images drawn with `package:image` (no binary fixtures).
//
// `textured` imitates a field photo well enough for size and blur tests: a
// soft green/brown gradient, many short sharp "blades" and Gaussian sensor
// noise. Measured with the NF-004 pipeline (1280 px long edge, q80, 4:2:0):
//   * textured(1280, 960)                       -> ~193 KB at q80
//   * textured(4000, 3000, blades: 4000) -> 1280 -> ~198 KB at q80
//   * textured(1280, 960, blades: 1500)         -> ~321 KB q80, ~226 KB q70
import 'dart:math';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// A photo-like image: gradient + sharp blades + Gaussian noise.
img.Image textured(
  int width,
  int height, {
  int seed = 1,
  double noiseSigma = 8,
  int blades = 400,
}) {
  final image = img.Image(width: width, height: height);
  final rnd = Random(seed);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final fy = y / height;
      final fx = x / width;
      image.setPixelRgb(
        x,
        y,
        (60 + 80 * fy + 20 * sin(fx * 12)).clamp(0, 255),
        (120 + 60 * (1 - fy) + 25 * sin(fx * 7 + fy * 5)).clamp(0, 255),
        (40 + 40 * fy).clamp(0, 255),
      );
    }
  }
  for (var i = 0; i < blades; i++) {
    final cx = rnd.nextInt(width);
    final cy = rnd.nextInt(height);
    final len = 10 + rnd.nextInt(width ~/ 12);
    final a = rnd.nextDouble() * pi;
    img.drawLine(
      image,
      x1: cx,
      y1: cy,
      x2: (cx + len * cos(a)).round(),
      y2: (cy + len * sin(a)).round(),
      color: img.ColorRgb8(
        20 + rnd.nextInt(80),
        80 + rnd.nextInt(140),
        20 + rnd.nextInt(60),
      ),
      thickness: 1 + rnd.nextInt(4),
    );
  }
  if (noiseSigma > 0) {
    img.noise(image, noiseSigma, random: rnd);
  }
  return image;
}

/// A flat image of one colour.
img.Image flat(int width, int height, {int r = 20, int g = 25, int b = 15}) {
  return img.Image(width: width, height: height)..clear(img.ColorRgb8(r, g, b));
}

/// Gaussian-blurred copy of [source].
img.Image blurred(img.Image source, {int radius = 6}) {
  return img.gaussianBlur(img.Image.from(source), radius: radius);
}

/// JPEG bytes of [image] (camera-like quality).
Uint8List jpeg(img.Image image, {int quality = 92}) {
  return img.encodeJpg(image, quality: quality, chroma: img.JpegChroma.yuv420);
}

/// PNG bytes of [image].
Uint8List png(img.Image image) => img.encodePng(image);

/// JPEG bytes of [image] carrying an EXIF orientation tag.
Uint8List jpegWithOrientation(img.Image image, int orientation) {
  final copy = img.Image.from(image);
  copy.exif.imageIfd.orientation = orientation;
  return img.encodeJpg(copy, quality: 92);
}

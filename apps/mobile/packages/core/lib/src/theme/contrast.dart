import 'dart:math' as math;
import 'dart:ui';

/// NF-009 contrast helper.
///
/// The WCAG 2.2 ratio was already the gate the design tokens are held to
/// (`test/theme/contrast_test.dart`). FA-008 lets a tenant replace the
/// primary colour at run time, so the same arithmetic now has to run in the
/// app as well: a brand colour is only used once it has been pushed to a
/// value that still passes AA in all three themes. The test suite and the
/// theme therefore share one implementation rather than two that can drift.

/// WCAG 2.2 relative luminance of an opaque colour (0 = black, 1 = white).
double relativeLuminance(Color c) {
  double channel(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
}

/// WCAG 2.2 contrast ratio between two opaque colours (1..21, symmetric).
double contrastRatio(Color a, Color b) {
  final la = relativeLuminance(a);
  final lb = relativeLuminance(b);
  final hi = math.max(la, lb);
  final lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

/// Parses `#RRGGBB` (case-insensitive); `null` when the string is not one.
Color? parseHexColour(String? hex) {
  if (hex == null) return null;
  final value = hex.trim();
  if (!RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(value)) return null;
  return Color(0xFF000000 | int.parse(value.substring(1), radix: 16));
}

/// `#RRGGBB` for [c] (upper case), as the settings API stores it.
String hexOf(Color c) {
  String part(double v) =>
      (v * 255).round().clamp(0, 255).toInt().toRadixString(16).padLeft(2, '0');
  return '#${part(c.r)}${part(c.g)}${part(c.b)}'.toUpperCase();
}

/// Lightness (0..1) of [c] in HSL.
///
/// Written out rather than taken from `HSLColor` so the console's
/// TypeScript copy (`apps/console/lib/brand.ts`) can be line-for-line the
/// same and both surfaces derive byte-identical colours from one brand hex.
double lightnessOf(Color c) {
  final max = math.max(c.r, math.max(c.g, c.b));
  final min = math.min(c.r, math.min(c.g, c.b));
  return (max + min) / 2;
}

/// [c] with its HSL lightness replaced by [lightness] (0..1).
Color withLightness(Color c, double lightness) {
  final l = lightness.clamp(0.0, 1.0);
  final max = math.max(c.r, math.max(c.g, c.b));
  final min = math.min(c.r, math.min(c.g, c.b));
  final delta = max - min;
  final l0 = (max + min) / 2;
  if (delta == 0) return _rgb(l, l, l);
  final s = delta / (1 - (2 * l0 - 1).abs());
  double h;
  if (max == c.r) {
    h = ((c.g - c.b) / delta) % 6;
  } else if (max == c.g) {
    h = (c.b - c.r) / delta + 2;
  } else {
    h = (c.r - c.g) / delta + 4;
  }
  h *= 60;
  if (h < 0) h += 360;
  final chroma = (1 - (2 * l - 1).abs()) * s;
  final x = chroma * (1 - ((h / 60) % 2 - 1).abs());
  final m = l - chroma / 2;
  final (r, g, b) = switch (h ~/ 60) {
    0 => (chroma, x, 0.0),
    1 => (x, chroma, 0.0),
    2 => (0.0, chroma, x),
    3 => (0.0, x, chroma),
    4 => (x, 0.0, chroma),
    _ => (chroma, 0.0, x),
  };
  return _rgb(r + m, g + m, b + m);
}

Color _rgb(double r, double g, double b) => Color.fromARGB(
  255,
  (r * 255).round().clamp(0, 255).toInt(),
  (g * 255).round().clamp(0, 255).toInt(),
  (b * 255).round().clamp(0, 255).toInt(),
);

/// Mixes [a] into [b]: `t == 0` is [a], `t == 1` is [b] (sRGB, rounded).
Color mixColours(Color a, Color b, double t) {
  final k = t.clamp(0.0, 1.0);
  return _rgb(
    a.r + (b.r - a.r) * k,
    a.g + (b.g - a.g) * k,
    a.b + (b.b - a.b) * k,
  );
}

/// One lightness step used when a colour has to be pushed to pass AA.
const double contrastStep = 0.01;

/// [colour] moved in 1 % lightness steps until it reaches [min] against
/// [background], darker when [darken] and lighter otherwise.
///
/// Stops at pure black / white, so the worst case is the strongest colour
/// available rather than an endless loop.
Color ensureContrast(
  Color colour,
  Color background, {
  required double min,
  required bool darken,
}) {
  var out = colour;
  for (var i = 0; i < 101; i++) {
    if (contrastRatio(out, background) >= min) return out;
    final l = lightnessOf(out) + (darken ? -contrastStep : contrastStep);
    if (l < 0 || l > 1) {
      return darken ? const Color(0xFF000000) : const Color(0xFFFFFFFF);
    }
    out = withLightness(out, l);
  }
  return out;
}

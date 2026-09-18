import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('type scale matches SPEC 13.1 and uses weights 400/600 only', () {
    final t = AppTextStyles.forLocale(const Locale('en'), color: Colors.black);
    expect(t.display.fontSize, 28);
    expect(t.display.height, 36 / 28);
    expect(t.title.fontSize, 22);
    expect(t.heading.fontSize, 18);
    expect(t.body.fontSize, 16);
    expect(t.body.height, 24 / 16);
    expect(t.label.fontSize, 14);
    expect(t.caption.fontSize, 12);
    for (final s in <TextStyle>[
      t.display,
      t.title,
      t.heading,
      t.body,
      t.label,
      t.caption,
    ]) {
      expect(
        s.fontWeight,
        isIn(<FontWeight>[FontWeight.w400, FontWeight.w600]),
      );
      expect(s.fontFeatures, contains(const FontFeature.tabularFigures()));
    }
  });

  test('Indic locales get +15% line height', () {
    final te = AppTextStyles.forLocale(const Locale('te'), color: Colors.black);
    expect(te.body.height, closeTo(24 * 1.15 / 16, 1e-9));
    expect(te.body.fontFamilyFallback, contains('Noto Sans Telugu'));
    final hi = AppTextStyles.forLocale(const Locale('hi'), color: Colors.black);
    expect(hi.body.fontFamilyFallback, contains('Noto Sans Devanagari'));
  });

  test('Sunlight theme is pure white, black text, 2 dp borders', () {
    final theme = AppTheme.build(AppThemeMode.sunlight);
    final app = theme.extension<AppThemeData>()!;
    expect(app.palette.background, const Color(0xFFFFFFFF));
    expect(app.palette.surface, const Color(0xFFFFFFFF));
    expect(app.palette.text, const Color(0xFF000000));
    expect(app.palette.primary, const Color(0xFF134A27));
    expect(app.borderWidth, 2);
    expect(app.tint(app.palette.primaryContainer), app.palette.surface);
  });

  test('Light theme uses the default tokens', () {
    final theme = AppTheme.build(AppThemeMode.light);
    final app = theme.extension<AppThemeData>()!;
    expect(app.palette.primary, const Color(0xFF1F6B3A));
    expect(app.palette.background, const Color(0xFFFAF7F0));
    expect(app.borderWidth, 1);
    expect(app.tint(app.palette.primaryContainer), const Color(0xFFDCEFE2));
  });
}

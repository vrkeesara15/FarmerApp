import 'dart:convert';

import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// FA-008: a tenant supplies one colour; the theme derives the other three
/// `color.primary.*` tokens from it. These tests hold the derivation to the
/// same NF-009 bar the shipped tokens are held to (`contrast_test.dart`) —
/// for brand colours chosen to be awkward: a very light one, a very dark
/// one, a saturated red, and the two acceptance tenants.
void main() {
  const modes = <AppThemeMode>[AppThemeMode.light, AppThemeMode.sunlight];

  /// The colours a tenant might actually pick, plus two that are hostile.
  const brands = <String, String>{
    'fresh crops indigo': '#3B4BD8',
    'sun agro orange': '#E0651B',
    'bright yellow (hostile: no white passes)': '#FFE600',
    'near black': '#050505',
    'saturated red': '#FF0000',
    'default leaf': '#1F6B3A',
  };

  for (final entry in brands.entries) {
    group(entry.key, () {
      final colour = parseHexColour(entry.value)!;

      for (final mode in modes) {
        test('${mode.name}: text and controls keep WCAG AA', () {
          final p = brandedPalette(
            mode == AppThemeMode.light ? Tokens.light : Tokens.sunlight,
            colour,
            mode,
          );
          final min = brandMinContrast[mode]!;
          expect(
            contrastRatio(p.primary, p.surface),
            greaterThanOrEqualTo(min),
            reason: 'primary is used as icon and text colour',
          );
          expect(
            contrastRatio(p.primary, p.background),
            greaterThanOrEqualTo(4.5),
          );
          expect(
            contrastRatio(p.primaryOn, p.primary),
            greaterThanOrEqualTo(4.5),
          );
          expect(
            contrastRatio(p.primaryOn, p.primaryHover),
            greaterThanOrEqualTo(4.5),
            reason: 'a pressed button still shows its label',
          );
          expect(
            contrastRatio(p.primary, p.primaryContainer),
            greaterThanOrEqualTo(4.5),
          );
        });
      }

      test('dark (console parity): text and controls keep WCAG AA', () {
        final p = brandedPalette(
          Tokens.dark,
          colour,
          AppThemeMode.light,
          dark: true,
        );
        expect(contrastRatio(p.primary, p.surface), greaterThanOrEqualTo(4.5));
        expect(
          contrastRatio(p.primaryOn, p.primary),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          contrastRatio(p.primaryOn, p.primaryHover),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          contrastRatio(p.primary, p.primaryContainer),
          greaterThanOrEqualTo(4.5),
        );
      });

      test('sunlight is at least as strong as light', () {
        final light = brandedPalette(Tokens.light, colour, AppThemeMode.light);
        final sun = brandedPalette(
          Tokens.sunlight,
          colour,
          AppThemeMode.sunlight,
        );
        expect(
          contrastRatio(sun.primary, sun.surface),
          greaterThanOrEqualTo(contrastRatio(light.primary, light.surface)),
        );
      });
    });
  }

  test('a light brand colour flips on-primary to near black', () {
    final p = brandedPalette(
      Tokens.light,
      parseHexColour('#FFE600')!,
      AppThemeMode.light,
    );
    // Yellow cannot carry white text, so the derivation darkens it until it
    // reads on white and then picks whichever on-primary wins.
    expect(contrastRatio(p.primaryOn, p.primary), greaterThanOrEqualTo(4.5));
  });

  test('sunlight keeps plain white containers (SPEC 13.1: no tints)', () {
    final p = brandedPalette(
      Tokens.sunlight,
      parseHexColour('#3B4BD8')!,
      AppThemeMode.sunlight,
    );
    expect(p.primaryContainer, Tokens.sunlight.primaryContainer);
  });

  test('the derivation is pinned (the console must match hex for hex)', () {
    // apps/console/lib/brand.test.ts asserts exactly these values for the
    // same input: one brand colour, one set of tokens, two surfaces.
    final light = brandedPalette(
      Tokens.light,
      parseHexColour('#3B4BD8')!,
      AppThemeMode.light,
    );
    expect(hexOf(light.primary), '#3B4BD8');
    expect(hexOf(light.primaryOn), '#FFFFFF');
    expect(hexOf(light.primaryHover), '#2533B7');
    expect(hexOf(light.primaryContainer), '#E7E9FA');
    final dark = brandedPalette(
      Tokens.dark,
      parseHexColour('#3B4BD8')!,
      AppThemeMode.light,
      dark: true,
    );
    expect(hexOf(dark.primary), '#6B7BE4');
    expect(hexOf(dark.primaryHover), '#A4AEEE');
    expect(hexOf(dark.primaryContainer), '#181B27');
    expect(hexOf(dark.primaryOn), '#0B1A10');
    final sunlight = brandedPalette(
      Tokens.sunlight,
      parseHexColour('#3B4BD8')!,
      AppThemeMode.sunlight,
    );
    expect(hexOf(sunlight.primary), '#3343D6');
  });

  group('AppBrand', () {
    test('resolves the app name per surface, falling back to the working '
        'name', () async {
      const branding = TenantBranding(
        appNameAgent: 'Harvest Field',
        appNameFarmer: 'Harvest Farmer',
        primaryColour: '#3B4BD8',
        logoBlobUri: 'https://cdn.example/logo.png',
        supportPhone: '+919800000001',
      );
      final agent = AppBrand.of(branding, BrandSurface.agent);
      expect(agent.appName, 'Harvest Field');
      expect(agent.primary, parseHexColour('#3B4BD8'));
      expect(agent.logoUri, 'https://cdn.example/logo.png');
      expect(agent.supportPhone, '+919800000001');
      expect(
        AppBrand.of(branding, BrandSurface.farmer).appName,
        'Harvest Farmer',
      );
    });

    test('the shipped colour is not treated as an override', () {
      expect(
        AppBrand.of(const TenantBranding(), BrandSurface.agent).primary,
        isNull,
      );
      expect(
        AppBrand.of(const TenantBranding(), BrandSurface.agent).appName,
        isNull,
      );
    });

    test('blank strings are no override', () {
      const branding = TenantBranding(
        appNameAgent: '  ',
        logoBlobUri: '',
        supportPhone: ' ',
      );
      final brand = AppBrand.of(branding, BrandSurface.agent);
      expect(brand.appName, isNull);
      expect(brand.logoUri, isNull);
      expect(brand.supportPhone, isNull);
    });
  });

  group('brandingOverrides', () {
    test(
      'reads the cached brand so the first frame is the tenant\'s',
      () async {
        final db = openInMemoryDatabase();
        addTearDown(db.close);
        await db.setValue(
          TenantSettingsSync.kvKey,
          jsonEncode(
            const PublicTenantSettings(
              branding: TenantBranding(
                appNameAgent: 'Harvest Field',
                primaryColour: '#3B4BD8',
              ),
            ).toJson(),
          ),
        );
        final container = ProviderContainer(
          overrides: await brandingOverrides(db),
        );
        addTearDown(container.dispose);
        expect(
          container.read(initialBrandingProvider).appNameAgent,
          'Harvest Field',
        );
      },
    );

    test('a corrupt cache falls back to the default brand', () async {
      final db = openInMemoryDatabase();
      addTearDown(db.close);
      await db.setValue(TenantSettingsSync.kvKey, 'not json');
      final container = ProviderContainer(
        overrides: await brandingOverrides(db),
      );
      addTearDown(container.dispose);
      expect(container.read(initialBrandingProvider), const TenantBranding());
    });
  });

  testWidgets('the theme paints the tenant colour through the tokens', (
    tester,
  ) async {
    late AppThemeData themed;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(
          AppThemeMode.light,
          brand: AppBrand(
            surface: BrandSurface.agent,
            primary: parseHexColour('#3B4BD8'),
          ),
        ),
        home: Builder(
          builder: (context) {
            themed = context.app;
            return const SizedBox();
          },
        ),
      ),
    );
    expect(hexOf(themed.palette.primary), '#3B4BD8');
    expect(themed.palette.text, Tokens.light.text, reason: 'only primary.*');
  });
}

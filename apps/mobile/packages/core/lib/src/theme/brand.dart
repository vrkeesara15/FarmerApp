import 'package:flutter/widgets.dart';

import '../i18n/generated/core_localizations.dart';
import '../state/tenant_settings.dart';
import '../tokens/tokens.g.dart';
import 'app_theme.dart';
import 'contrast.dart';

/// FA-008 tenant branding, resolved for one surface.
///
/// SPEC 2.1: a tenant may set its app name, logo, primary colour and support
/// phone; SPEC 13.1 allows the primary colour and the logo to be overridden,
/// nothing else. The four tenant values arrive in `GET /v1/settings/public`
/// ([TenantBranding]) and are cached, so the first frame after a launch is
/// already the tenant's (see `brandingOverrides`).
///
/// The Android application label and the launcher icon are *not* part of
/// this: they are baked into the APK a store listing points at, so they stay
/// per app ("Mitra" / "Kisan") whatever the tenant sets. Documented in
/// docs/branding.md.
@immutable
class AppBrand {
  /// Creates the brand.
  const AppBrand({
    required this.surface,
    this.appName,
    this.primary,
    this.logoUri,
    this.supportPhone,
  });

  /// The brand of [branding] for [surface]; the default brand when the
  /// tenant set nothing.
  factory AppBrand.of(TenantBranding branding, BrandSurface surface) {
    final name = switch (surface) {
      BrandSurface.agent => branding.appNameAgent,
      BrandSurface.farmer => branding.appNameFarmer,
    };
    final colour = parseHexColour(branding.primaryColour);
    return AppBrand(
      surface: surface,
      appName: (name?.trim().isEmpty ?? true) ? null : name!.trim(),
      // The default is not a tenant override: keep the shipped tokens
      // (which carry the NF-009 corrections the derivation cannot know).
      primary: colour == Tokens.light.primary ? null : colour,
      logoUri: (branding.logoBlobUri?.trim().isEmpty ?? true)
          ? null
          : branding.logoBlobUri!.trim(),
      supportPhone: (branding.supportPhone?.trim().isEmpty ?? true)
          ? null
          : branding.supportPhone!.trim(),
    );
  }

  /// The default brand of the officer app (no tenant override).
  static const AppBrand agent = AppBrand(surface: BrandSurface.agent);

  /// The default brand of the farmer app (no tenant override).
  static const AppBrand farmer = AppBrand(surface: BrandSurface.farmer);

  /// Which app this brand is for.
  final BrandSurface surface;

  /// The tenant's app name, or `null` for the shipped one.
  final String? appName;

  /// The tenant's primary colour, or `null` for the token palette.
  final Color? primary;

  /// The tenant's logo (an https blob URI), or `null` for the leaf mark.
  final String? logoUri;

  /// The tenant's support phone in E.164, or `null` when it set none.
  final String? supportPhone;

  /// The name to show: the tenant's, else the shipped working name
  /// (SPEC 1.2: "Mitra" and "Kisan" are placeholders).
  String name(CoreLocalizations l10n) =>
      appName ??
      switch (surface) {
        BrandSurface.agent => l10n.appNameAgent,
        BrandSurface.farmer => l10n.appNameFarmer,
      };

  @override
  bool operator ==(Object other) =>
      other is AppBrand &&
      other.surface == surface &&
      other.appName == appName &&
      other.primary == primary &&
      other.logoUri == logoUri &&
      other.supportPhone == supportPhone;

  @override
  int get hashCode =>
      Object.hash(surface, appName, primary, logoUri, supportPhone);
}

/// Which app a brand is resolved for (the two app-name overrides).
enum BrandSurface {
  /// Field agent app.
  agent,

  /// Farmer app.
  farmer,
}

/// Minimum contrast the branded primary keeps against the theme's surface.
///
/// The Sunlight theme exists for a farmer holding a cheap phone in direct
/// sun, so it asks for AAA (7:1) where Light and Dark ask for AA (4.5:1) —
/// the same relation the shipped tokens have, which `contrast_test.dart`
/// pins ("the Sunlight theme is the strongest of the three").
const Map<AppThemeMode, double> brandMinContrast = <AppThemeMode, double>{
  AppThemeMode.light: 4.5,
  AppThemeMode.sunlight: 7,
};

/// Contrast the white / near-black on-primary must reach on the primary.
const double onPrimaryMinContrast = 4.5;

/// Near-black used for on-primary over a light brand colour (the Dark
/// theme's `primaryOn`).
const Color brandOnPrimaryDark = Color(0xFF0B1A10);

/// [base] with the four `color.primary.*` tokens derived from [primary].
///
/// The tenant only ever supplies one colour; hover, container and
/// on-primary are derived here so a brand cannot ship an unreadable screen
/// (NF-009 / WCAG AA, checked with [contrastRatio] at every step):
///
/// 1. **primary** is darkened (lightened in Dark) in 1 % lightness steps
///    until it reaches [brandMinContrast] against *both* the theme's
///    surface and its background — it is used as icon and text colour, not
///    only as a fill, and the Light background is a warm off-white half a
///    step darker than the cards that sit on it.
/// 2. **on-primary** is white or [brandOnPrimaryDark], whichever contrasts
///    more; if neither reaches 4.5:1 the primary is pushed further.
/// 3. **hover** is the primary 20 % darker (lighter in Dark) and is kept at
///    4.5:1 against on-primary, because a pressed button still shows its
///    label.
/// 4. **container** is the primary mixed into the surface until the primary
///    reads on it at 4.5:1. The Sunlight theme has no tinted containers
///    (SPEC 13.1), so it keeps the base one (plain white).
TokenPalette brandedPalette(
  TokenPalette base,
  Color primary,
  AppThemeMode mode, {
  bool dark = false,
}) {
  final darken = !dark;
  final min = dark ? 4.5 : brandMinContrast[mode]!;
  var p = ensureContrast(primary, base.surface, min: min, darken: darken);
  p = ensureContrast(p, base.background, min: min, darken: darken);
  var on =
      contrastRatio(const Color(0xFFFFFFFF), p) >=
          contrastRatio(brandOnPrimaryDark, p)
      ? const Color(0xFFFFFFFF)
      : brandOnPrimaryDark;
  if (contrastRatio(on, p) < onPrimaryMinContrast) {
    p = ensureContrast(p, on, min: onPrimaryMinContrast, darken: darken);
    on =
        contrastRatio(const Color(0xFFFFFFFF), p) >=
            contrastRatio(brandOnPrimaryDark, p)
        ? const Color(0xFFFFFFFF)
        : brandOnPrimaryDark;
  }
  final hover = ensureContrast(
    withLightness(p, lightnessOf(p) * (dark ? 1.2 : 0.8)),
    on,
    min: onPrimaryMinContrast,
    darken: !dark,
  );
  final container = mode == AppThemeMode.sunlight
      ? base.primaryContainer
      : ensureContrast(
          mixColours(
            p,
            dark ? base.background : base.surface,
            dark ? 0.8 : 0.88,
          ),
          p,
          min: onPrimaryMinContrast,
          darken: dark,
        );
  return TokenPalette(
    primary: p,
    primaryHover: hover,
    primaryContainer: container,
    primaryOn: on,
    secondary: base.secondary,
    secondaryContainer: base.secondaryContainer,
    secondaryOn: base.secondaryOn,
    text: base.text,
    textSecondary: base.textSecondary,
    textMuted: base.textMuted,
    border: base.border,
    borderStrong: base.borderStrong,
    surface: base.surface,
    background: base.background,
    statusSuccess: base.statusSuccess,
    statusSuccessContainer: base.statusSuccessContainer,
    statusWarning: base.statusWarning,
    statusWarningContainer: base.statusWarningContainer,
    statusDanger: base.statusDanger,
    statusDangerContainer: base.statusDangerContainer,
    statusInfo: base.statusInfo,
    statusInfoContainer: base.statusInfoContainer,
    confidenceHigh: base.confidenceHigh,
    confidenceMedium: base.confidenceMedium,
    confidenceLow: base.confidenceLow,
    visitVerified: base.visitVerified,
    visitPartial: base.visitPartial,
    visitUnverified: base.visitUnverified,
  );
}

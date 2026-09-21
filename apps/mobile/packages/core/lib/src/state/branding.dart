import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

import '../db/app_database.dart';
import '../security/security_providers.dart' show tenantSettingsProvider;
import '../theme/brand.dart';
import 'tenant_settings.dart';

/// FA-008: the tenant branding both apps read.
///
/// `GET /v1/settings/public` is pulled after login, daily and whenever the
/// network returns ([TenantSettingsSync]); the pulled value is cached in
/// `kv`. [brandingOverrides] reads that cache *before* the first frame, the
/// same way FA-004 loads the saved language, so a launch shows the tenant's
/// colour, name and logo immediately instead of flashing the default green
/// and then repainting. With nothing cached — a fresh install — the shipped
/// tokens apply until the first pull lands.

/// The branding loaded before the first frame; see [brandingOverrides].
final Provider<TenantBranding> initialBrandingProvider =
    Provider<TenantBranding>((ref) => const TenantBranding());

/// The live branding: the pulled settings once they are read, else the
/// value the app started with.
final Provider<TenantBranding> brandingProvider = Provider<TenantBranding>(
  (ref) =>
      ref.watch(tenantSettingsProvider).value?.branding ??
      ref.watch(initialBrandingProvider),
);

/// Which app this is; the apps override it (`BrandSurface.farmer` in Kisan).
final Provider<BrandSurface> brandSurfaceProvider = Provider<BrandSurface>(
  (ref) => BrandSurface.agent,
);

/// The resolved brand of this app: name, colour, logo and support phone.
final Provider<AppBrand> appBrandProvider = Provider<AppBrand>(
  (ref) =>
      AppBrand.of(ref.watch(brandingProvider), ref.watch(brandSurfaceProvider)),
);

/// The tenant's support phone, or `null` when it set none (FA-008: every
/// "call support" action dials this).
final Provider<String?> supportPhoneProvider = Provider<String?>(
  (ref) => ref.watch(appBrandProvider).supportPhone,
);

/// Turns a logo URI into an [ImageProvider]. Overridden in tests (and by
/// anything that wants a caching loader) so no widget test touches the
/// network.
final Provider<ImageProvider<Object> Function(String uri)>
brandLogoLoaderProvider = Provider<ImageProvider<Object> Function(String uri)>(
  (ref) => NetworkImage.new,
);

/// Reads the cached tenant settings from [db] and returns the override the
/// apps pass to their root `ProviderScope`, so the first frame already uses
/// the tenant's brand. Never throws: a missing or corrupt cache is the
/// default brand.
Future<List<Override>> brandingOverrides(AppDatabase db) async {
  var branding = const TenantBranding();
  try {
    final raw = await db.getValue(TenantSettingsSync.kvKey);
    if (raw != null) {
      branding = PublicTenantSettings.fromJson(
        Map<String, Object?>.from(jsonDecode(raw) as Map),
      ).branding;
    }
  } on Object {
    // Corrupt cache: ship the default brand and let the next pull fix it.
  }
  return <Override>[initialBrandingProvider.overrideWithValue(branding)];
}

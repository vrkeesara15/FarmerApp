import 'dart:convert';

import 'package:flutter/widgets.dart';

import 'tenant_settings.dart';

/// FA-008 acceptance fixture: two tenants whose brands differ in every
/// field the apps and the console render.
///
/// SPEC 2.1 asks for "a second test tenant renders with its brand without a
/// code change". These two are that test: both apps and the console build
/// the same widget tree for each of them and only the branding changes.
/// They live in `lib/` rather than a test folder because the officer app,
/// the farmer app and the core package each have their own test suite and
/// all three assert against the same two tenants — a second copy would be a
/// second answer to "what does tenant B look like".
///
/// The console's copy is `apps/console/lib/mock/brands.ts`; the hex values
/// are the same on purpose.
abstract final class TestBrands {
  /// Tenant A: indigo, "Harvest".
  static const TenantBranding harvest = TenantBranding(
    appNameAgent: 'Harvest Field',
    appNameFarmer: 'Harvest Kisan',
    primaryColour: '#3B4BD8',
    logoBlobUri: 'https://cdn.example/harvest-logo.png',
    supportPhone: '+919800000001',
  );

  /// Tenant B: terracotta, "Bhoomi".
  static const TenantBranding bhoomi = TenantBranding(
    appNameAgent: 'Bhoomi Officer',
    appNameFarmer: 'Bhoomi',
    primaryColour: '#B4362A',
    logoBlobUri: 'https://cdn.example/bhoomi-logo.png',
    supportPhone: '+919800000002',
  );

  /// 8x8 solid PNGs standing in for the two tenants' logos, so a test can
  /// render a real image without touching the network.
  static const Map<String, String> logoPngBase64 = <String, String>{
    'https://cdn.example/harvest-logo.png':
        'iVBORw0KGgoAAAANSUhEUgAAAAgAAAAICAIAAABLbSncAAAAEUlEQVR4nGOw9r6B'
        'FTEMLQkACYZXgdU378AAAAAASUVORK5CYII=',
    'https://cdn.example/bhoomi-logo.png':
        'iVBORw0KGgoAAAANSUhEUgAAAAgAAAAICAIAAABLbSncAAAAEUlEQVR4nGPYYqaF'
        'FTEMLQkAGN1FARmqfVwAAAAASUVORK5CYII=',
  };

  /// A [brandLogoLoaderProvider] stand-in that serves [logoPngBase64] from
  /// memory and falls back to tenant A's mark for an unknown URI.
  static ImageProvider<Object> logoLoader(String uri) => MemoryImage(
    base64Decode(logoPngBase64[uri] ?? logoPngBase64.values.first),
  );
}

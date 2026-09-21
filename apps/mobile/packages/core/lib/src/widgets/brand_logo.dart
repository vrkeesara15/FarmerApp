import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/branding.dart';
import '../theme/app_theme.dart';
import '../tokens/tokens.g.dart';

/// FA-008: the tenant's logo, with the shipped leaf mark as the fallback.
///
/// Used on the splash and in the home header of both apps. A tenant that
/// set no logo — or whose logo cannot be loaded, which offline is the
/// normal case on a fresh install — gets the same circle with the leaf the
/// app has always shown, so the header never collapses.
class BrandLogo extends ConsumerWidget {
  /// Creates the logo at [size] dp (the drawn circle, not the padding).
  const BrandLogo({super.key, this.size = Tokens.space8, this.bordered = true});

  /// Edge length in dp.
  final double size;

  /// Draw the token border around the circle (off inside an AppBar).
  final bool bordered;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = context.app;
    final uri = ref.watch(appBrandProvider).logoUri;
    final fallback = Icon(
      Icons.eco_outlined,
      size: size / 2,
      color: app.palette.primary,
    );
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: app.tint(app.palette.primaryContainer),
        shape: BoxShape.circle,
        border: bordered ? Border.fromBorderSide(app.borderSide) : null,
      ),
      child: uri == null
          ? fallback
          : Image(
              key: const Key('brand-logo-image'),
              image: ref.watch(brandLogoLoaderProvider)(uri),
              width: size,
              height: size,
              fit: BoxFit.contain,
              // Offline, or a tenant that typed a bad URI: the leaf mark.
              errorBuilder: (context, error, stack) => fallback,
              // i18n-ignore: decorative; the brand name is next to it.
              excludeFromSemantics: true,
            ),
    );
  }
}

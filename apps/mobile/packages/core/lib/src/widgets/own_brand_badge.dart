import 'package:flutter/material.dart';

import '../i18n/generated/core_localizations.dart';
import '../theme/app_theme.dart';
import '../tokens/tokens.g.dart';

/// Turmeric "Own brand" badge shown on the tenant's own products
/// (SPEC 13.1 `OwnBrandBadge`).
class OwnBrandBadge extends StatelessWidget {
  /// Creates the badge.
  const OwnBrandBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final p = app.palette;
    final l10n = CoreLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Tokens.space2,
        vertical: Tokens.space1,
      ),
      decoration: BoxDecoration(
        color: app.tint(p.secondaryContainer),
        borderRadius: BorderRadius.circular(Tokens.radiusPill),
        border: Border.all(color: p.secondary, width: app.borderWidth),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.star_outline, size: Tokens.space4, color: p.secondaryOn),
          const SizedBox(width: Tokens.space1),
          Text(
            l10n.ownBrand,
            style: app.text.caption.copyWith(
              color: p.secondaryOn,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

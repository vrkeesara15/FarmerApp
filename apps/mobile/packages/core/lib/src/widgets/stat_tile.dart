import 'package:flutter/material.dart';

import '../i18n/generated/core_localizations.dart';
import '../theme/app_theme.dart';
import '../tokens/tokens.g.dart';

/// Direction of the trend arrow on a [StatTile].
enum StatTrend {
  /// Value went up.
  up,

  /// Value went down.
  down,

  /// No change.
  flat,
}

/// Compact value + label tile with an optional trend arrow
/// (SPEC 13.1 `StatTile`).
class StatTile extends StatelessWidget {
  /// Creates the tile.
  const StatTile({
    required this.value,
    required this.label,
    this.icon,
    this.trend,
    this.trendLabel,
    super.key,
  });

  /// Pre-formatted value, e.g. `12` or `₹1,25,000`.
  final String value;

  /// What the value is.
  final String label;

  /// Optional leading icon.
  final IconData? icon;

  /// Optional trend.
  final StatTrend? trend;

  /// Optional text next to the arrow, e.g. `+3`.
  final String? trendLabel;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final p = app.palette;
    final l10n = CoreLocalizations.of(context);
    final trendColor = switch (trend) {
      StatTrend.up => p.statusSuccess,
      StatTrend.down => p.statusDanger,
      _ => p.textSecondary,
    };
    final trendIcon = switch (trend) {
      StatTrend.up => Icons.arrow_upward,
      StatTrend.down => Icons.arrow_downward,
      _ => Icons.remove,
    };
    final trendText = switch (trend) {
      StatTrend.up => l10n.statTrendUp,
      StatTrend.down => l10n.statTrendDown,
      _ => l10n.statTrendFlat,
    };

    return Container(
      padding: const EdgeInsets.all(Tokens.space3),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(Tokens.radiusCard),
        border: Border.fromBorderSide(app.borderSide),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, color: p.primary),
            const SizedBox(height: Tokens.space2),
          ],
          Text(value, style: app.text.display, maxLines: 1),
          const SizedBox(height: Tokens.space1),
          Text(
            label,
            style: app.text.label.copyWith(color: p.textSecondary),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (trend != null) ...<Widget>[
            const SizedBox(height: Tokens.space2),
            Row(
              children: <Widget>[
                Icon(trendIcon, size: Tokens.space4, color: trendColor),
                const SizedBox(width: Tokens.space1),
                Flexible(
                  child: Text(
                    trendLabel == null ? trendText : '$trendLabel $trendText',
                    style: app.text.caption.copyWith(color: trendColor),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

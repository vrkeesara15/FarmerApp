import 'package:flutter/material.dart';

import '../i18n/generated/core_localizations.dart';
import '../theme/app_theme.dart';
import '../tokens/tokens.g.dart';
import 'internal/dashed_border.dart';

/// Diagnosis confidence (DX requirements).
enum ConfidenceLevel {
  /// Success colour.
  high,

  /// Warning colour.
  medium,

  /// Provisional: neutral grey with a dashed border.
  low,
}

/// Confidence label pill (SPEC 13.1 `ConfidenceBand`).
class ConfidenceBand extends StatelessWidget {
  /// Creates the band.
  const ConfidenceBand({required this.level, super.key});

  /// Confidence level.
  final ConfidenceLevel level;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final p = app.palette;
    final l10n = CoreLocalizations.of(context);
    final (
      Color color,
      Color container,
      String label,
      IconData icon,
    ) = switch (level) {
      ConfidenceLevel.high => (
        p.confidenceHigh,
        app.tint(p.statusSuccessContainer),
        l10n.confidenceHigh,
        Icons.check_circle_outline,
      ),
      ConfidenceLevel.medium => (
        p.confidenceMedium,
        app.tint(p.statusWarningContainer),
        l10n.confidenceMedium,
        Icons.help_outline,
      ),
      ConfidenceLevel.low => (
        p.confidenceLow,
        p.surface,
        l10n.confidenceLow,
        Icons.hourglass_empty,
      ),
    };
    final content = Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Tokens.space3,
        vertical: Tokens.space1,
      ),
      decoration: BoxDecoration(
        color: container,
        borderRadius: BorderRadius.circular(Tokens.radiusPill),
        border: level == ConfidenceLevel.low
            ? null
            : Border.all(color: color, width: app.borderWidth),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: Tokens.space4, color: color),
          const SizedBox(width: Tokens.space1),
          Flexible(
            child: Text(
              label,
              style: app.text.label.copyWith(color: color),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
    return Semantics(
      label: label,
      child: level == ConfidenceLevel.low
          ? DashedBorder(
              color: color,
              strokeWidth: app.borderWidth,
              radius: Tokens.radiusPill,
              child: content,
            )
          : content,
    );
  }
}

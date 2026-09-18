import 'package:flutter/material.dart';

import '../i18n/generated/core_localizations.dart';
import '../theme/app_theme.dart';
import '../tokens/tokens.g.dart';

/// Visit verification status derived from the 0-100 score (VV requirements).
enum VisitStatus {
  /// Score >= 70.
  verified,

  /// Score 40-69.
  partial,

  /// Score < 40.
  unverified;

  /// Threshold at or above which a visit is [verified].
  static const int verifiedThreshold = 70;

  /// Threshold at or above which a visit is at least [partial].
  static const int partialThreshold = 40;

  /// Maps a score to its status.
  static VisitStatus fromScore(int score) {
    assert(score >= 0 && score <= 100, 'score must be 0..100');
    if (score >= verifiedThreshold) return VisitStatus.verified;
    if (score >= partialThreshold) return VisitStatus.partial;
    return VisitStatus.unverified;
  }
}

/// Score pill coloured by [VisitStatus] (SPEC 13.1 `VisitScoreBadge`).
///
/// Verified is filled success, partial is filled warning, unverified is a
/// danger outline.
class VisitScoreBadge extends StatelessWidget {
  /// Creates the badge for [score] (0-100).
  const VisitScoreBadge({required this.score, super.key});

  /// Visit score 0-100.
  final int score;

  /// Derived status.
  VisitStatus get status => VisitStatus.fromScore(score);

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final p = app.palette;
    final l10n = CoreLocalizations.of(context);
    final status = this.status;
    final (
      Color color,
      String label,
      IconData icon,
      bool filled,
    ) = switch (status) {
      VisitStatus.verified => (
        p.visitVerified,
        l10n.visitVerified,
        Icons.verified_outlined,
        true,
      ),
      VisitStatus.partial => (
        p.visitPartial,
        l10n.visitPartial,
        Icons.rule_outlined,
        true,
      ),
      VisitStatus.unverified => (
        p.visitUnverified,
        l10n.visitUnverified,
        Icons.error_outline,
        false,
      ),
    };
    final container = switch (status) {
      VisitStatus.verified => app.tint(p.statusSuccessContainer),
      VisitStatus.partial => app.tint(p.statusWarningContainer),
      VisitStatus.unverified => p.surface,
    };
    return Semantics(
      label: '$label, ${l10n.visitScore(score)}',
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: Tokens.space3,
          vertical: Tokens.space1,
        ),
        decoration: BoxDecoration(
          color: filled ? container : p.surface,
          borderRadius: BorderRadius.circular(Tokens.radiusPill),
          border: Border.all(
            color: color,
            width: filled ? app.borderWidth : app.borderWidth + 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: Tokens.space4, color: color),
            const SizedBox(width: Tokens.space1),
            Text('$score', style: app.text.label.copyWith(color: color)),
            const SizedBox(width: Tokens.space1),
            Flexible(
              child: Text(
                label,
                style: app.text.caption.copyWith(color: color),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

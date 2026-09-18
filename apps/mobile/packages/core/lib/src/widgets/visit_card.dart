import 'package:flutter/material.dart';

import '../i18n/generated/core_localizations.dart';
import '../theme/app_theme.dart';
import '../tokens/tokens.g.dart';
import '../utils/format.dart';
import 'visit_score_badge.dart';

/// Purpose of a visit (SPEC A30).
enum VisitPurpose {
  /// Advisory visit.
  advisory,

  /// Crop scouting.
  scouting,

  /// Demo plot.
  demo,

  /// Payment collection.
  collection,

  /// Product sale.
  sale,

  /// Group meeting.
  meeting,
}

/// Localised label and icon for a [VisitPurpose].
extension VisitPurposeUi on VisitPurpose {
  /// Localised label.
  String label(CoreLocalizations l10n) => switch (this) {
    VisitPurpose.advisory => l10n.visitPurposeAdvisory,
    VisitPurpose.scouting => l10n.visitPurposeScouting,
    VisitPurpose.demo => l10n.visitPurposeDemo,
    VisitPurpose.collection => l10n.visitPurposeCollection,
    VisitPurpose.sale => l10n.visitPurposeSale,
    VisitPurpose.meeting => l10n.visitPurposeMeeting,
  };

  /// Pictogram.
  IconData get icon => switch (this) {
    VisitPurpose.advisory => Icons.support_agent_outlined,
    VisitPurpose.scouting => Icons.bug_report_outlined,
    VisitPurpose.demo => Icons.science_outlined,
    VisitPurpose.collection => Icons.currency_rupee,
    VisitPurpose.sale => Icons.shopping_bag_outlined,
    VisitPurpose.meeting => Icons.groups_outlined,
  };
}

/// Visit list item with farmer, purpose, time, duration and score badge
/// (SPEC 13.1 `VisitCard`). An open visit (no [score] yet) shows an
/// "In progress" pill instead of the badge; [footnote] carries the sync
/// state ("Will sync", "Needs attention") under the meta row.
class VisitCard extends StatelessWidget {
  /// Creates the card.
  const VisitCard({
    required this.farmerName,
    required this.purpose,
    required this.startedAtUtc,
    required this.duration,
    required this.score,
    this.onTap,
    this.footnote,
    this.footnoteColor,
    super.key,
  });

  /// Farmer visited.
  final String farmerName;

  /// Purpose of the visit.
  final VisitPurpose purpose;

  /// Start time in UTC.
  final DateTime startedAtUtc;

  /// How long the visit lasted.
  final Duration duration;

  /// Visit score 0-100; null while the visit is open (not checked out).
  final int? score;

  /// Tap handler.
  final VoidCallback? onTap;

  /// Sync / attention line under the meta row.
  final String? footnote;

  /// Colour of [footnote] (secondary text when null).
  final Color? footnoteColor;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final p = app.palette;
    final l10n = CoreLocalizations.of(context);
    return Semantics(
      button: onTap != null,
      child: Material(
        color: p.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Tokens.radiusCard),
          side: app.borderSide,
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(Tokens.space3),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        farmerName,
                        style: app.text.heading,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: Tokens.space2),
                    if (score != null)
                      VisitScoreBadge(score: score!)
                    else
                      _OpenPill(label: l10n.visitStatusOpen),
                  ],
                ),
                const SizedBox(height: Tokens.space2),
                Row(
                  children: <Widget>[
                    Icon(purpose.icon, size: Tokens.space4, color: p.primary),
                    const SizedBox(width: Tokens.space1),
                    Text(purpose.label(l10n), style: app.text.label),
                  ],
                ),
                const SizedBox(height: Tokens.space1),
                Wrap(
                  spacing: Tokens.space3,
                  runSpacing: Tokens.space1,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: <Widget>[
                    _Meta(
                      icon: Icons.schedule_outlined,
                      text: formatDateTimeIst(startedAtUtc),
                    ),
                    _Meta(
                      icon: Icons.timelapse_outlined,
                      text: l10n.visitDurationMinutes(duration.inMinutes),
                    ),
                  ],
                ),
                if (footnote != null) ...<Widget>[
                  const SizedBox(height: Tokens.space1),
                  Text(
                    footnote!,
                    style: app.text.caption.copyWith(
                      color: footnoteColor ?? p.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final p = app.palette;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icon, size: Tokens.space4, color: p.textSecondary),
        const SizedBox(width: Tokens.space1),
        Text(text, style: app.text.caption.copyWith(color: p.textSecondary)),
      ],
    );
  }
}

class _OpenPill extends StatelessWidget {
  const _OpenPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final p = app.palette;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Tokens.space3,
        vertical: Tokens.space1,
      ),
      decoration: BoxDecoration(
        color: app.tint(p.statusInfoContainer),
        borderRadius: BorderRadius.circular(Tokens.radiusPill),
        border: Border.all(color: p.statusInfo, width: app.borderWidth),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.timelapse, size: Tokens.space4, color: p.statusInfo),
          const SizedBox(width: Tokens.space1),
          Text(label, style: app.text.caption.copyWith(color: p.statusInfo)),
        ],
      ),
    );
  }
}

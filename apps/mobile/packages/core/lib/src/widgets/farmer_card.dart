import 'package:flutter/material.dart';

import '../i18n/generated/core_localizations.dart';
import '../theme/app_theme.dart';
import '../tokens/tokens.g.dart';
import '../utils/format.dart';
import 'crop_chip.dart';

/// Farmer list item: photo or initials, name, village, crop chips, last visit
/// and balance-due badge (SPEC 13.1 `FarmerCard`).
class FarmerCard extends StatelessWidget {
  /// Creates the card.
  const FarmerCard({
    required this.name,
    required this.village,
    this.photo,
    this.crops = const <CropChipData>[],
    this.lastVisitUtc,
    this.balanceDuePaise = 0,
    this.pendingSync = false,
    this.attention = false,
    this.onTap,
    super.key,
  });

  /// Farmer name.
  final String name;

  /// Village name.
  final String village;

  /// Optional photo; initials are shown when `null`.
  final ImageProvider<Object>? photo;

  /// Crops to show as chips (first two are shown).
  final List<CropChipData> crops;

  /// Last visit time in UTC, or `null` if never visited.
  final DateTime? lastVisitUtc;

  /// Outstanding balance in paise; the badge is hidden when zero.
  final int balanceDuePaise;

  /// Saved offline; a queued op has not reached the server yet (FA-025).
  final bool pendingSync;

  /// The server rejected the farmer (A64 / A22 explain); shown as a
  /// danger row under the footer.
  final bool attention;

  /// Tap handler.
  final VoidCallback? onTap;

  String get _initials {
    final parts = name.trim().split(RegExp(r'\s+'));
    final chars = parts.take(2).map((s) => s.isEmpty ? '' : s[0]).join();
    return chars.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final p = app.palette;
    final l10n = CoreLocalizations.of(context);
    return Semantics(
      button: onTap != null,
      label: '$name, $village',
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
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    CircleAvatar(
                      radius: Tokens.space6,
                      backgroundColor: app.tint(p.primaryContainer),
                      foregroundColor: p.primary,
                      foregroundImage: photo,
                      child: Text(_initials, style: app.text.heading),
                    ),
                    const SizedBox(width: Tokens.space3),
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            name,
                            style: app.text.heading,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Row(
                            children: <Widget>[
                              Icon(
                                Icons.place_outlined,
                                size: Tokens.space4,
                                color: p.textSecondary,
                              ),
                              const SizedBox(width: Tokens.space1),
                              Expanded(
                                child: Text(
                                  village,
                                  style: app.text.body.copyWith(
                                    color: p.textSecondary,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (balanceDuePaise > 0) ...<Widget>[
                      const SizedBox(width: Tokens.space2),
                      Flexible(
                        child: _DueBadge(
                          text: l10n.farmerBalanceDue(
                            formatInr(balanceDuePaise, showPaise: false),
                          ),
                          icon: Icons.currency_rupee,
                          color: p.statusWarning,
                          container: p.statusWarningContainer,
                        ),
                      ),
                    ],
                  ],
                ),
                if (crops.isNotEmpty) ...<Widget>[
                  const SizedBox(height: Tokens.space3),
                  Wrap(
                    spacing: Tokens.space2,
                    runSpacing: Tokens.space2,
                    children: <Widget>[
                      for (final c in crops.take(2)) CropChip(data: c),
                    ],
                  ),
                ],
                const SizedBox(height: Tokens.space3),
                Row(
                  children: <Widget>[
                    Icon(
                      Icons.event_outlined,
                      size: Tokens.space4,
                      color: p.textSecondary,
                    ),
                    const SizedBox(width: Tokens.space1),
                    Expanded(
                      child: Text(
                        lastVisitUtc == null
                            ? l10n.farmerNoVisit
                            : l10n.farmerLastVisit(
                                formatDateIst(lastVisitUtc!),
                              ),
                        style: app.text.caption.copyWith(
                          color: p.textSecondary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                if (attention) ...<Widget>[
                  const SizedBox(height: Tokens.space1),
                  Row(
                    children: <Widget>[
                      Icon(
                        Icons.error_outline,
                        size: Tokens.space4,
                        color: p.statusDanger,
                      ),
                      const SizedBox(width: Tokens.space1),
                      Expanded(
                        child: Text(
                          l10n.farmerRejected,
                          style: app.text.caption.copyWith(
                            color: p.statusDanger,
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
                if (pendingSync) ...<Widget>[
                  const SizedBox(height: Tokens.space1),
                  Row(
                    children: <Widget>[
                      Icon(
                        Icons.cloud_upload_outlined,
                        size: Tokens.space4,
                        color: p.statusInfo,
                      ),
                      const SizedBox(width: Tokens.space1),
                      Expanded(
                        child: Text(
                          l10n.farmerPendingSync,
                          style: app.text.caption.copyWith(color: p.statusInfo),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
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

class _DueBadge extends StatelessWidget {
  const _DueBadge({
    required this.text,
    required this.icon,
    required this.color,
    required this.container,
  });

  final String text;
  final IconData icon;
  final Color color;
  final Color container;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Tokens.space2,
        vertical: Tokens.space1,
      ),
      decoration: BoxDecoration(
        color: app.tint(container),
        borderRadius: BorderRadius.circular(Tokens.radiusPill),
        border: Border.all(color: color, width: app.borderWidth),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: Tokens.space4, color: color),
          const SizedBox(width: Tokens.space1),
          Flexible(
            child: Text(
              text,
              overflow: TextOverflow.ellipsis,
              style: app.text.caption.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

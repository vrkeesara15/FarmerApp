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
                      _DueBadge(
                        text: l10n.farmerBalanceDue(
                          formatInr(balanceDuePaise, showPaise: false),
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
                    Text(
                      lastVisitUtc == null
                          ? l10n.farmerNoVisit
                          : l10n.farmerLastVisit(formatDateIst(lastVisitUtc!)),
                      style: app.text.caption.copyWith(color: p.textSecondary),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DueBadge extends StatelessWidget {
  const _DueBadge({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final p = app.palette;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Tokens.space2,
        vertical: Tokens.space1,
      ),
      decoration: BoxDecoration(
        color: app.tint(p.statusWarningContainer),
        borderRadius: BorderRadius.circular(Tokens.radiusPill),
        border: Border.all(color: p.statusWarning, width: app.borderWidth),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            Icons.currency_rupee,
            size: Tokens.space4,
            color: p.statusWarning,
          ),
          const SizedBox(width: Tokens.space1),
          Text(
            text,
            style: app.text.caption.copyWith(
              color: p.statusWarning,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

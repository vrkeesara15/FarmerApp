import 'package:flutter/material.dart';

import '../i18n/generated/core_localizations.dart';
import '../theme/app_theme.dart';
import '../tokens/tokens.g.dart';

/// The four proofs that make a visit verified (VV requirements).
enum ProofKind {
  /// Officer was inside the farm geofence.
  geofence,

  /// At least one in-app photo was taken.
  photo,

  /// Farmer confirmed the visit (OTP, app or QR).
  farmerConfirmed,

  /// Visit met the minimum duration.
  duration,
}

/// One row of a [ProofChecklist].
@immutable
class ProofItem {
  /// Creates the item.
  const ProofItem({
    required this.kind,
    required this.satisfied,
    this.explanation,
  });

  /// Which proof.
  final ProofKind kind;

  /// Whether it is met.
  final bool satisfied;

  /// Optional override for the explanation text.
  final String? explanation;
}

/// Tick/cross list of visit proofs with explanations
/// (SPEC 13.1 `ProofChecklist`).
class ProofChecklist extends StatelessWidget {
  /// Creates the checklist.
  const ProofChecklist({required this.items, super.key});

  /// Items in display order.
  final List<ProofItem> items;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final p = app.palette;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(Tokens.radiusCard),
        border: Border.fromBorderSide(app.borderSide),
      ),
      child: Column(
        children: <Widget>[
          for (var i = 0; i < items.length; i++) ...<Widget>[
            if (i > 0) Divider(height: app.borderWidth, color: p.border),
            _ProofRow(item: items[i]),
          ],
        ],
      ),
    );
  }
}

class _ProofRow extends StatelessWidget {
  const _ProofRow({required this.item});

  final ProofItem item;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final p = app.palette;
    final l10n = CoreLocalizations.of(context);
    final ok = item.satisfied;
    final color = ok ? p.statusSuccess : p.statusDanger;
    final (String title, String missing, IconData icon) = switch (item.kind) {
      ProofKind.geofence => (
        l10n.proofGeofence,
        l10n.proofGeofenceMissing,
        Icons.my_location_outlined,
      ),
      ProofKind.photo => (
        l10n.proofPhoto,
        l10n.proofPhotoMissing,
        Icons.photo_camera_outlined,
      ),
      ProofKind.farmerConfirmed => (
        l10n.proofFarmerConfirmed,
        l10n.proofFarmerConfirmedMissing,
        Icons.how_to_reg_outlined,
      ),
      ProofKind.duration => (
        l10n.proofDuration,
        l10n.proofDurationMissing,
        Icons.timer_outlined,
      ),
    };
    final explanation = item.explanation ?? (ok ? null : missing);
    return Semantics(
      label: '$title: ${ok ? l10n.proofDone : l10n.proofMissing}',
      child: Padding(
        padding: const EdgeInsets.all(Tokens.space3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(icon, color: p.textSecondary),
            const SizedBox(width: Tokens.space3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(title, style: app.text.body),
                  if (explanation != null)
                    Text(
                      explanation,
                      style: app.text.caption.copyWith(color: p.textSecondary),
                    ),
                ],
              ),
            ),
            const SizedBox(width: Tokens.space2),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  ok ? Icons.check_circle_outline : Icons.cancel_outlined,
                  color: color,
                ),
                const SizedBox(width: Tokens.space1),
                Text(
                  ok ? l10n.proofDone : l10n.proofMissing,
                  style: app.text.caption.copyWith(color: color),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

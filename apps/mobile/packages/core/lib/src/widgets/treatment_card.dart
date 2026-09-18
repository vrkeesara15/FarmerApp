import 'package:flutter/material.dart';

import '../i18n/generated/core_localizations.dart';
import '../theme/app_theme.dart';
import '../tokens/tokens.g.dart';

/// Organic or chemical treatment.
enum TreatmentKind {
  /// Organic / cultural practice.
  organic,

  /// Chemical (pesticide, fungicide).
  chemical,
}

/// Personal protective equipment pictograms.
enum Ppe {
  /// Gloves.
  gloves,

  /// Mask.
  mask,

  /// Goggles.
  goggles,
}

/// Treatment recommendation card with dose per acre and per 15 L tank,
/// safety interval and PPE icons (SPEC 13.1 `TreatmentCard`).
class TreatmentCard extends StatelessWidget {
  /// Creates the card.
  const TreatmentCard({
    required this.name,
    required this.kind,
    required this.dosePerAcre,
    required this.dosePerTank,
    this.activeIngredient,
    this.safetyIntervalDays,
    this.ppe = const <Ppe>{},
    super.key,
  });

  /// Treatment / product name.
  final String name;

  /// Organic or chemical.
  final TreatmentKind kind;

  /// Active ingredient, e.g. `Imidacloprid 17.8% SL`.
  final String? activeIngredient;

  /// Pre-formatted dose per acre, e.g. `100 ml`.
  final String dosePerAcre;

  /// Pre-formatted dose per 15 L tank, e.g. `5 ml`.
  final String dosePerTank;

  /// Pre-harvest interval in days.
  final int? safetyIntervalDays;

  /// PPE to wear.
  final Set<Ppe> ppe;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final p = app.palette;
    final l10n = CoreLocalizations.of(context);
    final organic = kind == TreatmentKind.organic;
    final tagColor = organic ? p.statusSuccess : p.statusInfo;
    final tagContainer = app.tint(
      organic ? p.statusSuccessContainer : p.statusInfoContainer,
    );

    return Container(
      padding: const EdgeInsets.all(Tokens.space4),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(Tokens.radiusCard),
        border: Border.fromBorderSide(app.borderSide),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: Tokens.space2,
                  vertical: Tokens.space1,
                ),
                decoration: BoxDecoration(
                  color: tagContainer,
                  borderRadius: BorderRadius.circular(Tokens.radiusPill),
                  border: Border.all(color: tagColor, width: app.borderWidth),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(
                      organic ? Icons.spa_outlined : Icons.science_outlined,
                      size: Tokens.space4,
                      color: tagColor,
                    ),
                    const SizedBox(width: Tokens.space1),
                    Text(
                      organic ? l10n.treatmentOrganic : l10n.treatmentChemical,
                      style: app.text.caption.copyWith(
                        color: tagColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: Tokens.space2),
          Text(name, style: app.text.heading),
          if (activeIngredient != null) ...<Widget>[
            const SizedBox(height: Tokens.space1),
            Text(
              '${l10n.treatmentActiveIngredient}: $activeIngredient',
              style: app.text.caption.copyWith(color: p.textSecondary),
            ),
          ],
          const SizedBox(height: Tokens.space3),
          Row(
            children: <Widget>[
              Expanded(
                child: _Dose(
                  icon: Icons.landscape_outlined,
                  label: l10n.treatmentDosePerAcre,
                  value: dosePerAcre,
                ),
              ),
              const SizedBox(width: Tokens.space2),
              Expanded(
                child: _Dose(
                  icon: Icons.water_drop_outlined,
                  label: l10n.treatmentDosePerTank,
                  value: dosePerTank,
                ),
              ),
            ],
          ),
          if (safetyIntervalDays != null) ...<Widget>[
            const SizedBox(height: Tokens.space3),
            Row(
              children: <Widget>[
                Icon(Icons.event_busy_outlined, color: p.statusWarning),
                const SizedBox(width: Tokens.space2),
                Expanded(
                  child: Text(
                    l10n.treatmentSafetyInterval(safetyIntervalDays!),
                    style: app.text.body,
                  ),
                ),
              ],
            ),
          ],
          if (ppe.isNotEmpty) ...<Widget>[
            const SizedBox(height: Tokens.space3),
            Wrap(
              spacing: Tokens.space3,
              runSpacing: Tokens.space1,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: <Widget>[
                Text(
                  l10n.treatmentPpeTitle,
                  style: app.text.label.copyWith(color: p.textSecondary),
                ),
                for (final item in Ppe.values)
                  if (ppe.contains(item))
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(switch (item) {
                          Ppe.gloves => Icons.back_hand_outlined,
                          Ppe.mask => Icons.masks_outlined,
                          Ppe.goggles => Icons.visibility_outlined,
                        }, color: p.statusInfo),
                        const SizedBox(width: Tokens.space1),
                        Text(switch (item) {
                          Ppe.gloves => l10n.treatmentPpeGloves,
                          Ppe.mask => l10n.treatmentPpeMask,
                          Ppe.goggles => l10n.treatmentPpeGoggles,
                        }, style: app.text.caption),
                      ],
                    ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Dose extends StatelessWidget {
  const _Dose({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final p = app.palette;
    return Container(
      padding: const EdgeInsets.all(Tokens.space2),
      decoration: BoxDecoration(
        color: app.tint(p.background),
        borderRadius: BorderRadius.circular(Tokens.radiusInput),
        border: Border.fromBorderSide(app.borderSide),
      ),
      child: Row(
        children: <Widget>[
          Icon(icon, color: p.primary),
          const SizedBox(width: Tokens.space2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  label,
                  style: app.text.caption.copyWith(color: p.textSecondary),
                ),
                Text(value, style: app.text.heading),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

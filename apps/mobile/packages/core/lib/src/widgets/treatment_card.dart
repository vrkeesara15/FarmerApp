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

  /// Full-sleeve clothing, apron or boots.
  clothing,
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
    this.safetyText,
    this.tankPictogram = false,
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

  /// Safety text from the label (DX-009).
  final String? safetyText;

  /// Draws the per-tank dose as a 15 L sprayer tank pictogram with the
  /// dose on it (farmer app F25: "shown visually").
  final bool tankPictogram;

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
                child: tankPictogram
                    ? TankDose(dose: dosePerTank)
                    : _Dose(
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
                          Ppe.clothing => Icons.checkroom_outlined,
                        }, color: p.statusInfo),
                        const SizedBox(width: Tokens.space1),
                        Text(switch (item) {
                          Ppe.gloves => l10n.treatmentPpeGloves,
                          Ppe.mask => l10n.treatmentPpeMask,
                          Ppe.goggles => l10n.treatmentPpeGoggles,
                          Ppe.clothing => l10n.treatmentPpeClothing,
                        }, style: app.text.caption),
                      ],
                    ),
              ],
            ),
          ],
          if (safetyText != null && safetyText!.trim().isNotEmpty) ...<Widget>[
            const SizedBox(height: Tokens.space2),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(Icons.health_and_safety_outlined, color: p.statusWarning),
                const SizedBox(width: Tokens.space2),
                Expanded(
                  child: Text(
                    safetyText!,
                    key: const Key('treatment-safety-text'),
                    style: app.text.caption,
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

/// A 15 L knapsack sprayer tank with the per-tank dose written on it
/// (F25: the dose "shown visually"; NF-010 low literacy).
class TankDose extends StatelessWidget {
  /// Creates the pictogram.
  const TankDose({required this.dose, super.key});

  /// Pre-formatted dose per 15 L tank, e.g. `5 ml`.
  final String dose;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final p = app.palette;
    final l10n = CoreLocalizations.of(context);
    return Semantics(
      container: true,
      label: '${l10n.treatmentDosePerTank}: $dose',
      excludeSemantics: true,
      child: Container(
        key: const Key('treatment-tank'),
        padding: const EdgeInsets.all(Tokens.space2),
        decoration: BoxDecoration(
          color: app.tint(p.background),
          borderRadius: BorderRadius.circular(Tokens.radiusInput),
          border: Border.fromBorderSide(app.borderSide),
        ),
        child: Row(
          children: <Widget>[
            SizedBox(
              width: Tokens.space8,
              height: Tokens.space12,
              child: CustomPaint(
                painter: _TankPainter(
                  outline: p.primary,
                  fill: p.statusInfo.withValues(alpha: 0.35),
                  width: app.borderWidth + 0.5,
                ),
              ),
            ),
            const SizedBox(width: Tokens.space2),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    l10n.treatmentDosePerTank,
                    style: app.text.caption.copyWith(color: p.textSecondary),
                  ),
                  Text(dose, style: app.text.heading),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Knapsack tank: body with a cap, filled with water, a "15 L" mark line.
class _TankPainter extends CustomPainter {
  const _TankPainter({
    required this.outline,
    required this.fill,
    required this.width,
  });

  final Color outline;
  final Color fill;
  final double width;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = outline
      ..style = PaintingStyle.stroke
      ..strokeWidth = width;
    final body = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, size.height * 0.18, size.width, size.height * 0.82),
      Radius.circular(size.width * 0.25),
    );
    canvas
      ..save()
      ..clipRRect(body)
      ..drawRect(
        Rect.fromLTWH(0, size.height * 0.4, size.width, size.height),
        Paint()..color = fill,
      )
      ..restore()
      ..drawRRect(body, stroke)
      ..drawRect(
        Rect.fromLTWH(
          size.width * 0.3,
          0,
          size.width * 0.4,
          size.height * 0.18,
        ),
        stroke,
      )
      ..drawLine(
        Offset(size.width * 0.15, size.height * 0.4),
        Offset(size.width * 0.85, size.height * 0.4),
        stroke,
      );
  }

  @override
  bool shouldRepaint(_TankPainter oldDelegate) =>
      outline != oldDelegate.outline ||
      fill != oldDelegate.fill ||
      width != oldDelegate.width;
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

import 'package:flutter/material.dart';

import '../i18n/generated/core_localizations.dart';
import '../theme/app_theme.dart';
import '../tokens/tokens.g.dart';
import 'confidence_band.dart';
import 'internal/dashed_border.dart';

/// One symptom in the "check these signs" list.
@immutable
class SymptomCheck {
  /// Creates the symptom.
  const SymptomCheck({required this.label, required this.present});

  /// Localised symptom text.
  final String label;

  /// Whether it was observed.
  final bool present;
}

/// Diagnosis result with problem name, confidence band and symptom checklist
/// (SPEC 13.1 `DiagnosisResultCard`).
///
/// When [confidence] is [ConfidenceLevel.low] the card is in the provisional
/// state: dashed border and an "expert will confirm" note.
class DiagnosisResultCard extends StatelessWidget {
  /// Creates the card.
  const DiagnosisResultCard({
    required this.problemName,
    required this.confidence,
    this.localName,
    this.symptoms = const <SymptomCheck>[],
    this.image,
    super.key,
  });

  /// Problem name (already localised or scientific).
  final String problemName;

  /// Name in the farmer's language if different.
  final String? localName;

  /// Confidence level.
  final ConfidenceLevel confidence;

  /// Symptom checklist.
  final List<SymptomCheck> symptoms;

  /// Optional reference photo.
  final ImageProvider<Object>? image;

  /// True when the diagnosis is provisional.
  bool get provisional => confidence == ConfidenceLevel.low;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final p = app.palette;
    final l10n = CoreLocalizations.of(context);

    final body = Padding(
      padding: const EdgeInsets.all(Tokens.space4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                width: Tokens.space12 + Tokens.space4,
                height: Tokens.space12 + Tokens.space4,
                decoration: BoxDecoration(
                  color: app.tint(p.primaryContainer),
                  borderRadius: BorderRadius.circular(Tokens.radiusInput),
                  image: image == null
                      ? null
                      : DecorationImage(image: image!, fit: BoxFit.cover),
                ),
                child: image == null
                    ? Icon(Icons.eco_outlined, color: p.primary)
                    : null,
              ),
              const SizedBox(width: Tokens.space3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      l10n.diagnosisProblem,
                      style: app.text.caption.copyWith(color: p.textSecondary),
                    ),
                    Text(problemName, style: app.text.title),
                    if (localName != null)
                      Text(
                        localName!,
                        style: app.text.body.copyWith(color: p.textSecondary),
                      ),
                    const SizedBox(height: Tokens.space2),
                    ConfidenceBand(level: confidence),
                  ],
                ),
              ),
            ],
          ),
          if (provisional) ...<Widget>[
            const SizedBox(height: Tokens.space3),
            Row(
              children: <Widget>[
                Icon(Icons.schedule_outlined, color: p.textSecondary),
                const SizedBox(width: Tokens.space2),
                Expanded(
                  child: Text(
                    l10n.diagnosisProvisionalNote,
                    style: app.text.body.copyWith(color: p.textSecondary),
                  ),
                ),
              ],
            ),
          ],
          if (symptoms.isNotEmpty) ...<Widget>[
            const SizedBox(height: Tokens.space4),
            Text(l10n.diagnosisSymptomsTitle, style: app.text.heading),
            const SizedBox(height: Tokens.space2),
            for (final s in symptoms)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: Tokens.space1),
                child: Row(
                  children: <Widget>[
                    Icon(
                      s.present
                          ? Icons.check_box_outlined
                          : Icons.check_box_outline_blank,
                      color: s.present ? p.statusSuccess : p.textMuted,
                    ),
                    const SizedBox(width: Tokens.space2),
                    Expanded(child: Text(s.label, style: app.text.body)),
                  ],
                ),
              ),
          ],
        ],
      ),
    );

    if (provisional) {
      return DashedBorder(
        color: p.confidenceLow,
        strokeWidth: app.borderWidth + 1,
        radius: Tokens.radiusCard,
        child: Material(
          color: p.surface,
          borderRadius: BorderRadius.circular(Tokens.radiusCard),
          child: body,
        ),
      );
    }
    return Material(
      color: p.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Tokens.radiusCard),
        side: app.borderSide,
      ),
      child: body,
    );
  }
}

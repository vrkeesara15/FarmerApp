import 'package:flutter/material.dart';

import '../i18n/generated/core_localizations.dart';
import '../theme/app_theme.dart';
import '../tokens/tokens.g.dart';

/// Wizard progress header: "Step n of N", segmented bar and step title
/// (SPEC 13.1 `Stepper`; named `AppStepper` to avoid clashing with Flutter's
/// `Stepper`).
class AppStepper extends StatelessWidget {
  /// Creates the stepper.
  const AppStepper({
    required this.steps,
    required this.currentIndex,
    super.key,
  });

  /// Localised step titles in order.
  final List<String> steps;

  /// Zero-based current step.
  final int currentIndex;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final p = app.palette;
    final l10n = CoreLocalizations.of(context);
    final total = steps.length;
    final current = currentIndex.clamp(0, total - 1);
    return Semantics(
      label: '${l10n.stepperStepOf(current + 1, total)}: ${steps[current]}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            l10n.stepperStepOf(current + 1, total),
            style: app.text.label.copyWith(color: p.textSecondary),
          ),
          const SizedBox(height: Tokens.space2),
          Row(
            children: <Widget>[
              for (var i = 0; i < total; i++) ...<Widget>[
                if (i > 0) const SizedBox(width: Tokens.space1),
                Expanded(
                  child: Container(
                    height: Tokens.space2,
                    decoration: BoxDecoration(
                      color: i <= current ? p.primary : app.tint(p.border),
                      borderRadius: BorderRadius.circular(Tokens.radiusPill),
                      border: app.isSunlight
                          ? Border.all(color: p.border)
                          : null,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: Tokens.space2),
          Text(steps[current], style: app.text.title),
        ],
      ),
    );
  }
}

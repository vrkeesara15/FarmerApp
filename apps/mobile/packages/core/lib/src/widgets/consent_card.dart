import 'package:flutter/material.dart';

import '../i18n/generated/core_localizations.dart';
import '../theme/app_theme.dart';
import '../tokens/tokens.g.dart';

/// One consent decision (A21d, F-side consent later): title, plain-language
/// body, Required / Optional badge, a "Read aloud" button (audio playback
/// lands with NF-009; the button is part of the layout now) and the toggle.
class ConsentCard extends StatelessWidget {
  /// Creates the card.
  const ConsentCard({
    required this.title,
    required this.body,
    required this.required,
    required this.granted,
    required this.onChanged,
    this.notice,
    this.onReadAloud,
    this.readAloud,
    this.agreeLabel,
    this.toggleKey,
    super.key,
  });

  /// Short title ("Use my data to give crop advice").
  final String title;

  /// One-line description.
  final String body;

  /// Longer plain-language notice in the farmer's language.
  final String? notice;

  /// Required (data) or optional (marketing).
  final bool required;

  /// Current decision.
  final bool granted;

  /// Toggle handler.
  final ValueChanged<bool> onChanged;

  /// Speaker button handler; the button is shown disabled when null.
  final VoidCallback? onReadAloud;

  /// Replaces the built-in "Read aloud" button (the farmer app passes an
  /// `AudioButton` that knows whether a voice exists, NF-009).
  final Widget? readAloud;

  /// Label next to the switch; defaults to "Farmer agrees" (officer
  /// surfaces). The farmer app says "I agree".
  final String? agreeLabel;

  /// Key for the switch (tests).
  final Key? toggleKey;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final p = app.palette;
    final l10n = CoreLocalizations.of(context);
    final badgeColor = required ? p.statusWarning : p.textSecondary;
    return Semantics(
      container: true,
      label:
          '$title, ${required ? l10n.consentRequired : l10n.consentOptional}',
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(Tokens.space4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(child: Text(title, style: app.text.heading)),
                  const SizedBox(width: Tokens.space2),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: Tokens.space2,
                      vertical: Tokens.space1,
                    ),
                    decoration: BoxDecoration(
                      color: required
                          ? app.tint(p.statusWarningContainer)
                          : p.surface,
                      borderRadius: BorderRadius.circular(Tokens.radiusPill),
                      border: Border.all(
                        color: badgeColor,
                        width: app.borderWidth,
                      ),
                    ),
                    child: Text(
                      required ? l10n.consentRequired : l10n.consentOptional,
                      style: app.text.caption.copyWith(
                        color: badgeColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Tokens.space2),
              Text(body, style: app.text.body),
              if (notice != null) ...<Widget>[
                const SizedBox(height: Tokens.space2),
                Text(
                  notice!,
                  style: app.text.body.copyWith(color: p.textSecondary),
                ),
              ],
              const SizedBox(height: Tokens.space2),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child:
                    readAloud ??
                    TextButton.icon(
                      onPressed: onReadAloud,
                      style: TextButton.styleFrom(
                        foregroundColor: p.primary,
                        minimumSize: const Size(
                          Tokens.sizeTouchTargetMin,
                          Tokens.sizeTouchTargetMin,
                        ),
                        textStyle: app.text.label,
                      ),
                      icon: const Icon(Icons.volume_up_outlined),
                      label: Text(l10n.consentReadAloud),
                    ),
              ),
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      agreeLabel ?? l10n.regConsentGiven,
                      style: app.text.label.copyWith(color: p.textSecondary),
                    ),
                  ),
                  const SizedBox(width: Tokens.space2),
                  Switch(
                    key: toggleKey,
                    value: granted,
                    onChanged: onChanged,
                    activeTrackColor: p.primary,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

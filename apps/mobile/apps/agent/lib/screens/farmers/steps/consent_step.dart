import 'dart:async';

import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../wizard_copy.dart';

/// A21d: two separate consent cards (data: required; marketing: optional)
/// with a read-aloud button and the plain-language notice in the farmer's
/// chosen language (NF-010). Audio playback arrives with NF-009.
class ConsentStep extends ConsumerWidget {
  /// Creates the step.
  const ConsentStep({this.showIssues = false, super.key});

  /// Show validation errors (after a failed Next).
  final bool showIssues;

  /// Strings in the farmer's language (falls back to the UI language).
  static CoreLocalizations farmerCopy(BuildContext context, String? code) {
    if (code != null) {
      try {
        return lookupCoreLocalizations(Locale(code));
      } on FlutterError {
        // Unsupported language: fall through.
      }
    }
    return CoreLocalizations.of(context);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = context.app;
    final p = app.palette;
    final l10n = CoreLocalizations.of(context);
    final state = ref.watch(registrationProvider);
    final wizard = ref.read(registrationProvider.notifier);
    final draft = state.draft!;
    final farmer = farmerCopy(context, draft.language);
    final issue = showIssues && !draft.consentData;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          l10n.regConsentIntro,
          style: app.text.body.copyWith(color: p.textSecondary),
        ),
        const SizedBox(height: Tokens.space3),
        ConsentCard(
          toggleKey: const Key('consent-data'),
          title: farmer.consentDataCardTitle,
          body: farmer.consentDataCardBody,
          notice: farmer.regConsentNotice,
          required: true,
          granted: draft.consentData,
          onChanged: (v) => unawaited(wizard.setConsentData(granted: v)),
          onReadAloud: () {
            // Audio prompt playback lands with NF-009 (TTS assets).
          },
        ),
        if (issue) ...<Widget>[
          const SizedBox(height: Tokens.space2),
          NoticeBox(
            text: l10n.regIssueConsent,
            icon: Icons.error_outline,
            color: p.statusDanger,
            container: p.statusDangerContainer,
          ),
        ],
        const SizedBox(height: Tokens.space3),
        ConsentCard(
          toggleKey: const Key('consent-marketing'),
          title: farmer.consentOffersCardTitle,
          body: farmer.consentOffersCardBody,
          notice: farmer.regConsentMarketingNotice,
          required: false,
          granted: draft.consentMarketing,
          onChanged: (v) => unawaited(wizard.setConsentMarketing(granted: v)),
          onReadAloud: () {
            // Audio prompt playback lands with NF-009 (TTS assets).
          },
        ),
      ],
    );
  }
}

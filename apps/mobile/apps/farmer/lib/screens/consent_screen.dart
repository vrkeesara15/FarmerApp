import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../router.dart';
import '../widgets/kisan_widgets.dart';

/// F04 Consent (FM-002): two separate cards in the chosen language, each
/// with its own read-aloud button. "Use my data to give crop advice" is
/// required to continue; "Send me offers and tips" is optional and can be
/// withdrawn later in F70. Recorded online (`channel: app`, the tenant's
/// consent version) or queued in the outbox when offline. Two decisions.
class ConsentScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const ConsentScreen({super.key});

  @override
  ConsumerState<ConsentScreen> createState() => _ConsentScreenState();
}

class _ConsentScreenState extends ConsumerState<ConsentScreen> {
  bool _data = false;
  bool _marketing = false;
  bool _busy = false;

  Future<void> _continue() async {
    final l10n = CoreLocalizations.of(context);
    final language = Localizations.localeOf(context).languageCode;
    setState(() => _busy = true);
    final repo = ref.read(kisanRepositoryProvider);
    final data = await repo.recordConsent(
      ConsentPurposes.data,
      granted: true,
      language: language,
    );
    final marketing = data == KisanWrite.refused || data == KisanWrite.offline
        ? data
        : await repo.recordConsent(
            ConsentPurposes.marketing,
            granted: _marketing,
            language: language,
          );
    if (!mounted) return;
    setState(() => _busy = false);
    if (data == KisanWrite.refused || marketing == KisanWrite.refused) {
      showKisanMessage(context, l10n.kisanSaveFailed);
      return;
    }
    if (data == KisanWrite.offline) {
      showKisanMessage(context, l10n.kisanNeedsInternet);
      return;
    }
    if (data == KisanWrite.queued) {
      showKisanMessage(context, l10n.kisanSavedWillSend);
    }
    final next = await repo.welcomeDone() ? AppRoutes.home : AppRoutes.welcome;
    if (mounted) context.go(next);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final l10n = CoreLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.kisanConsentTitle)),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            if (ref.watch(offlineProvider)) const OfflineBanner(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(Tokens.spaceScreenPadding),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    SpokenText(
                      promptId: 'f04_intro',
                      text: l10n.kisanConsentIntro,
                    ),
                    const SizedBox(height: Tokens.space2),
                    ConsentCard(
                      key: const Key('consent-card-data'),
                      title: l10n.consentDataCardTitle,
                      body: l10n.consentDataCardBody,
                      notice: l10n.kisanConsentDataNotice,
                      required: true,
                      granted: _data,
                      agreeLabel: l10n.kisanConsentAgree,
                      toggleKey: const Key('consent-data'),
                      readAloud: AudioButton(
                        promptId: 'f04_data',
                        label: l10n.consentReadAloud,
                        text:
                            '${l10n.consentDataCardTitle}. '
                            '${l10n.consentDataCardBody} '
                            '${l10n.kisanConsentDataNotice}',
                      ),
                      onChanged: (v) => setState(() => _data = v),
                    ),
                    const SizedBox(height: Tokens.space3),
                    ConsentCard(
                      key: const Key('consent-card-marketing'),
                      title: l10n.consentOffersCardTitle,
                      body: l10n.consentOffersCardBody,
                      notice: l10n.kisanConsentOffersNotice,
                      required: false,
                      granted: _marketing,
                      agreeLabel: l10n.kisanConsentAgree,
                      toggleKey: const Key('consent-marketing'),
                      readAloud: AudioButton(
                        promptId: 'f04_offers',
                        label: l10n.consentReadAloud,
                        text:
                            '${l10n.consentOffersCardTitle}. '
                            '${l10n.consentOffersCardBody} '
                            '${l10n.kisanConsentOffersNotice}',
                      ),
                      onChanged: (v) => setState(() => _marketing = v),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(Tokens.spaceScreenPadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  if (!_data) ...<Widget>[
                    Text(
                      l10n.kisanConsentDataNeeded,
                      key: const Key('consent-data-needed'),
                      textAlign: TextAlign.center,
                      style: app.text.label.copyWith(
                        color: app.palette.textSecondary,
                      ),
                    ),
                    const SizedBox(height: Tokens.space2),
                  ],
                  AppButton(
                    key: const Key('consent-continue'),
                    label: l10n.actionContinue,
                    icon: Icons.arrow_forward,
                    loading: _busy,
                    onPressed: _data && !_busy ? _continue : null,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

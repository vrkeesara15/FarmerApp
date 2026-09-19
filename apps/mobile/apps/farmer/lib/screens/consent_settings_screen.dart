import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../router.dart';
import '../widgets/kisan_widgets.dart';

/// F70 consent settings (FM-002): the current state of both consents; the
/// offers and tips consent can be withdrawn (a new consent row with
/// `granted: false`) or given again at any time. The data consent is
/// needed to use the app; stopping it means deleting the account.
class ConsentSettingsScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const ConsentSettingsScreen({super.key});

  @override
  ConsumerState<ConsentSettingsScreen> createState() =>
      _ConsentSettingsScreenState();
}

class _ConsentSettingsScreenState extends ConsumerState<ConsentSettingsScreen> {
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    ref
        .read(kisanRepositoryProvider)
        .refreshProfile()
        .catchError((Object _) => false);
  }

  Future<void> _setMarketing(bool granted) async {
    final l10n = CoreLocalizations.of(context);
    final language = Localizations.localeOf(context).languageCode;
    setState(() => _busy = true);
    final result = await ref
        .read(kisanRepositoryProvider)
        .recordConsent(
          ConsentPurposes.marketing,
          granted: granted,
          language: language,
        );
    if (!mounted) return;
    setState(() => _busy = false);
    showKisanMessage(context, switch (result) {
      KisanWrite.done => granted ? l10n.kisanOffersOn : l10n.kisanOffersOff,
      KisanWrite.queued => l10n.kisanSavedWillSend,
      KisanWrite.offline => l10n.kisanNeedsInternet,
      KisanWrite.refused => l10n.kisanSaveFailed,
    });
  }

  String _state(CoreLocalizations l10n, ConsentEntry? e) {
    if (e == null) return l10n.consentNotGiven;
    final when = formatDateIst(e.at);
    if (e.pending) return l10n.kisanConsentPending;
    return e.granted
        ? l10n.kisanConsentGivenOn(when)
        : l10n.kisanConsentWithdrawnOn(when);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final p = app.palette;
    final l10n = CoreLocalizations.of(context);
    final consents = ref.watch(kisanConsentsProvider).value;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.kisanConsentSettings)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(Tokens.spaceScreenPadding),
          children: <Widget>[
            KisanCard(
              key: const Key('consent-state-data'),
              icon: Icons.verified_user_outlined,
              title: l10n.consentDataCardTitle,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    _state(l10n, consents?.data),
                    key: const Key('consent-data-state'),
                    style: app.text.body,
                  ),
                  const SizedBox(height: Tokens.space2),
                  Text(
                    l10n.kisanConsentDataHowToStop,
                    style: app.text.caption.copyWith(color: p.textSecondary),
                  ),
                  TextButton(
                    onPressed: () => context.push(AppRoutes.deleteAccount),
                    child: Text(l10n.kisanDeleteAccount),
                  ),
                ],
              ),
            ),
            const SizedBox(height: Tokens.space3),
            ConsentCard(
              key: const Key('consent-card-marketing'),
              title: l10n.consentOffersCardTitle,
              body: l10n.consentOffersCardBody,
              notice: _state(l10n, consents?.marketing),
              required: false,
              granted: consents?.marketingGranted ?? false,
              agreeLabel: l10n.kisanConsentAgree,
              toggleKey: const Key('consent-marketing'),
              readAloud: AudioButton(
                promptId: 'f70_offers',
                label: l10n.consentReadAloud,
                text:
                    '${l10n.consentOffersCardTitle}. '
                    '${l10n.consentOffersCardBody} '
                    '${l10n.kisanConsentOffersNotice}',
              ),
              onChanged: _busy ? (_) {} : _setMarketing,
            ),
          ],
        ),
      ),
    );
  }
}

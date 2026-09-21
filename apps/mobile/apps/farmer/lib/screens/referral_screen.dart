import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../widgets/kisan_widgets.dart';

/// F71 Refer a friend (FM-013), opened from F70 Me.
///
/// The farmer sees their own invite code and shares it — WhatsApp through
/// the OS share sheet, SMS through an `sms:` link — with a ready-made
/// message that carries the link. There is **no text field anywhere**: a
/// farmer screen may not ask for typing (NF-010), so the invited farmer
/// gets the code from the link, not from copying it down.
///
/// Every share also records a `pending` referral, so the invite is already
/// on the referrer's side of the ledger before anybody registers.
class ReferralScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const ReferralScreen({super.key});

  @override
  ConsumerState<ReferralScreen> createState() => _ReferralScreenState();
}

class _ReferralScreenState extends ConsumerState<ReferralScreen> {
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    ref
        .read(marketRepositoryProvider)
        .refreshReferral()
        .catchError((Object _) => false);
  }

  String _message(MyReferral referral, CoreLocalizations l10n) =>
      l10n.referralShareMessage(referral.shareLink, referral.code);

  Future<void> _share(MyReferral referral) async {
    final l10n = CoreLocalizations.of(context);
    final text = _message(referral, l10n);
    setState(() => _busy = true);
    await ref.read(textSharerProvider).share(text);
    await ref.read(marketRepositoryProvider).recordInvite();
    if (!mounted) return;
    setState(() => _busy = false);
  }

  Future<void> _sms(MyReferral referral) async {
    final l10n = CoreLocalizations.of(context);
    final body = Uri.encodeComponent(_message(referral, l10n));
    setState(() => _busy = true);
    final opened = await ref.read(urlOpenerProvider).open('sms:?body=$body');
    await ref.read(marketRepositoryProvider).recordInvite();
    if (!mounted) return;
    setState(() => _busy = false);
    if (!opened) showKisanMessage(context, l10n.kisanCouldNotOpen);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final l10n = CoreLocalizations.of(context);
    final cached = ref.watch(myReferralProvider).value;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.referralTitle)),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            if (ref.watch(offlineProvider)) const OfflineBanner(),
            Expanded(
              child: cached == null
                  ? EmptyState(
                      icon: Icons.card_giftcard_outlined,
                      title: l10n.referralTitle,
                      help: l10n.referralIntro,
                    )
                  : ListView(
                      padding: const EdgeInsets.all(Tokens.spaceScreenPadding),
                      children: <Widget>[
                        Text(l10n.referralIntro, style: app.text.body),
                        const SizedBox(height: Tokens.space2),
                        AudioButton(
                          promptId: 'f71_intro',
                          text: l10n.referralIntro,
                        ),
                        const SizedBox(height: Tokens.space4),
                        _CodeCard(code: cached.value.code),
                        const SizedBox(height: Tokens.space4),
                        if (!cached.value.enabled)
                          Text(
                            l10n.referralOff,
                            key: const Key('referral-off'),
                            style: app.text.body.copyWith(
                              color: app.palette.textSecondary,
                            ),
                          )
                        else ...<Widget>[
                          AppButton(
                            key: const Key('referral-whatsapp'),
                            label: l10n.referralShareWhatsApp,
                            icon: Icons.share_outlined,
                            onPressed: _busy
                                ? null
                                : () => _share(cached.value),
                          ),
                          const SizedBox(height: Tokens.space3),
                          AppButton(
                            key: const Key('referral-sms'),
                            label: l10n.referralShareSms,
                            variant: AppButtonVariant.secondary,
                            icon: Icons.sms_outlined,
                            onPressed: _busy ? null : () => _sms(cached.value),
                          ),
                        ],
                        const SizedBox(height: Tokens.space4),
                        _Counts(referral: cached.value),
                        const SizedBox(height: Tokens.space3),
                        Text(
                          cached.value.rewardNote ?? l10n.referralRewardNone,
                          key: const Key('referral-reward-note'),
                          style: app.text.caption.copyWith(
                            color: app.palette.textSecondary,
                          ),
                        ),
                        const SizedBox(height: Tokens.space3),
                        AsOfLabel(cached.asOf),
                        const SizedBox(height: Tokens.space8),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CodeCard extends StatelessWidget {
  const _CodeCard({required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final p = app.palette;
    final l10n = CoreLocalizations.of(context);
    return Container(
      key: const Key('referral-code'),
      padding: const EdgeInsets.all(Tokens.space4),
      decoration: BoxDecoration(
        color: app.tint(p.primaryContainer),
        borderRadius: BorderRadius.circular(Tokens.radiusCard),
        border: Border.fromBorderSide(app.borderSide),
      ),
      child: Column(
        children: <Widget>[
          Text(
            l10n.referralYourCode,
            style: app.text.caption.copyWith(color: p.textSecondary),
          ),
          const SizedBox(height: Tokens.space2),
          Text(
            code,
            style: app.text.display.copyWith(
              color: p.primary,
              letterSpacing: 4,
            ),
          ),
        ],
      ),
    );
  }
}

class _Counts extends StatelessWidget {
  const _Counts({required this.referral});

  final MyReferral referral;

  @override
  Widget build(BuildContext context) {
    final l10n = CoreLocalizations.of(context);
    return Row(
      key: const Key('referral-counts'),
      children: <Widget>[
        Expanded(
          child: StatTile(
            value: '${referral.invited}',
            label: l10n.referralInvited(referral.invited),
          ),
        ),
        const SizedBox(width: Tokens.space2),
        Expanded(
          child: StatTile(
            value: '${referral.attributed}',
            label: l10n.referralJoined(referral.attributed),
          ),
        ),
        const SizedBox(width: Tokens.space2),
        Expanded(
          child: StatTile(
            value: '${referral.rewarded}',
            label: l10n.referralRewarded(referral.rewarded),
          ),
        ),
      ],
    );
  }
}

import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../orders/commerce_copy.dart';

/// A54 Payment link sent (FA-021): the channel used (SMS / WhatsApp), the
/// amount and link, "Check payment" (one status call) and resend through
/// either channel.
class LinkScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const LinkScreen({required this.paymentId, super.key});

  /// Local + server payment id.
  final String paymentId;

  @override
  ConsumerState<LinkScreen> createState() => _LinkScreenState();
}

class _LinkScreenState extends ConsumerState<LinkScreen> {
  bool _busy = false;

  Future<void> _resend(String channel) async {
    setState(() => _busy = true);
    final out = await ref
        .read(paymentRepositoryProvider)
        .resendLink(widget.paymentId, channel: channel);
    if (!mounted) return;
    setState(() => _busy = false);
    final l10n = CoreLocalizations.of(context);
    if (out.paymentId != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.linkResent)));
      context.pushReplacement(CommerceRoutes.link(out.paymentId!));
    } else {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.checkoutNetworkError)));
    }
  }

  Future<void> _check() async {
    setState(() => _busy = true);
    final repo = ref.read(paymentRepositoryProvider);
    final out = await repo.api.status(widget.paymentId);
    if (out.result == PaymentCallResult.ok) {
      final state = out.body['state'];
      final phase = switch (state) {
        'paid' => UpiPollPhase.paid,
        'failed' => UpiPollPhase.failed,
        _ => UpiPollPhase.waiting,
      };
      await repo.applyPoll(
        widget.paymentId,
        UpiPollState(
          phase,
          failureReason: out.body['failure_reason'] as String?,
        ),
      );
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final pal = app.palette;
    final l10n = CoreLocalizations.of(context);
    final offline = ref.watch(offlineProvider);
    final view = ref.watch(paymentViewProvider(widget.paymentId)).value;
    final p = view?.payment;
    final paid = p?.status == PaymentStatuses.paid;
    final channel = p?.sentVia == 'whatsapp'
        ? l10n.channelWhatsapp
        : l10n.channelSms;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.linkTitle)),
      bottomNavigationBar: p == null
          ? null
          : BottomActions(
              children: <Widget>[
                if (!paid)
                  AppButton(
                    key: const Key('link-check'),
                    label: l10n.linkCheckStatus,
                    icon: Icons.refresh,
                    variant: AppButtonVariant.secondary,
                    loading: _busy,
                    onPressed: offline || _busy ? null : _check,
                  ),
                AppButton(
                  key: const Key('link-done'),
                  label: l10n.paymentDone,
                  icon: Icons.check,
                  onPressed: () {
                    if (p.orderId != null) {
                      refreshOrder(ref, p.orderId!);
                      context.go(CommerceRoutes.order(p.orderId!));
                    } else {
                      context.go(CommerceRoutes.khata(p.farmerId ?? ''));
                    }
                  },
                ),
              ],
            ),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            const OfflineBannerLive(),
            Expanded(
              child: p == null
                  ? const Center(child: CircularProgressIndicator())
                  : ListView(
                      padding: const EdgeInsets.all(Tokens.spaceScreenPadding),
                      children: <Widget>[
                        Icon(
                          paid
                              ? Icons.check_circle_outline
                              : Icons.send_outlined,
                          size: Tokens.space12,
                          color: paid ? pal.statusSuccess : pal.primary,
                        ),
                        const SizedBox(height: Tokens.space2),
                        Text(
                          paid ? l10n.upiPaid : l10n.linkSentTitle,
                          key: const Key('link-state'),
                          textAlign: TextAlign.center,
                          style: app.text.title,
                        ),
                        const SizedBox(height: Tokens.space2),
                        Text(
                          formatInr(p.amountPaise),
                          textAlign: TextAlign.center,
                          style: app.text.display,
                        ),
                        const SizedBox(height: Tokens.space2),
                        Text(
                          l10n.linkSentVia(channel),
                          key: const Key('link-channel'),
                          textAlign: TextAlign.center,
                          style: app.text.body.copyWith(
                            color: pal.textSecondary,
                          ),
                        ),
                        if (p.shortUrl != null) ...<Widget>[
                          const SizedBox(height: Tokens.space2),
                          SelectableText(
                            p.shortUrl!,
                            textAlign: TextAlign.center,
                            style: app.text.label.copyWith(
                              color: pal.statusInfo,
                            ),
                          ),
                        ],
                        if (p.expiresAt != null && !paid) ...<Widget>[
                          const SizedBox(height: Tokens.space2),
                          Text(
                            l10n.linkValidUntil(
                              formatDateTimeIst(p.expiresAt!),
                            ),
                            textAlign: TextAlign.center,
                            style: app.text.caption.copyWith(
                              color: pal.textSecondary,
                            ),
                          ),
                        ],
                        if (!paid) ...<Widget>[
                          const SizedBox(height: Tokens.space6),
                          Text(l10n.linkResend, style: app.text.heading),
                          const SizedBox(height: Tokens.space2),
                          Row(
                            children: <Widget>[
                              Expanded(
                                child: AppButton(
                                  key: const Key('link-resend-sms'),
                                  label: l10n.channelSms,
                                  icon: Icons.sms_outlined,
                                  variant: AppButtonVariant.secondary,
                                  size: AppButtonSize.medium,
                                  onPressed: offline || _busy
                                      ? null
                                      : () => _resend('sms'),
                                ),
                              ),
                              const SizedBox(width: Tokens.space2),
                              Expanded(
                                child: AppButton(
                                  key: const Key('link-resend-whatsapp'),
                                  label: l10n.channelWhatsapp,
                                  icon: Icons.chat_outlined,
                                  variant: AppButtonVariant.secondary,
                                  size: AppButtonSize.medium,
                                  onPressed: offline || _busy
                                      ? null
                                      : () => _resend('whatsapp'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

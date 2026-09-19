import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../orders/commerce_copy.dart';

/// A56 Credit sale (FA-021 / ST-007): the `payment` credit op's outcome.
/// Queued offline → "checked when online"; applied → on the khata;
/// `credit_limit_exceeded` → approval-needed state with the limit, the
/// balance, the shortfall and "sent to cluster head". The approval request
/// comes back through the change feed (`credit_approval_request`): once it
/// is approved the sync engine resends the op with
/// `credit_approval_request_id` by itself and the screen flips to "on
/// khata"; a rejection is shown. "Check approval" stays as the manual
/// fallback (resend now with the approval id).
class CreditScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const CreditScreen({required this.paymentId, super.key});

  /// The credit payment.
  final String paymentId;

  @override
  ConsumerState<CreditScreen> createState() => _CreditScreenState();
}

class _CreditScreenState extends ConsumerState<CreditScreen> {
  bool _busy = false;

  Future<void> _recheck() async {
    setState(() => _busy = true);
    final l10n = CoreLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final repo = ref.read(paymentRepositoryProvider);
    final requeued = await repo.recheckCredit(widget.paymentId);
    final ran = await syncIfOnline(ref);
    final view = await repo.payment(widget.paymentId);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ran) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.creditOfflineCheck)));
    } else if (requeued && view?.creditBlock != null) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.creditStillPending)));
    }
  }

  Future<void> _cashInstead(PaymentRow p) async {
    await ref.read(paymentRepositoryProvider).discard(p.id);
    if (!mounted) return;
    context.pushReplacement(CommerceRoutes.cash(orderId: p.orderId));
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final pal = app.palette;
    final l10n = CoreLocalizations.of(context);
    final offline = ref.watch(offlineProvider);
    final view = ref.watch(paymentViewProvider(widget.paymentId)).value;
    final p = view?.payment;
    final block = view?.creditBlock;
    final approvalId = block?.approvalRequestId;
    final approval = approvalId == null
        ? null
        : ref.watch(creditApprovalStateProvider(approvalId)).value;
    final state = view?.state;
    final onKhata = state == CollectionState.onKhata;
    final (
      IconData icon,
      Color color,
      String title,
      String body,
    ) = switch (state) {
      CollectionState.approvalNeeded => (
        Icons.hourglass_top,
        pal.statusWarning,
        l10n.creditNeedsApprovalTitle,
        l10n.creditNeedsApprovalBody,
      ),
      CollectionState.onKhata => (
        Icons.check_circle_outline,
        pal.statusSuccess,
        l10n.creditApprovedTitle,
        '',
      ),
      CollectionState.failed => (
        Icons.error_outline,
        pal.statusDanger,
        l10n.collectionStateFailed,
        view?.rejection?.detail ?? '',
      ),
      _ => (
        Icons.cloud_upload_outlined,
        pal.statusInfo,
        l10n.creditTitle,
        l10n.creditQueued,
      ),
    };
    return Scaffold(
      appBar: AppBar(title: Text(l10n.creditTitle)),
      bottomNavigationBar: p == null
          ? null
          : BottomActions(
              children: <Widget>[
                if (block != null) ...<Widget>[
                  AppButton(
                    key: const Key('credit-cash-instead'),
                    label: l10n.creditUseCash,
                    icon: Icons.payments_outlined,
                    variant: AppButtonVariant.secondary,
                    onPressed: _busy ? null : () => _cashInstead(p),
                  ),
                  AppButton(
                    key: const Key('credit-recheck'),
                    label: l10n.creditCheckAgain,
                    icon: Icons.refresh,
                    loading: _busy,
                    onPressed: _busy || offline ? null : _recheck,
                  ),
                ] else
                  AppButton(
                    key: const Key('credit-done'),
                    label: l10n.paymentDone,
                    icon: Icons.check,
                    onPressed: () {
                      if (p.orderId != null) {
                        refreshOrder(ref, p.orderId!);
                        context.go(CommerceRoutes.order(p.orderId!));
                      } else {
                        context.go(CommerceRoutes.orders);
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
                        if (p.farmerId != null)
                          Text(
                            l10n.catalogForFarmer(
                              farmerNameOf(ref, p.farmerId),
                            ),
                            style: app.text.heading,
                          ),
                        const SizedBox(height: Tokens.space3),
                        Container(
                          key: Key('credit-state-${state?.name}'),
                          padding: const EdgeInsets.all(Tokens.space4),
                          decoration: BoxDecoration(
                            color: pal.surface,
                            borderRadius: BorderRadius.circular(
                              Tokens.radiusCard,
                            ),
                            border: Border.all(
                              color: color,
                              width: app.borderWidth,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Row(
                                children: <Widget>[
                                  Icon(icon, color: color),
                                  const SizedBox(width: Tokens.space2),
                                  Expanded(
                                    child: Text(
                                      title,
                                      style: app.text.heading.copyWith(
                                        color: color,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              if (body.isNotEmpty) ...<Widget>[
                                const SizedBox(height: Tokens.space2),
                                Text(body, style: app.text.body),
                              ],
                              const SizedBox(height: Tokens.space3),
                              MoneyRow(
                                key: const Key('credit-amount'),
                                label: l10n.checkoutOrderAmount,
                                paise: p.amountPaise,
                                strong: true,
                              ),
                              if (block != null) ...<Widget>[
                                const Divider(),
                                MoneyRow(
                                  key: const Key('credit-limit'),
                                  label: l10n.creditLimit,
                                  paise: block.limitPaise,
                                ),
                                MoneyRow(
                                  key: const Key('credit-balance'),
                                  label: l10n.creditBalance,
                                  paise: block.balancePaise,
                                ),
                                MoneyRow(
                                  key: const Key('credit-shortfall'),
                                  label: l10n.creditShortfall,
                                  paise: block.shortfallPaise,
                                  strong: true,
                                ),
                                const SizedBox(height: Tokens.space3),
                                if (approval?.approved ?? false)
                                  StatusPill(
                                    key: const Key('credit-approved-sending'),
                                    text: l10n.creditApprovedSending,
                                    color: pal.statusSuccess,
                                  )
                                else if (approval?.rejected ?? false)
                                  StatusPill(
                                    key: const Key('credit-rejected'),
                                    text: l10n.creditRejectedByClusterHead,
                                    color: pal.statusDanger,
                                  )
                                else
                                  StatusPill(
                                    key: const Key('credit-sent'),
                                    text: l10n.creditSentToClusterHead,
                                    color: pal.statusWarning,
                                  ),
                              ],
                              if (onKhata) ...<Widget>[
                                const SizedBox(height: Tokens.space2),
                                StatusPill(
                                  text: l10n.collectionStateOnKhata,
                                  color: pal.statusSuccess,
                                ),
                              ],
                            ],
                          ),
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

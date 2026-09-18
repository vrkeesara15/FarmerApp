import 'dart:async';

import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../orders/commerce_copy.dart';

/// A53 UPI QR (FA-021): the provider's `qr_payload` in UpiQrPanel with the
/// amount and a countdown; polls `GET /v1/payments/{id}` every 3 s (backing
/// off to 10 s, stopping at expiry) → paid / failed / expired.
class UpiScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const UpiScreen({required this.paymentId, super.key});

  /// Local + server payment id.
  final String paymentId;

  @override
  ConsumerState<UpiScreen> createState() => _UpiScreenState();
}

class _UpiScreenState extends ConsumerState<UpiScreen> {
  StreamSubscription<UpiPollState>? _sub;
  UpiPollState _poll = const UpiPollState(UpiPollPhase.waiting);
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_start()));
  }

  Future<void> _start() async {
    final repo = ref.read(paymentRepositoryProvider);
    final view = await repo.payment(widget.paymentId);
    if (!mounted || view == null) return;
    final status = view.payment.status;
    if (status == PaymentStatuses.paid || status == PaymentStatuses.failed) {
      setState(
        () => _poll = UpiPollState(
          status == PaymentStatuses.paid
              ? UpiPollPhase.paid
              : UpiPollPhase.failed,
        ),
      );
      return;
    }
    _sub = repo
        .poller(
          widget.paymentId,
          expiresAt: view.payment.expiresAt,
          sleep: ref.read(upiSleepProvider),
        )
        .run()
        .listen((s) {
          if (!mounted) return;
          setState(() => _poll = s);
          if (s.isFinal) unawaited(repo.applyPoll(widget.paymentId, s));
        });
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    super.dispose();
  }

  Future<void> _newQr(PaymentRow p) async {
    setState(() => _busy = true);
    final out = await ref
        .read(paymentRepositoryProvider)
        .createOnline(targetOf(p), mode: PaymentModes.upiQr);
    if (!mounted) return;
    setState(() => _busy = false);
    if (out.paymentId != null) {
      context.pushReplacement(CommerceRoutes.upi(out.paymentId!));
    } else {
      final l10n = CoreLocalizations.of(context);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.checkoutNetworkError)));
    }
  }

  void _done(PaymentRow p) {
    if (p.orderId != null) {
      refreshOrder(ref, p.orderId!);
      context.go(CommerceRoutes.order(p.orderId!));
    } else if (p.farmerId != null) {
      context.go(CommerceRoutes.khata(p.farmerId!));
    } else {
      context.go(CommerceRoutes.collections);
    }
  }

  void _cash(PaymentRow p) => context.pushReplacement(
    p.orderId != null
        ? CommerceRoutes.cash(orderId: p.orderId)
        : CommerceRoutes.cash(
            farmerId: p.farmerId,
            storeId: p.storeId,
            amountPaise: p.amountPaise,
          ),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = CoreLocalizations.of(context);
    ref.watch(paymentTickProvider);
    final view = ref.watch(paymentViewProvider(widget.paymentId)).value;
    final now = ref.watch(clockProvider)();
    final p = view?.payment;
    final state = switch (_poll.phase) {
      UpiPollPhase.waiting => UpiPaymentState.waiting,
      UpiPollPhase.paid => UpiPaymentState.paid,
      UpiPollPhase.failed || UpiPollPhase.expired => UpiPaymentState.failed,
    };
    final remaining = p?.expiresAt == null
        ? null
        : p!.expiresAt!.difference(now);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.upiTitle)),
      bottomNavigationBar: p == null
          ? null
          : BottomActions(
              children: <Widget>[
                if (state == UpiPaymentState.paid)
                  AppButton(
                    key: const Key('upi-done'),
                    label: l10n.paymentDone,
                    icon: Icons.check,
                    onPressed: () => _done(p),
                  )
                else
                  AppButton(
                    key: const Key('upi-cash-instead'),
                    label: l10n.upiCollectCash,
                    icon: Icons.payments_outlined,
                    variant: AppButtonVariant.secondary,
                    onPressed: () => _cash(p),
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
                          Padding(
                            padding: const EdgeInsets.only(
                              bottom: Tokens.space3,
                            ),
                            child: Text(
                              l10n.catalogForFarmer(
                                farmerNameOf(ref, p.farmerId),
                              ),
                              style: context.app.text.heading,
                            ),
                          ),
                        UpiQrPanel(
                          key: Key('upi-panel-${state.name}'),
                          state: state,
                          amountPaise: p.amountPaise,
                          qrPayload: p.qrPayload ?? '',
                          remaining: remaining == null || remaining.isNegative
                              ? Duration.zero
                              : remaining,
                          statusText: _poll.phase == UpiPollPhase.expired
                              ? l10n.upiExpired
                              : null,
                          onRetry: _busy ? null : () => _newQr(p),
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

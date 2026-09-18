import 'dart:async';

import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../orders/commerce_copy.dart';

/// A52 Payment method (FA-021) for the cart's order, or — with
/// [duesFarmerId] — for khata dues (A58 / A22 "Collect"): amount defaults
/// to the balance, partial allowed up to it.
///
/// UPI QR and payment links need the network (offline they are disabled
/// with the reason); cash and credit are saved on the phone and synced.
class CheckoutScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const CheckoutScreen({this.duesFarmerId, super.key});

  /// Dues mode for this farmer; null = the cart's order.
  final String? duesFarmerId;

  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  PaymentMethod? _method;
  bool _busy = false;
  String? _message;
  final TextEditingController _amount = TextEditingController();
  bool _amountTouched = false;

  bool get _dues => widget.duesFarmerId != null;

  @override
  void initState() {
    super.initState();
    final farmerId = widget.duesFarmerId;
    if (farmerId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final online = await ref.read(connectivityMonitorProvider).isOnline();
        if (online) await ref.read(khataRepositoryProvider).refresh(farmerId);
      });
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  int? _parseRupees(String text) {
    final t = text.trim().replaceAll(',', '');
    if (t.isEmpty) return null;
    final v = double.tryParse(t);
    if (v == null || v <= 0) return null;
    return (v * 100).round();
  }

  Future<void> _submit() async {
    final method = _method;
    if (method == null) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      if (_dues) {
        await _collectDues(method);
      } else {
        await _placeOrder(method);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _placeOrder(PaymentMethod method) async {
    final l10n = CoreLocalizations.of(context);
    final cart = ref.read(cartProvider);
    final farmerId = cart.farmerId;
    if (farmerId == null || cart.lines.isEmpty) return;
    final orders = ref.read(orderRepositoryProvider);
    final payments = ref.read(paymentRepositoryProvider);
    final now = ref.read(clockProvider)();
    final mode = PaymentModes.of(method);
    // Credit is collected by the `payment` op (the order itself is not
    // placed on credit, so the credit gate runs once, on the payment).
    final orderMode = method == PaymentMethod.credit ? null : mode;
    final String orderId;
    if (cart.editingOrderId != null) {
      orderId = cart.editingOrderId!;
      await orders.resubmit(orderId, cart.lines, now: now);
    } else {
      orderId = await orders.place(
        farmerId: farmerId,
        storeId: cart.storeId,
        fulfilment: cart.fulfilment,
        lines: cart.lines,
        paymentMode: orderMode,
        now: now,
      );
    }
    final estimate = cart.totals.totalPaise;
    final target = PaymentTarget.order(
      orderId: orderId,
      farmerId: farmerId,
      storeId: cart.storeId,
    );
    ref.read(cartProvider.notifier).clear();
    if (!mounted) return;
    final router = GoRouter.of(context);
    final messenger = ScaffoldMessenger.of(context);
    switch (method) {
      case PaymentMethod.cash:
        router.go(CommerceRoutes.order(orderId));
        unawaited(router.push(CommerceRoutes.cash(orderId: orderId)));
      case PaymentMethod.credit:
        final paymentId = await payments.collectCredit(
          target,
          expectedPaise: estimate,
        );
        await syncIfOnline(ref);
        router.go(CommerceRoutes.order(orderId));
        unawaited(router.push(CommerceRoutes.credit(paymentId)));
      case PaymentMethod.upiQr:
      case PaymentMethod.paymentLink:
        await syncIfOnline(ref);
        final view = await orders.order(orderId);
        if (view == null || view.rejection != null || view.pendingSync) {
          router.go(CommerceRoutes.order(orderId));
          if (view != null && view.pendingSync) {
            messenger.showSnackBar(
              SnackBar(content: Text(l10n.checkoutOrderNotSynced)),
            );
          }
          return;
        }
        final out = await payments.createOnline(target, mode: mode);
        router.go(CommerceRoutes.order(orderId));
        if (out.paymentId != null) {
          unawaited(
            router.push(
              method == PaymentMethod.upiQr
                  ? CommerceRoutes.upi(out.paymentId!)
                  : CommerceRoutes.link(out.paymentId!),
            ),
          );
        } else {
          messenger.showSnackBar(
            SnackBar(content: Text(_refusal(l10n, out.result, out.code))),
          );
        }
    }
  }

  Future<void> _collectDues(PaymentMethod method) async {
    final l10n = CoreLocalizations.of(context);
    final farmerId = widget.duesFarmerId!;
    final khata = ref.read(khataProvider(farmerId)).value;
    final storeId =
        khata?.collectStoreId ??
        await ref.read(catalogCacheProvider).storeIdForFarmer(farmerId);
    final balance = khata == null || storeId == null
        ? null
        : khata.balanceAt(storeId);
    final amount = _parseRupees(_amount.text) ?? balance;
    if (amount == null || amount <= 0 || storeId == null) {
      setState(() => _message = l10n.checkoutDuesInvalid);
      return;
    }
    if (balance != null && amount > balance) {
      setState(() => _message = l10n.checkoutDuesTooMuch(formatInr(balance)));
      return;
    }
    if (!mounted) return;
    final router = GoRouter.of(context);
    switch (method) {
      case PaymentMethod.cash:
        await router.push(
          CommerceRoutes.cash(
            farmerId: farmerId,
            storeId: storeId,
            amountPaise: amount,
          ),
        );
      case PaymentMethod.upiQr:
      case PaymentMethod.paymentLink:
        final out = await ref
            .read(paymentRepositoryProvider)
            .createOnline(
              PaymentTarget.dues(
                farmerId: farmerId,
                storeId: storeId,
                duesAmountPaise: amount,
              ),
              mode: PaymentModes.of(method),
            );
        if (out.paymentId != null) {
          await router.push(
            method == PaymentMethod.upiQr
                ? CommerceRoutes.upi(out.paymentId!)
                : CommerceRoutes.link(out.paymentId!),
          );
        } else {
          setState(() => _message = _refusal(l10n, out.result, out.code));
        }
      case PaymentMethod.credit:
        break;
    }
  }

  String _refusal(
    CoreLocalizations l10n,
    PaymentCallResult result,
    String? code,
  ) {
    if (result == PaymentCallResult.network) return l10n.checkoutNetworkError;
    return switch (code) {
      'already_paid' => l10n.checkoutAlreadyPaid,
      'amount_mismatch' => l10n.checkoutAmountMismatch,
      'nothing_due' => l10n.checkoutNothingDue,
      'requires_network' => l10n.checkoutNeedsInternet,
      _ => l10n.checkoutRefused(code ?? '—'),
    };
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final p = app.palette;
    final l10n = CoreLocalizations.of(context);
    final offline = ref.watch(offlineProvider);
    final cart = ref.watch(cartProvider);
    final farmerId = widget.duesFarmerId ?? cart.farmerId;
    final khata = farmerId == null
        ? null
        : ref.watch(khataProvider(farmerId)).value;
    final storeId = _dues ? khata?.collectStoreId : cart.storeId;
    final balance = khata == null || storeId == null
        ? null
        : khata.balanceAt(storeId);
    if (_dues && !_amountTouched && balance != null && balance > 0) {
      _amount.text = (balance / 100).toStringAsFixed(
        balance % 100 == 0 ? 0 : 2,
      );
    }
    final limit = khata == null || storeId == null
        ? null
        : khata.limitsByStore[storeId];
    final available = <PaymentMethod>{
      if (!offline) PaymentMethod.upiQr,
      if (!offline) PaymentMethod.paymentLink,
      PaymentMethod.cash,
      if (!_dues) PaymentMethod.credit,
    };
    final reasons = <PaymentMethod, String>{
      if (offline) PaymentMethod.upiQr: l10n.checkoutNeedsInternet,
      if (offline) PaymentMethod.paymentLink: l10n.checkoutNeedsInternet,
      if (_dues) PaymentMethod.credit: l10n.checkoutCreditOrdersOnly,
    };
    final method = _method != null && available.contains(_method)
        ? _method
        : null;
    final canSubmit =
        !_busy && method != null && (_dues || cart.lines.isNotEmpty);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(l10n.checkoutTitle),
            if (farmerId != null)
              Text(
                l10n.catalogForFarmer(farmerNameOf(ref, farmerId)),
                style: app.text.caption.copyWith(color: p.textSecondary),
              ),
          ],
        ),
      ),
      bottomNavigationBar: BottomActions(
        children: <Widget>[
          AppButton(
            key: const Key('checkout-submit'),
            label: _dues ? l10n.checkoutCollect : l10n.checkoutPlaceOrder,
            icon: _dues ? Icons.currency_rupee : Icons.check,
            loading: _busy,
            onPressed: canSubmit ? _submit : null,
          ),
        ],
      ),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            const OfflineBannerLive(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(Tokens.spaceScreenPadding),
                children: <Widget>[
                  if (_dues) ...<Widget>[
                    if (balance != null)
                      Text(
                        l10n.checkoutDuesBalance(formatInr(balance)),
                        key: const Key('checkout-balance'),
                        style: app.text.body.copyWith(color: p.textSecondary),
                      ),
                    const SizedBox(height: Tokens.space2),
                    AppTextField(
                      key: const Key('checkout-amount'),
                      label: l10n.checkoutDuesAmount,
                      controller: _amount,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      prefixIcon: Icons.currency_rupee,
                      onChanged: (_) => setState(() => _amountTouched = true),
                    ),
                  ] else
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(Tokens.space3),
                        child: MoneyRow(
                          key: const Key('checkout-total'),
                          label: l10n.checkoutOrderAmount,
                          paise: cart.totals.totalPaise,
                          strong: true,
                        ),
                      ),
                    ),
                  const SizedBox(height: Tokens.space4),
                  Text(l10n.paymentMethodTitle, style: app.text.heading),
                  const SizedBox(height: Tokens.space2),
                  PaymentMethodSelector(
                    key: const Key('checkout-methods'),
                    selected: method,
                    available: available,
                    unavailableReasons: reasons,
                    creditHint: limit == null
                        ? null
                        : l10n.checkoutCreditLeft(
                            formatInr((limit - (balance ?? 0)).clamp(0, limit)),
                          ),
                    onChanged: _busy
                        ? null
                        : (m) => setState(() => _method = m),
                  ),
                  if (offline) ...<Widget>[
                    const SizedBox(height: Tokens.space3),
                    Text(
                      l10n.checkoutOfflineNote,
                      key: const Key('checkout-offline-note'),
                      style: app.text.body.copyWith(color: p.textSecondary),
                    ),
                  ],
                  if (_message != null) ...<Widget>[
                    const SizedBox(height: Tokens.space3),
                    Text(
                      _message!,
                      key: const Key('checkout-message'),
                      style: app.text.body.copyWith(color: p.statusDanger),
                    ),
                  ],
                  if (!_dues) ...<Widget>[
                    const SizedBox(height: Tokens.space3),
                    Text(
                      l10n.cartEstimateNote,
                      style: app.text.caption.copyWith(color: p.textSecondary),
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

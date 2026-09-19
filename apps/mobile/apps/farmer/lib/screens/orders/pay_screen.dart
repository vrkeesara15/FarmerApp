import 'package:farmerapp_core/farmerapp_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../router.dart';
import '../../widgets/kisan_widgets.dart';
import '../../widgets/upi_pay.dart';
import 'shop_state.dart';

/// How the farmer pays on F32.
enum KisanPayChoice {
  /// UPI: opens the phone's UPI apps.
  upi,

  /// Pay at the store when collecting.
  store,

  /// Ask the store for credit (khata); the store confirms.
  credit,
}

/// F32 Pay (FM-010): UPI (opens UPI apps with the payment intent from the
/// payments API), "Pay at store", or a credit request ("your store will
/// confirm"). One choice, then "Place order". Needs the network: the
/// server prices and reserves stock.
class PayScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const PayScreen({super.key});

  @override
  ConsumerState<PayScreen> createState() => _PayScreenState();
}

class _PayScreenState extends ConsumerState<PayScreen> {
  KisanPayChoice? _choice;
  bool _busy = false;

  Future<void> _place() async {
    final l10n = CoreLocalizations.of(context);
    final cart = ref.read(cartProvider);
    final storeId = cart.storeId ?? await ref.read(kisanStoreIdProvider.future);
    setState(() => _busy = true);
    final choice = _choice!;
    final result = await ref
        .read(kisanRepositoryProvider)
        .placeOrder(
          storeId: storeId,
          fulfilment: cart.fulfilment,
          lines: cart.lines,
          paymentMode: switch (choice) {
            KisanPayChoice.upi => PaymentModes.upiQr,
            KisanPayChoice.store => null,
            KisanPayChoice.credit => PaymentModes.credit,
          },
        );
    if (!mounted) return;
    setState(() => _busy = false);
    switch (result.write) {
      case KisanWrite.offline:
        showKisanMessage(context, l10n.kisanNeedsInternet);
        return;
      case KisanWrite.refused || KisanWrite.queued:
        if (choice == KisanPayChoice.credit &&
            result.code == OrderErrorCodes.creditLimitExceeded) {
          ref.read(cartProvider.notifier).clear();
          showKisanMessage(context, l10n.kisanCreditStoreWillConfirm);
          context.go(AppRoutes.orders);
          return;
        }
        showKisanMessage(
          context,
          result.code == OrderErrorCodes.insufficientStock
              ? l10n.kisanOrderShort
              : l10n.kisanSaveFailed,
        );
        return;
      case KisanWrite.done:
        break;
    }
    final order = result.order!;
    ref.read(cartProvider.notifier).clear();
    var message = switch (choice) {
      KisanPayChoice.store => l10n.kisanPayAtStoreNote,
      KisanPayChoice.credit => l10n.kisanCreditStoreWillConfirm,
      KisanPayChoice.upi => l10n.kisanOrderPlaced,
    };
    if (choice == KisanPayChoice.upi) {
      final paid = await payByUpi(context, ref, <String, Object?>{
        'order_id': order.id,
      });
      await ref.read(kisanRepositoryProvider).refreshOrder(order.id);
      message = paid.outcome == UpiOutcome.paid
          ? l10n.kisanPaidThanks
          : l10n.kisanNotPaidYet;
    }
    if (!mounted) return;
    showKisanMessage(context, message);
    context.go(AppRoutes.order(order.id));
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final l10n = CoreLocalizations.of(context);
    final cart = ref.watch(cartProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.kisanPayTitle)),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            if (ref.watch(offlineProvider)) const OfflineBanner(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(Tokens.spaceScreenPadding),
                children: <Widget>[
                  Text(
                    l10n.kisanTotalToPay(formatInr(cart.totals.totalPaise)),
                    key: const Key('pay-total'),
                    style: app.text.title,
                  ),
                  Text(
                    l10n.kisanTotalEstimateNote,
                    style: app.text.caption.copyWith(
                      color: app.palette.textSecondary,
                    ),
                  ),
                  const SizedBox(height: Tokens.space4),
                  SpokenText(
                    promptId: 'f32_how_pay',
                    text: l10n.kisanHowPay,
                    style: app.text.heading,
                  ),
                  const SizedBox(height: Tokens.space2),
                  for (final c in KisanPayChoice.values)
                    Padding(
                      padding: const EdgeInsets.only(bottom: Tokens.space2),
                      child: _PayOption(
                        key: Key('pay-${c.name}'),
                        choice: c,
                        selected: _choice == c,
                        onTap: () => setState(() => _choice = c),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(Tokens.spaceScreenPadding),
              child: AppButton(
                key: const Key('pay-place'),
                label: l10n.kisanPlaceOrder,
                icon: Icons.check,
                loading: _busy,
                onPressed: _choice == null || _busy || cart.lines.isEmpty
                    ? null
                    : _place,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PayOption extends StatelessWidget {
  const _PayOption({
    required this.choice,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final KisanPayChoice choice;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final p = app.palette;
    final l10n = CoreLocalizations.of(context);
    final (icon, title, help) = switch (choice) {
      KisanPayChoice.upi => (
        Icons.qr_code_2,
        l10n.kisanPayUpi,
        l10n.kisanPayUpiHelp,
      ),
      KisanPayChoice.store => (
        Icons.storefront_outlined,
        l10n.kisanPayAtStore,
        l10n.kisanPayAtStoreHelp,
      ),
      KisanPayChoice.credit => (
        Icons.menu_book_outlined,
        l10n.kisanPayCredit,
        l10n.kisanCreditStoreWillConfirm,
      ),
    };
    return Material(
      color: selected ? app.tint(p.primaryContainer) : p.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Tokens.radiusCard),
        side: BorderSide(
          color: selected ? p.primary : p.border,
          width: selected ? app.borderWidth + 1 : app.borderWidth,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(Tokens.space3),
          child: Row(
            children: <Widget>[
              Icon(icon, size: Tokens.space8, color: p.primary),
              const SizedBox(width: Tokens.space3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(title, style: app.text.heading),
                    Text(
                      help,
                      style: app.text.body.copyWith(color: p.textSecondary),
                    ),
                  ],
                ),
              ),
              Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_off,
                color: selected ? p.primary : p.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
